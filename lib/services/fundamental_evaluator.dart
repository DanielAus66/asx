import '../models/scan_rule.dart';
import '../models/stock.dart';
import 'short_interest_service.dart';
import 'announcement_service.dart';

/// Evaluates fundamental (non-technical) scan conditions
/// Call this alongside your existing technical evaluator in scan_engine_service.dart
///
/// Usage in scan_engine_service.dart:
/// ```dart
/// // After evaluating technical conditions...
/// for (final condition in rule.conditions) {
///   if (isFundamentalCondition(condition.type)) {
///     final passed = await FundamentalEvaluator.evaluate(condition, stock);
///     if (!passed) { allPassed = false; break; }
///   }
/// }
/// ```
class FundamentalEvaluator {

  /// Evaluate a single fundamental condition against a stock
  /// Returns true if the condition is met
  static Future<bool> evaluate(RuleCondition condition, Stock stock) async {
    final symbol = stock.symbol; // e.g., 'BHP.AX'

    switch (condition.type) {
      // ── Announcement conditions ──
      
      case RuleConditionType.announcementWithinDays:
        return AnnouncementService.hasAnnouncementWithinDays(
          symbol, condition.value.toInt());
      
      case RuleConditionType.earningsWithinDays:
        return AnnouncementService.hasEarningsWithinDays(
          symbol, condition.value.toInt());
      
      case RuleConditionType.directorTradeWithinDays:
        return AnnouncementService.hasDirectorTradeWithinDays(
          symbol, condition.value.toInt());
      
      case RuleConditionType.capitalRaiseWithinDays:
        return AnnouncementService.hasAnnouncementWithinDays(
          symbol, condition.value.toInt(), 
          category: AnnouncementCategory.capitalRaise);
      
      case RuleConditionType.marketSensitiveWithinDays:
        return AnnouncementService.hasMarketSensitiveWithinDays(
          symbol, condition.value.toInt());

      // ── Short interest conditions ──
      
      case RuleConditionType.shortInterestAbove:
        final shortPct = ShortInterestService.getShortPercent(symbol);
        return shortPct >= condition.value;
      
      case RuleConditionType.shortInterestBelow:
        final shortPct = ShortInterestService.getShortPercent(symbol);
        return shortPct > 0 && shortPct <= condition.value;
      
      case RuleConditionType.shortInterestRising:
        return ShortInterestService.isShortInterestRising(
          symbol, minChange: condition.value > 0 ? condition.value : 0.5);
      
      case RuleConditionType.daysToCoverAbove:
        final dtc = ShortInterestService.getDaysToCover(
          symbol, stock.volume.toInt());
        return dtc != null && dtc >= condition.value;

      // ── Trading status conditions ──
      
      case RuleConditionType.isNotHalted:
        final halted = await AnnouncementService.isInTradingHalt(symbol);
        return !halted;
      
      case RuleConditionType.resumedFromHalt:
        return AnnouncementService.resumedFromHaltWithinDays(
          symbol, condition.value.toInt());

      // Not a fundamental condition — should not reach here
      default:
        return true;
    }
  }

  /// Evaluate all fundamental conditions for a rule against a stock
  /// Returns true only if ALL fundamental conditions pass
  static Future<bool> evaluateAll(ScanRule rule, Stock stock) async {
    for (final condition in rule.conditions) {
      if (isFundamentalCondition(condition.type)) {
        final passed = await evaluate(condition, stock);
        if (!passed) return false;
      }
    }
    return true;
  }

  /// Pre-fetch fundamental data for a batch of stocks
  /// Call this before scanning to warm the caches
  /// Only fetches for stocks on watchlist to avoid rate limits
  static Future<void> prefetch(List<String> watchlistSymbols) async {
    // Short interest: single bulk download (covers all stocks)
    await ShortInterestService.fetchDailyReport();
    
    // Announcements: fetch per-stock (only for watchlist to respect rate limits)
    for (final symbol in watchlistSymbols) {
      try {
        await AnnouncementService.fetchAnnouncements(symbol, count: 10);
        // Small delay to avoid hammering the API
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        print('PREFETCH: Failed for $symbol: $e');
      }
    }
  }

  /// Initialize fundamental data services on app startup
  static Future<void> initialize() async {
    // Load cached short interest from SQLite
    await ShortInterestService.loadFromDatabase();
    
    // Try to fetch fresh data (non-blocking)
    ShortInterestService.fetchDailyReport().catchError((e) {
      print('FUNDAMENTAL INIT: Short interest fetch failed: $e');
    });
  }
}

/// Helper to check if a condition type requires fundamental data
/// Add this to scan_rule.dart or import it where needed
bool isFundamentalCondition(RuleConditionType type) {
  switch (type) {
    case RuleConditionType.announcementWithinDays:
    case RuleConditionType.earningsWithinDays:
    case RuleConditionType.directorTradeWithinDays:
    case RuleConditionType.capitalRaiseWithinDays:
    case RuleConditionType.marketSensitiveWithinDays:
    case RuleConditionType.shortInterestAbove:
    case RuleConditionType.shortInterestBelow:
    case RuleConditionType.shortInterestRising:
    case RuleConditionType.daysToCoverAbove:
    case RuleConditionType.isNotHalted:
    case RuleConditionType.resumedFromHalt:
      return true;
    default:
      return false;
  }
}
