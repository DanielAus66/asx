import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'database_service.dart';

/// ASIC Short Position data for ASX stocks
/// Source: https://download.asic.gov.au/short-selling/
/// Published daily at T+4 (4 business days after trade date)
/// No authentication required. CSV format ~500KB.
class ShortInterestService {
  static const String _baseUrl = 'https://download.asic.gov.au/short-selling';
  
  // Cache the latest fetch date to avoid redundant downloads
  static DateTime? _lastFetchDate;
  static Map<String, ShortPositionData> _cache = {};

  /// Fetch today's (or most recent) short position report from ASIC
  /// Returns number of records parsed, or -1 on failure
  static Future<int> fetchDailyReport() async {
    // Try today, then work backwards up to 7 days to find latest report
    // (reports aren't published on weekends/holidays)
    final now = DateTime.now();
    
    for (int daysBack = 0; daysBack < 7; daysBack++) {
      final targetDate = now.subtract(Duration(days: daysBack));
      
      // Skip weekends
      if (targetDate.weekday == DateTime.saturday || targetDate.weekday == DateTime.sunday) {
        continue;
      }
      
      // Skip if we already fetched this date
      if (_lastFetchDate != null && 
          _lastFetchDate!.year == targetDate.year &&
          _lastFetchDate!.month == targetDate.month &&
          _lastFetchDate!.day == targetDate.day) {
        print('SHORT: Already fetched ${DateFormat('yyyy-MM-dd').format(targetDate)}');
        return _cache.length;
      }
      
      final dateStr = DateFormat('yyyyMMdd').format(targetDate);
      final url = '$_baseUrl/RR$dateStr-001-SSDailyAggShortPos.csv';
      
      print('SHORT: Trying $url');
      
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {'Accept': 'text/csv'},
        ).timeout(const Duration(seconds: 30));
        
        if (response.statusCode == 200 && response.body.contains('Product Code')) {
          final records = _parseCsv(response.body, targetDate);
          
          if (records.isNotEmpty) {
            _cache = records;
            _lastFetchDate = targetDate;
            
            // Persist to SQLite
            await _saveToDatabase(records, targetDate);
            
            print('SHORT: Parsed ${records.length} records for $dateStr');
            return records.length;
          }
        }
      } catch (e) {
        print('SHORT: Failed for $dateStr: $e');
      }
    }
    
    print('SHORT: No reports found in last 7 days');
    return -1;
  }

  /// Parse ASIC CSV into structured data
  /// CSV format: Product, Product Code, Reported Short Positions, Total Product in Issue, % Short
  static Map<String, ShortPositionData> _parseCsv(String csv, DateTime tradeDate) {
    final Map<String, ShortPositionData> result = {};
    final lines = const LineSplitter().convert(csv);
    
    // Skip header line
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      
      // Parse CSV - handle commas in product names by using lastIndexOf
      // Format: "PRODUCT NAME,CODE,SHORT_POS,TOTAL_ISSUED,SHORT_PCT"
      final parts = line.split(',');
      if (parts.length < 5) continue;
      
      try {
        // Product Code is always the second-to-last 4 fields
        // Work backwards: pct, total, short_pos, code, ...name parts
        final shortPct = double.tryParse(parts.last.trim()) ?? 0;
        final totalIssued = int.tryParse(parts[parts.length - 2].trim()) ?? 0;
        final shortPositions = int.tryParse(parts[parts.length - 3].trim()) ?? 0;
        final code = parts[parts.length - 4].trim();
        final productName = parts.sublist(0, parts.length - 4).join(',').trim();
        
        if (code.isEmpty || code.length > 5 || shortPositions == 0) continue;
        
        // Skip non-equity products (bonds, ETF units with long codes, etc.)
        if (code.contains(' ') || code.startsWith('GSB')) continue;
        
        result[code] = ShortPositionData(
          symbol: code,
          productName: productName,
          shortPositions: shortPositions,
          totalIssued: totalIssued,
          shortPercent: shortPct,
          tradeDate: tradeDate,
        );
      } catch (e) {
        // Skip malformed lines
        continue;
      }
    }
    
    return result;
  }

  /// Get short position data for a specific stock
  static ShortPositionData? getShortData(String asxCode) {
    // Remove .AX suffix if present
    final code = asxCode.replaceAll('.AX', '').toUpperCase();
    return _cache[code];
  }

  /// Get short % for a stock (convenience)
  static double getShortPercent(String asxCode) {
    return getShortData(asxCode)?.shortPercent ?? 0;
  }

  /// Get short interest change vs previous day
  /// Requires at least 2 days of data in SQLite
  static Future<double?> getShortChangePercent(String asxCode) async {
    final code = asxCode.replaceAll('.AX', '').toUpperCase();
    
    try {
      final db = await DatabaseService.getDatabase();
      if (db == null) return null;
      
      final rows = await db.query(
        'short_interest',
        where: 'symbol = ?',
        whereArgs: [code],
        orderBy: 'trade_date DESC',
        limit: 2,
      );
      
      if (rows.length < 2) return null;
      
      final today = (rows[0]['short_percent'] as num).toDouble();
      final yesterday = (rows[1]['short_percent'] as num).toDouble();
      
      if (yesterday == 0) return null;
      return today - yesterday; // Absolute change in short %
    } catch (e) {
      return null;
    }
  }

  /// Calculate days to cover: short positions / avg daily volume
  static double? getDaysToCover(String asxCode, int avgDailyVolume) {
    if (avgDailyVolume <= 0) return null;
    final data = getShortData(asxCode);
    if (data == null) return null;
    return data.shortPositions / avgDailyVolume;
  }

  /// Get all stocks with short interest above threshold
  static List<ShortPositionData> getHighlyShorted({double minPercent = 5.0}) {
    return _cache.values
        .where((d) => d.shortPercent >= minPercent)
        .toList()
      ..sort((a, b) => b.shortPercent.compareTo(a.shortPercent));
  }

  /// Get top N most shorted stocks
  static List<ShortPositionData> getTopShorted({int count = 20}) {
    final sorted = _cache.values.toList()
      ..sort((a, b) => b.shortPercent.compareTo(a.shortPercent));
    return sorted.take(count).toList();
  }

  /// Check if short interest is rising (increased in latest report)
  static Future<bool> isShortInterestRising(String asxCode, {double minChange = 0.5}) async {
    final change = await getShortChangePercent(asxCode);
    return change != null && change >= minChange;
  }

  /// Save to SQLite for historical tracking
  static Future<void> _saveToDatabase(Map<String, ShortPositionData> records, DateTime tradeDate) async {
    try {
      final db = await DatabaseService.getDatabase();
      if (db == null) return;
      
      // Ensure table exists
      await db.execute('''
        CREATE TABLE IF NOT EXISTS short_interest (
          symbol TEXT NOT NULL,
          trade_date TEXT NOT NULL,
          short_positions INTEGER NOT NULL,
          total_issued INTEGER NOT NULL,
          short_percent REAL NOT NULL,
          fetched_at TEXT NOT NULL,
          PRIMARY KEY (symbol, trade_date)
        )
      ''');
      
      final dateStr = DateFormat('yyyy-MM-dd').format(tradeDate);
      final now = DateTime.now().toIso8601String();
      
      // Batch insert using transaction
      await db.transaction((txn) async {
        for (final entry in records.entries) {
          await txn.rawInsert('''
            INSERT OR REPLACE INTO short_interest 
            (symbol, trade_date, short_positions, total_issued, short_percent, fetched_at)
            VALUES (?, ?, ?, ?, ?, ?)
          ''', [entry.key, dateStr, entry.value.shortPositions, entry.value.totalIssued, entry.value.shortPercent, now]);
        }
      });
      
      // Prune old data (keep 60 days)
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      await db.delete('short_interest', where: 'trade_date < ?', whereArgs: [DateFormat('yyyy-MM-dd').format(cutoff)]);
      
    } catch (e) {
      print('SHORT DB ERROR: $e');
    }
  }

  /// Load cached data from SQLite on app startup
  static Future<void> loadFromDatabase() async {
    try {
      final db = await DatabaseService.getDatabase();
      if (db == null) return;
      
      // Check table exists
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='short_interest'");
      if (tables.isEmpty) return;
      
      // Get most recent date
      final latest = await db.rawQuery('SELECT MAX(trade_date) as latest FROM short_interest');
      if (latest.isEmpty || latest.first['latest'] == null) return;
      
      final latestDate = latest.first['latest'] as String;
      
      // Load that day's data into cache
      final rows = await db.query('short_interest', where: 'trade_date = ?', whereArgs: [latestDate]);
      
      _cache.clear();
      for (final row in rows) {
        final code = row['symbol'] as String;
        _cache[code] = ShortPositionData(
          symbol: code,
          productName: '',
          shortPositions: (row['short_positions'] as int?) ?? 0,
          totalIssued: (row['total_issued'] as int?) ?? 0,
          shortPercent: (row['short_percent'] as num?)?.toDouble() ?? 0,
          tradeDate: DateTime.parse(latestDate),
        );
      }
      
      _lastFetchDate = DateTime.parse(latestDate);
      print('SHORT: Loaded ${_cache.length} records from cache ($latestDate)');
    } catch (e) {
      print('SHORT: Failed to load from DB: $e');
    }
  }

  /// Get short interest history for a stock (for charts)
  static Future<List<Map<String, dynamic>>> getHistory(String asxCode, {int days = 30}) async {
    final code = asxCode.replaceAll('.AX', '').toUpperCase();
    try {
      final db = await DatabaseService.getDatabase();
      if (db == null) return [];
      
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final rows = await db.query(
        'short_interest',
        where: 'symbol = ? AND trade_date >= ?',
        whereArgs: [code, DateFormat('yyyy-MM-dd').format(cutoff)],
        orderBy: 'trade_date ASC',
      );
      
      return rows.map((r) {
        return <String, dynamic>{
          'date': r['trade_date'],
          'shortPercent': (r['short_percent'] as num?)?.toDouble() ?? 0,
          'shortPositions': r['short_positions'],
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }
}

/// Short position data for a single stock
class ShortPositionData {
  final String symbol;
  final String productName;
  final int shortPositions;
  final int totalIssued;
  final double shortPercent;
  final DateTime tradeDate;

  ShortPositionData({
    required this.symbol,
    required this.productName,
    required this.shortPositions,
    required this.totalIssued,
    required this.shortPercent,
    required this.tradeDate,
  });

  /// Formatted short percent string
  String get formattedPercent => '${shortPercent.toStringAsFixed(2)}%';

  /// Human-readable short positions
  String get formattedPositions {
    if (shortPositions >= 1000000) return '${(shortPositions / 1000000).toStringAsFixed(1)}M';
    if (shortPositions >= 1000) return '${(shortPositions / 1000).toStringAsFixed(0)}K';
    return shortPositions.toString();
  }

  /// Is this considered "heavily shorted"? (>5% is common threshold)
  bool get isHeavilyShorted => shortPercent >= 5.0;

  @override
  String toString() => '$symbol: $formattedPercent short ($formattedPositions shares)';
}
