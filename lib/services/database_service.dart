import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/stock.dart';
import '../models/watchlist_item.dart';
import '../models/scan_rule.dart';
import '../models/holding.dart';
import 'error_reporting_service.dart';

/// SQLite-backed storage service - replaces SharedPreferences for large data
/// Handles watchlist, rules, alerts, stock cache, and holdings
/// 
/// Migration: On first run, imports existing SharedPreferences data,
/// then uses SQLite going forward. SharedPreferences kept for small settings only.
class DatabaseService {
  static Database? _db;
  static const int _dbVersion = 2;
  static const String _dbName = 'asx_radar.db';

  /// Public accessor for database instance (used by fundamental data services)
  static Future<Database?> getDatabase() async {
    if (_db == null) await initialize();
    return _db;
  }

  /// Initialize database - call once at app startup
  static Future<void> initialize() async {
    if (_db != null) return;
    
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    
    print('DatabaseService initialized at $path');
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE watchlist (
        symbol TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        added_price REAL NOT NULL,
        added_at TEXT NOT NULL,
        capital_invested REAL DEFAULT 10000,
        trigger_rule TEXT,
        trigger_rules TEXT,
        current_price REAL,
        day_change REAL,
        day_change_percent REAL
      )
    ''');
    
    await db.execute('''
      CREATE TABLE rules (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL
      )
    ''');
    
    await db.execute('''
      CREATE TABLE alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_read INTEGER DEFAULT 0
      )
    ''');
    
    await db.execute('''
      CREATE TABLE stock_cache (
        symbol TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    
    await db.execute('''
      CREATE TABLE holdings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        data TEXT NOT NULL
      )
    ''');
    
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    
    // Create indexes for common queries
    await db.execute('CREATE INDEX idx_alerts_created ON alerts(created_at DESC)');
    await db.execute('CREATE INDEX idx_stock_cache_updated ON stock_cache(updated_at)');

    // === Phase 2: Fundamental data tables ===
    await _createFundamentalTables(db);
  }

  /// Create tables for fundamental data (announcements, short interest, halt status)
  static Future<void> _createFundamentalTables(Database db) async {
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ann_symbol ON announcements(symbol)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ann_date ON announcements(release_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ann_category ON announcements(category)');

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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_short_symbol ON short_interest(symbol)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS halt_status (
        symbol TEXT PRIMARY KEY,
        is_halted INTEGER DEFAULT 0,
        halt_type TEXT,
        halt_date TEXT,
        resume_date TEXT,
        resume_announcement_id TEXT
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2: Add fundamental data tables (announcements, short interest, halt status)
      await _createFundamentalTables(db);
      print('DatabaseService: Migrated to v2 (fundamental data tables)');
    }
  }

  /// Get database instance (auto-initializes)
  static Future<Database> get db async {
    if (_db == null) await initialize();
    return _db!;
  }

  // ===== WATCHLIST =====
  
  static Future<List<WatchlistItem>> loadWatchlist() async {
    try {
      final database = await db;
      final rows = await database.query('watchlist', orderBy: 'added_at DESC');
      return rows.map((row) => WatchlistItem(
        symbol: row['symbol'] as String,
        name: row['name'] as String,
        addedPrice: row['added_price'] as double,
        addedAt: DateTime.parse(row['added_at'] as String),
        capitalInvested: (row['capital_invested'] as num?)?.toDouble() ?? 10000,
        triggerRule: row['trigger_rule'] as String?,
        triggerRules: row['trigger_rules'] != null 
          ? (jsonDecode(row['trigger_rules'] as String) as List).cast<String>()
          : [],
        currentPrice: row['current_price'] as double?,
        dayChange: row['day_change'] as double?,
        dayChangePercent: row['day_change_percent'] as double?,
      )).toList();
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'loadWatchlist', category: ErrorCategory.storage);
      return [];
    }
  }

