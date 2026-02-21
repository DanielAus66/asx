import 'dart:convert';
import 'package:http/http.dart' as http;
import 'database_service.dart';

/// ASX announcement categories derived from title parsing
enum AnnouncementCategory {
  earnings,
  directorTrade,
  capitalRaise,
  tradingHalt,
  tradingResumption,
  substantialHolder,
  dividend,
  agm,
  priceSensitive,
  other,
}

/// Single ASX company announcement
class AsxAnnouncement {
  final String id;
  final String symbol;
  final String title;
  final DateTime releaseDate;
  final AnnouncementCategory category;
  final bool isMarketSensitive;
  final String? documentUrl;
  final int? numPages;
  final DateTime fetchedAt;

  AsxAnnouncement({
    required this.id,
    required this.symbol,
    required this.title,
    required this.releaseDate,
    required this.category,
    this.isMarketSensitive = false,
    this.documentUrl,
    this.numPages,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  /// How many days ago was this announcement?
  int get daysAgo => DateTime.now().difference(releaseDate).inDays;

  /// Human-readable category label
  String get categoryLabel {
    switch (category) {
      case AnnouncementCategory.earnings: return '📊 Earnings';
      case AnnouncementCategory.directorTrade: return '👤 Director Trade';
      case AnnouncementCategory.capitalRaise: return '💰 Capital Raise';
      case AnnouncementCategory.tradingHalt: return '⛔ Trading Halt';
      case AnnouncementCategory.tradingResumption: return '▶️ Resumed';
      case AnnouncementCategory.substantialHolder: return '🏦 Substantial Holder';
      case AnnouncementCategory.dividend: return '💵 Dividend';
      case AnnouncementCategory.agm: return '🏛️ AGM';
      case AnnouncementCategory.priceSensitive: return '⚡ Price Sensitive';
      case AnnouncementCategory.other: return '📄 Announcement';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'symbol': symbol, 'title': title,
    'releaseDate': releaseDate.toIso8601String(),
    'category': category.index,
    'isMarketSensitive': isMarketSensitive,
    'documentUrl': documentUrl, 'numPages': numPages,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  factory AsxAnnouncement.fromJson(Map<String, dynamic> json) => AsxAnnouncement(
    id: json['id'] ?? '',
    symbol: json['symbol'] ?? '',
    title: json['title'] ?? '',
    releaseDate: DateTime.tryParse(json['releaseDate'] ?? '') ?? DateTime.now(),
    category: AnnouncementCategory.values[(json['category'] as int?) ?? 9],
    isMarketSensitive: json['isMarketSensitive'] ?? false,
    documentUrl: json['documentUrl'],
    numPages: json['numPages'],
    fetchedAt: DateTime.tryParse(json['fetchedAt'] ?? ''),
  );
}

/// Service for fetching and caching ASX company announcements
/// Uses the MarkitDigital API that powers asx.com.au
class AnnouncementService {
  static const String _apiBase = 'https://asx.api.markitdigital.com/asx-research/1.0';
  
  // In-memory cache: symbol -> list of announcements
  static final Map<String, List<AsxAnnouncement>> _cache = {};
  static final Map<String, DateTime> _lastFetch = {};
  
  // Cache TTL: 15 minutes during market hours, 60 minutes otherwise
  static Duration get _cacheTtl {
    final now = DateTime.now();
    final hour = now.hour;
    // Market hours are roughly 10:00-16:30 AEST
    if (hour >= 10 && hour <= 17 && now.weekday <= 5) {
      return const Duration(minutes: 15);
    }
    return const Duration(minutes: 60);
  }

  /// Fetch announcements for a stock
  /// Returns cached data if fresh enough
  static Future<List<AsxAnnouncement>> fetchAnnouncements(String asxCode, {int count = 20}) async {
    final code = asxCode.replaceAll('.AX', '').toUpperCase();
    
    // Check cache freshness
    final lastFetch = _lastFetch[code];
    if (lastFetch != null && DateTime.now().difference(lastFetch) < _cacheTtl) {
      return _cache[code] ?? [];
    }
    
    try {
      final url = '$_apiBase/companies/$code/announcements?count=$count&market_sensitive=false';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
          'Referer': 'https://www.asx.com.au/',
          'Origin': 'https://www.asx.com.au',
        },
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = json['data'] as List? ?? [];
        
        final announcements = data.map((item) {
          final title = (item['header'] ?? '') as String;
          final relDate = item['document_release_date'] ?? item['document_date'] ?? '';
          
          return AsxAnnouncement(
            id: (item['id'] ?? '${code}_${DateTime.now().millisecondsSinceEpoch}') as String,
            symbol: code,
            title: title,
            releaseDate: DateTime.tryParse(relDate) ?? DateTime.now(),
            category: classifyAnnouncement(title, item['market_sensitive'] == true),
            isMarketSensitive: item['market_sensitive'] == true,
            documentUrl: item['url'] as String?,
            numPages: item['number_of_pages'] as int?,
          );
        }).toList();
        
        _cache[code] = announcements;
        _lastFetch[code] = DateTime.now();
        
        // Persist to SQLite
        await _saveToDatabase(announcements);
        
        return announcements;
      }
      
      print('ANNOUNCEMENTS: API returned ${response.statusCode} for $code');
    } catch (e) {
      print('ANNOUNCEMENTS: Error fetching $code: $e');
    }
    
    // Fallback to cached/DB data
    return _cache[code] ?? await _loadFromDatabase(code);
  }

  /// Classify announcement by title pattern matching
  /// This is deterministic and fast — no ML or PDF parsing needed
  static AnnouncementCategory classifyAnnouncement(String title, bool isMarketSensitive) {
    final lower = title.toLowerCase();
    
    // Trading halt / suspension (check first - highest priority)
    if (lower.contains('trading halt') || 
        lower.contains('suspension from quotation') ||
        lower.contains('voluntary suspension')) {
      return AnnouncementCategory.tradingHalt;
    }
    
    // Trading resumption
    if (lower.contains('reinstatement to quotation') || 
        lower.contains('reinstatement to official') ||
        lower.contains('trading resumes')) {
      return AnnouncementCategory.tradingResumption;
    }
    
    // Earnings / Results
    if (lower.contains('profit announcement') || 
        lower.contains('half year result') || lower.contains('half-year result') ||
        lower.contains('full year result') || lower.contains('full-year result') ||
        lower.contains('quarterly report') || lower.contains('quarterly activities') ||
        lower.contains('appendix 4d') || lower.contains('appendix 4e') ||
        lower.contains('appendix 4c') ||
        lower.contains('annual report') ||
        lower.contains('financial results') ||
        lower.contains('earnings') ||
        (lower.contains('4c') && lower.contains('quarterly')) ||
        (lower.contains('4d') && (lower.contains('statement') || lower.contains('preliminary')))) {
      return AnnouncementCategory.earnings;
    }
    
    // Director trades (Appendix 3Y)
    if (lower.contains('appendix 3y') || 
        lower.contains('director interest') ||
        lower.contains('change of director') ||
        lower.contains('initial director') ||
        lower.contains('final director') ||
        lower.contains('ceasing to be a director')) {
      return AnnouncementCategory.directorTrade;
    }
    
    // Substantial holder
    if (lower.contains('substantial holder') || 
        lower.contains('becoming a substantial') ||
        lower.contains('ceasing to be a substantial')) {
      return AnnouncementCategory.substantialHolder;
    }
    
    // Capital raise
    if (lower.contains('placement') || 
        lower.contains('share purchase plan') || lower.contains('spp') ||
        lower.contains('rights issue') || lower.contains('entitlement offer') ||
        lower.contains('capital raising') || lower.contains('prospectus') ||
        lower.contains('cleansing notice') ||
        (lower.contains('issue') && lower.contains('shares'))) {
      return AnnouncementCategory.capitalRaise;
    }
    
    // Dividend
    if (lower.contains('dividend') || lower.contains('distribution')) {
      return AnnouncementCategory.dividend;
    }
    
    // AGM
    if (lower.contains('agm') || lower.contains('annual general meeting') ||
        lower.contains('notice of meeting')) {
      return AnnouncementCategory.agm;
    }
    
    // Generic price sensitive
    if (isMarketSensitive) {
      return AnnouncementCategory.priceSensitive;
    }
    
    return AnnouncementCategory.other;
  }

  // ── Scan condition helpers ──

  /// Check if stock has announcement of given category within N days
  static Future<bool> hasAnnouncementWithinDays(
    String asxCode, 
    int days, 
    {AnnouncementCategory? category}
  ) async {
    final announcements = await fetchAnnouncements(asxCode);
    final cutoff = DateTime.now().subtract(Duration(days: days));
    
    return announcements.any((a) {
      final dateMatch = a.releaseDate.isAfter(cutoff);
      final categoryMatch = category == null || a.category == category;
      return dateMatch && categoryMatch;
    });
  }

  /// Check if stock has earnings announcement within N days
  static Future<bool> hasEarningsWithinDays(String asxCode, int days) async {
    return hasAnnouncementWithinDays(asxCode, days, category: AnnouncementCategory.earnings);
  }

  /// Check if stock has director trade (Appendix 3Y) within N days
  static Future<bool> hasDirectorTradeWithinDays(String asxCode, int days) async {
    return hasAnnouncementWithinDays(asxCode, days, category: AnnouncementCategory.directorTrade);
  }

  /// Check if stock is in a trading halt
  static Future<bool> isInTradingHalt(String asxCode) async {
    final announcements = await fetchAnnouncements(asxCode, count: 5);
    if (announcements.isEmpty) return false;
    
    // Check most recent halt-related announcements
    for (final ann in announcements) {
      if (ann.category == AnnouncementCategory.tradingResumption) return false;
      if (ann.category == AnnouncementCategory.tradingHalt) return true;
    }
    return false;
  }

  /// Check if stock resumed from halt within N days
  static Future<bool> resumedFromHaltWithinDays(String asxCode, int days) async {
    return hasAnnouncementWithinDays(asxCode, days, category: AnnouncementCategory.tradingResumption);
  }

  /// Check if stock has market-sensitive announcement within N days
  static Future<bool> hasMarketSensitiveWithinDays(String asxCode, int days) async {
    final announcements = await fetchAnnouncements(asxCode);
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return announcements.any((a) => a.isMarketSensitive && a.releaseDate.isAfter(cutoff));
  }

  /// Get the most recent announcement for a stock
  static Future<AsxAnnouncement?> getLatest(String asxCode) async {
    final announcements = await fetchAnnouncements(asxCode, count: 1);
    return announcements.isNotEmpty ? announcements.first : null;
  }

  /// Get announcements summary for display in stock detail
  static Future<Map<String, dynamic>> getAnnouncementSummary(String asxCode) async {
    final announcements = await fetchAnnouncements(asxCode);
    final now = DateTime.now();
    
    return {
      'total': announcements.length,
      'last7d': announcements.where((a) => now.difference(a.releaseDate).inDays <= 7).length,
      'last30d': announcements.where((a) => now.difference(a.releaseDate).inDays <= 30).length,
      'hasEarnings7d': announcements.any((a) => a.category == AnnouncementCategory.earnings && now.difference(a.releaseDate).inDays <= 7),
      'hasDirectorTrade14d': announcements.any((a) => a.category == AnnouncementCategory.directorTrade && now.difference(a.releaseDate).inDays <= 14),
      'isHalted': announcements.isNotEmpty && announcements.first.category == AnnouncementCategory.tradingHalt,
      'latestTitle': announcements.isNotEmpty ? announcements.first.title : null,
      'latestDate': announcements.isNotEmpty ? announcements.first.releaseDate : null,
      'latestCategory': announcements.isNotEmpty ? announcements.first.categoryLabel : null,
    };
  }

  // ── Database persistence ──

  static Future<void> _saveToDatabase(List<AsxAnnouncement> announcements) async {
    try {
      final db = await DatabaseService.getDatabase();
      if (db == null) return;
      
      await db.execute('''
        CREATE TABLE IF NOT EXISTS announcements (
          id TEXT PRIMARY KEY,
          symbol TEXT NOT NULL,
          title TEXT NOT NULL,
          release_date TEXT NOT NULL,
          category INTEGER NOT NULL,
          is_market_sensitive INTEGER DEFAULT 0,
          document_url TEXT,
          num_pages INTEGER,
          fetched_at TEXT NOT NULL
        )
      ''');
      
      await db.transaction((txn) async {
        for (final ann in announcements) {
          await txn.rawInsert('''
            INSERT OR REPLACE INTO announcements 
            (id, symbol, title, release_date, category, is_market_sensitive, document_url, num_pages, fetched_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''', [
            ann.id, ann.symbol, ann.title, ann.releaseDate.toIso8601String(),
            ann.category.index, ann.isMarketSensitive ? 1 : 0,
            ann.documentUrl, ann.numPages, ann.fetchedAt.toIso8601String(),
          ]);
        }
      });
      
      // Prune announcements older than 90 days
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      await db.delete('announcements', where: 'release_date < ?', whereArgs: [cutoff.toIso8601String()]);
    } catch (e) {
      print('ANNOUNCEMENTS DB ERROR: $e');
    }
  }

  static Future<List<AsxAnnouncement>> _loadFromDatabase(String code) async {
    try {
      final db = await DatabaseService.getDatabase();
      if (db == null) return [];
      
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='announcements'");
      if (tables.isEmpty) return [];
      
      final rows = await db.query(
        'announcements',
        where: 'symbol = ?',
        whereArgs: [code],
        orderBy: 'release_date DESC',
        limit: 20,
      );
      
      return rows.map((r) => AsxAnnouncement(
        id: r['id'] as String,
        symbol: r['symbol'] as String,
        title: r['title'] as String,
        releaseDate: DateTime.parse(r['release_date'] as String),
        category: AnnouncementCategory.values[(r['category'] as int?) ?? 9],
        isMarketSensitive: (r['is_market_sensitive'] as int?) == 1,
        documentUrl: r['document_url'] as String?,
        numPages: r['num_pages'] as int?,
        fetchedAt: DateTime.tryParse(r['fetched_at'] as String? ?? ''),
      )).toList();
    } catch (e) {
      return [];
    }
  }

  /// Clear all cached data
  static void clearCache() {
    _cache.clear();
    _lastFetch.clear();
  }
}
