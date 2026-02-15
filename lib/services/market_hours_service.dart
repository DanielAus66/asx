/// Service to determine ASX market status
/// ASX trading hours: 10:00 AM - 4:00 PM AEST (UTC+10) / AEDT (UTC+11)
/// Pre-open: 7:00 AM - 10:00 AM
/// Trading days: Monday to Friday (excluding public holidays)
class MarketHoursService {
  // Major ASX public holidays (2025-2026, month-day format for recurring)
  // These are approximate - in production, fetch from ASX calendar API
  static final List<DateTime> _publicHolidays2025 = [
    DateTime(2025, 1, 1),   // New Year's Day
    DateTime(2025, 1, 27),  // Australia Day
    DateTime(2025, 4, 18),  // Good Friday
    DateTime(2025, 4, 21),  // Easter Monday
    DateTime(2025, 4, 25),  // ANZAC Day
    DateTime(2025, 6, 9),   // Queen's Birthday (NSW)
    DateTime(2025, 12, 25), // Christmas Day
    DateTime(2025, 12, 26), // Boxing Day
  ];
  
  static final List<DateTime> _publicHolidays2026 = [
    DateTime(2026, 1, 1),   // New Year's Day
    DateTime(2026, 1, 26),  // Australia Day
    DateTime(2026, 4, 3),   // Good Friday
    DateTime(2026, 4, 6),   // Easter Monday
    DateTime(2026, 4, 27),  // ANZAC Day (observed Monday)
    DateTime(2026, 6, 8),   // Queen's Birthday (NSW)
    DateTime(2026, 12, 25), // Christmas Day
    DateTime(2026, 12, 28), // Boxing Day (observed Monday)
  ];

  /// Get current ASX market status
  static MarketStatus getMarketStatus({DateTime? now}) {
    final aestNow = _toAEST(now ?? DateTime.now().toUtc());
    
    // Check weekend
    if (aestNow.weekday == DateTime.saturday || aestNow.weekday == DateTime.sunday) {
      return MarketStatus(
        isOpen: false,
        statusText: 'Market Closed',
        detailText: 'Weekend — reopens Monday 10:00 AM AEST',
        nextEvent: _nextMarketOpen(aestNow),
        phase: MarketPhase.closed,
      );
    }
    
    // Check public holidays
    if (_isPublicHoliday(aestNow)) {
      return MarketStatus(
        isOpen: false,
        statusText: 'Market Closed',
        detailText: 'Public Holiday',
        nextEvent: _nextMarketOpen(aestNow),
        phase: MarketPhase.holiday,
      );
    }
    
    final hour = aestNow.hour;
    final minute = aestNow.minute;
    final timeMinutes = hour * 60 + minute;
    
    // Pre-open: 7:00 AM - 10:00 AM AEST
    if (timeMinutes >= 420 && timeMinutes < 600) {
      final minsToOpen = 600 - timeMinutes;
      return MarketStatus(
        isOpen: false,
        statusText: 'Pre-Market',
        detailText: 'Opens in ${_formatDuration(minsToOpen)}',
        nextEvent: _todayAt(aestNow, 10, 0),
        phase: MarketPhase.preMarket,
      );
    }
    
    // Trading: 10:00 AM - 4:00 PM AEST (960 = 16:00)
    if (timeMinutes >= 600 && timeMinutes < 960) {
      final minsToClose = 960 - timeMinutes;
      return MarketStatus(
        isOpen: true,
        statusText: 'Market Open',
        detailText: 'Closes in ${_formatDuration(minsToClose)}',
        nextEvent: _todayAt(aestNow, 16, 0),
        phase: MarketPhase.trading,
      );
    }
    
    // After hours: 4:00 PM onwards
    if (timeMinutes >= 960) {
      return MarketStatus(
        isOpen: false,
        statusText: 'Market Closed',
        detailText: 'Closed at 4:00 PM — prices as of close',
        nextEvent: _nextMarketOpen(aestNow),
        phase: MarketPhase.afterHours,
      );
    }
    
    // Before 7 AM
    return MarketStatus(
      isOpen: false,
      statusText: 'Market Closed',
      detailText: 'Pre-market opens 7:00 AM AEST',
      nextEvent: _todayAt(aestNow, 7, 0),
      phase: MarketPhase.closed,
    );
  }
  
  /// Convert UTC to AEST/AEDT
  /// AEST = UTC+10, AEDT = UTC+11 (first Sunday of October to first Sunday of April)
  static DateTime _toAEST(DateTime utc) {
    final isDST = _isDaylightSaving(utc);
    return utc.add(Duration(hours: isDST ? 11 : 10));
  }
  
  /// Check if date is during Australian Eastern Daylight Time
  static bool _isDaylightSaving(DateTime utc) {
    // DST in Australia: first Sunday of October to first Sunday of April
    final month = utc.month;
    if (month >= 4 && month < 10) return false;
    if (month > 10 || month < 4) return true; // Nov-Mar always DST
    
    // October: DST starts first Sunday
    if (month == 10) {
      final firstSunday = DateTime(utc.year, 10, 1);
      while (firstSunday.weekday != DateTime.sunday) {
        // Find first Sunday
      }
      // Simplified: assume DST from October 1
      return utc.day >= 7; // Approximate
    }
    // April: DST ends first Sunday
    if (month == 4) {
      return utc.day < 7; // Approximate
    }
    return false;
  }
  
  static bool _isPublicHoliday(DateTime aestDate) {
    final date = DateTime(aestDate.year, aestDate.month, aestDate.day);
    final holidays = aestDate.year == 2025 ? _publicHolidays2025 : 
                     aestDate.year == 2026 ? _publicHolidays2026 : <DateTime>[];
    return holidays.any((h) => h.year == date.year && h.month == date.month && h.day == date.day);
  }
  
  static DateTime _todayAt(DateTime aestNow, int hour, int minute) {
    return DateTime(aestNow.year, aestNow.month, aestNow.day, hour, minute);
  }
  
  static DateTime _nextMarketOpen(DateTime aestNow) {
    var next = DateTime(aestNow.year, aestNow.month, aestNow.day + 1, 10, 0);
    // Skip weekends and holidays
    while (next.weekday == DateTime.saturday || 
           next.weekday == DateTime.sunday || 
           _isPublicHoliday(next)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }
  
  static String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}

enum MarketPhase {
  preMarket,
  trading,
  afterHours,
  closed,
  holiday,
}

class MarketStatus {
  final bool isOpen;
  final String statusText;
  final String detailText;
  final DateTime nextEvent;
  final MarketPhase phase;
  
  const MarketStatus({
    required this.isOpen,
    required this.statusText,
    required this.detailText,
    required this.nextEvent,
    required this.phase,
  });
}