  static Future<void> saveWatchlist(List<WatchlistItem> items) async {
    try {
      final database = await db;
      await database.transaction((txn) async {
        await txn.delete('watchlist');
        for (final item in items) {
          await txn.insert('watchlist', {
            'symbol': item.symbol,
            'name': item.name,
            'added_price': item.addedPrice,
            'added_at': item.addedAt.toIso8601String(),
            'capital_invested': item.capitalInvested,
            'trigger_rule': item.triggerRule,
            'trigger_rules': jsonEncode(item.triggerRules),
            'current_price': item.currentPrice,
            'day_change': item.dayChange,
            'day_change_percent': item.dayChangePercent,
          });
        }
      });
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'saveWatchlist', category: ErrorCategory.storage);
    }
  }

  // ===== RULES =====
  
  static Future<List<ScanRule>> loadRules() async {
    try {
      final database = await db;
      final rows = await database.query('rules');
      if (rows.isEmpty) {
        await saveRules(defaultRules);
        return defaultRules;
      }
      final rules = rows.map((row) => ScanRule.fromJson(jsonDecode(row['data'] as String))).toList();
      // Add any new default rules not yet in DB
      for (final defaultRule in defaultRules) {
        if (!rules.any((r) => r.id == defaultRule.id)) {
          rules.add(defaultRule);
        }
      }
      return rules;
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'loadRules', category: ErrorCategory.storage);
      return defaultRules;
    }
  }

  static Future<void> saveRules(List<ScanRule> rules) async {
    try {
      final database = await db;
      await database.transaction((txn) async {
        await txn.delete('rules');
        for (final rule in rules) {
          await txn.insert('rules', {
            'id': rule.id,
            'data': jsonEncode(rule.toJson()),
          });
        }
      });
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'saveRules', category: ErrorCategory.storage);
    }
  }

  // ===== ALERTS =====
  
  static Future<List<Map<String, dynamic>>> loadAlerts() async {
    try {
      final database = await db;
      final rows = await database.query('alerts', orderBy: 'created_at DESC', limit: 100);
      return rows.map((row) {
        final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        data['isRead'] = row['is_read'] == 1;
        return data;
      }).toList();
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'loadAlerts', category: ErrorCategory.storage);
      return [];
    }
  }

  static Future<void> saveAlerts(List<Map<String, dynamic>> alerts) async {
    try {
      final database = await db;
      await database.transaction((txn) async {
        await txn.delete('alerts');
        for (final alert in alerts) {
          await txn.insert('alerts', {
            'data': jsonEncode(alert),
            'created_at': alert['timestamp'] ?? DateTime.now().toIso8601String(),
            'is_read': alert['isRead'] == true ? 1 : 0,
          });
        }
      });
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'saveAlerts', category: ErrorCategory.storage);
    }
  }

  static Future<void> addAlert(Map<String, dynamic> alert) async {
    try {
      final database = await db;
      await database.insert('alerts', {
        'data': jsonEncode(alert),
        'created_at': alert['timestamp'] ?? DateTime.now().toIso8601String(),
        'is_read': 0,
      });
      // Trim to 100 alerts
      await database.execute('''
        DELETE FROM alerts WHERE id NOT IN (
          SELECT id FROM alerts ORDER BY created_at DESC LIMIT 100
        )
      ''');
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'addAlert', category: ErrorCategory.storage);
    }
  }

  // ===== STOCK CACHE =====
  
  static Future<Map<String, Stock>> loadStockCache() async {
    try {
      final database = await db;
      // Only return cache less than 1 minute old
      final cutoff = DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
      final rows = await database.query('stock_cache', where: 'updated_at > ?', whereArgs: [cutoff]);
      final result = <String, Stock>{};
      for (final row in rows) {
        try {
          result[row['symbol'] as String] = Stock.fromJson(jsonDecode(row['data'] as String));
        } catch (_) {}
      }
      return result;
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'loadStockCache', category: ErrorCategory.storage);
      return {};
    }
  }

  static Future<void> saveStockCache(Map<String, Stock> stocks) async {
    try {
      final database = await db;
      final now = DateTime.now().toIso8601String();
      final batch = database.batch();
      for (final entry in stocks.entries) {
        batch.insert('stock_cache', {
          'symbol': entry.key,
          'data': jsonEncode(entry.value.toJson()),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'saveStockCache', category: ErrorCategory.storage);
    }
  }

  // ===== HOLDINGS =====
  
  static Future<List<Holding>> loadHoldings() async {
    try {
      final database = await db;
      final rows = await database.query('holdings');
      return rows.map((row) => Holding.fromJson(jsonDecode(row['data'] as String))).toList();
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'loadHoldings', category: ErrorCategory.storage);
      return [];
    }
  }

  static Future<void> saveHoldings(List<Holding> holdings) async {
    try {
      final database = await db;
      await database.transaction((txn) async {
        await txn.delete('holdings');
        for (final holding in holdings) {
          await txn.insert('holdings', {
            'data': jsonEncode(holding.toJson()),
          });
        }
      });
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'saveHoldings', category: ErrorCategory.storage);
    }
  }

  // ===== SETTINGS =====
  
  static Future<Map<String, dynamic>> loadSettings() async {
    try {
      final database = await db;
      final rows = await database.query('settings');
      final result = <String, dynamic>{};
      for (final row in rows) {
        result[row['key'] as String] = jsonDecode(row['value'] as String);
      }
      return result;
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'loadSettings', category: ErrorCategory.storage);
      return {};
    }
  }

  static Future<void> saveSetting(String key, dynamic value) async {
    try {
      final database = await db;
      await database.insert('settings', {
        'key': key,
        'value': jsonEncode(value),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'saveSetting', category: ErrorCategory.storage);
    }
  }

  // ===== MIGRATION FROM SHARED PREFERENCES =====
  
  /// Migrate existing SharedPreferences data to SQLite
  /// Call once on first launch after update
  static Future<bool> migrateFromSharedPreferences() async {
    try {
      final database = await db;
      
      // Check if migration already done
      final migrated = await database.query('settings', where: 'key = ?', whereArgs: ['migration_done']);
      if (migrated.isNotEmpty) return false;
      
      // Import from StorageService (SharedPreferences)
      // This is done lazily - the StorageService import is handled by the caller
      await saveSetting('migration_done', true);
      await saveSetting('migrated_at', DateTime.now().toIso8601String());
      
      print('DatabaseService: Migration from SharedPreferences complete');
      return true;
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'migrateFromSharedPreferences', category: ErrorCategory.storage);
      return false;
    }
  }

  // ===== CLEANUP =====
  
  static Future<void> clearAll() async {
    try {
      final database = await db;
      await database.delete('watchlist');
      await database.delete('rules');
      await database.delete('alerts');
      await database.delete('stock_cache');
      await database.delete('holdings');
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'clearAll', category: ErrorCategory.storage);
    }
  }

  /// Clean up old stock cache entries (older than 1 hour)
  static Future<void> pruneStockCache() async {
    try {
      final database = await db;
      final cutoff = DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();
      await database.delete('stock_cache', where: 'updated_at < ?', whereArgs: [cutoff]);
    } catch (e, st) {
      ErrorReportingService.report(e, stackTrace: st, context: 'pruneStockCache', category: ErrorCategory.storage);
    }
  }

  /// Close database
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
