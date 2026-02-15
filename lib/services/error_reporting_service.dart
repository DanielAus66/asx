import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Centralized error reporting service
/// Captures errors with context, maintains a local log ring buffer,
/// and is ready for Sentry/Firebase Crashlytics integration.
///
/// To enable Sentry, add `sentry_flutter` to pubspec.yaml and
/// uncomment the Sentry calls below.
class ErrorReportingService {
  static final ErrorReportingService _instance = ErrorReportingService._();
  factory ErrorReportingService() => _instance;
  ErrorReportingService._();

  /// Ring buffer of recent errors (last 100)
  static final Queue<ErrorRecord> _errorLog = Queue<ErrorRecord>();
  static const int _maxLogSize = 100;
  
  /// Error counts by category for diagnostics
  static final Map<String, int> _errorCounts = {};
  
  /// Initialize - call in main() before runApp
  static Future<void> initialize() async {
    // Setup Flutter error handler
    FlutterError.onError = (FlutterErrorDetails details) {
      report(
        details.exception,
        stackTrace: details.stack,
        context: 'FlutterError: ${details.context?.toString() ?? 'unknown'}',
        category: ErrorCategory.ui,
      );
      // Also forward to default handler for debug console
      FlutterError.presentError(details);
    };
    
    // Uncomment when adding Sentry:
    // await SentryFlutter.init((options) {
    //   options.dsn = 'YOUR_SENTRY_DSN';
    //   options.tracesSampleRate = 0.2;
    //   options.environment = kReleaseMode ? 'production' : 'development';
    // });
    
    print('ErrorReportingService initialized');
  }
  
  /// Report an error with optional context
  static void report(
    dynamic error, {
    StackTrace? stackTrace,
    String? context,
    ErrorCategory category = ErrorCategory.general,
    ErrorSeverity severity = ErrorSeverity.error,
  }) {
    final record = ErrorRecord(
      error: error.toString(),
      stackTrace: stackTrace?.toString(),
      context: context,
      category: category,
      severity: severity,
      timestamp: DateTime.now(),
    );
    
    // Add to ring buffer
    _errorLog.addFirst(record);
    if (_errorLog.length > _maxLogSize) {
      _errorLog.removeLast();
    }
    
    // Increment category counter
    final key = category.name;
    _errorCounts[key] = (_errorCounts[key] ?? 0) + 1;
    
    // Log to console in debug mode
    if (kDebugMode) {
      print('ERROR [${category.name}/${severity.name}] ${context ?? ''}: $error');
      if (stackTrace != null && severity == ErrorSeverity.fatal) {
        print(stackTrace);
      }
    }
    
    // Uncomment when adding Sentry:
    // Sentry.captureException(error, stackTrace: stackTrace);
  }
  
  /// Report a non-fatal warning
  static void warn(String message, {String? context, ErrorCategory category = ErrorCategory.general}) {
    report(message, context: context, category: category, severity: ErrorSeverity.warning);
  }
  
  /// Report an API error with endpoint info
  static void reportApiError(dynamic error, {required String endpoint, int? statusCode, StackTrace? stackTrace}) {
    report(
      error,
      stackTrace: stackTrace,
      context: 'API $endpoint (status: ${statusCode ?? 'unknown'})',
      category: ErrorCategory.api,
      severity: statusCode == 429 ? ErrorSeverity.warning : ErrorSeverity.error,
    );
  }
  
  /// Report a data parsing error
  static void reportParseError(dynamic error, {required String source, StackTrace? stackTrace}) {
    report(
      error,
      stackTrace: stackTrace,
      context: 'Parse error in $source',
      category: ErrorCategory.data,
    );
  }
  
  /// Get recent error log (for diagnostics screen)
  static List<ErrorRecord> get recentErrors => _errorLog.toList();
  
  /// Get error counts by category
  static Map<String, int> get errorCounts => Map.unmodifiable(_errorCounts);
  
  /// Get total error count since app start
  static int get totalErrors => _errorCounts.values.fold(0, (a, b) => a + b);
  
  /// Clear error log
  static void clearLog() {
    _errorLog.clear();
    _errorCounts.clear();
  }
  
  /// Check if there have been recent API failures (for UI indicators)
  static bool get hasRecentApiErrors {
    return _errorLog.any((e) => 
      e.category == ErrorCategory.api && 
      e.timestamp.isAfter(DateTime.now().subtract(const Duration(minutes: 5)))
    );
  }
}

enum ErrorCategory {
  general,
  api,
  data,
  ui,
  storage,
  scan,
  backtest,
}

enum ErrorSeverity {
  warning,
  error,
  fatal,
}

class ErrorRecord {
  final String error;
  final String? stackTrace;
  final String? context;
  final ErrorCategory category;
  final ErrorSeverity severity;
  final DateTime timestamp;

  ErrorRecord({
    required this.error,
    this.stackTrace,
    this.context,
    required this.category,
    required this.severity,
    required this.timestamp,
  });
  
  @override
  String toString() => '[$timestamp] ${severity.name}/${category.name}: ${context ?? ''} $error';
}
