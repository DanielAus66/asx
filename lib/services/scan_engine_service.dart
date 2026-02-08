import '../models/stock.dart';
import '../models/scan_rule.dart';
import 'dart:math' as math;

class ScanEngineService {
  
  /// Check if rule can be evaluated with just current stock data (no historical prices needed)
  static bool canQuickEvaluate(ScanRule rule) {
    final quickTypes = {
      RuleConditionType.priceChangeAbove,
      RuleConditionType.priceChangeBelow,
      RuleConditionType.priceNear52WeekLow,
      RuleConditionType.priceNear52WeekHigh,
      RuleConditionType.nearAllTimeHigh,
    };
    return rule.conditions.every((c) => quickTypes.contains(c.type));
  }

  /// Evaluate if a stock matches all conditions in a rule
  static bool evaluateRule(Stock stock, ScanRule rule, {List<double>? prices, List<int>? volumes}) {
    for (final condition in rule.conditions) {
      if (!_evaluateCondition(stock, condition, prices: prices, volumes: volumes)) {
        return false;
      }
    }
    return true;
  }
  
  /// Smart evaluation for rules with EVENT + STATE filter combinations
  /// 
  /// For rules that contain BOTH event conditions and state filters:
  /// - At least ONE event condition must trigger (crossover today)
  /// - ALL state filters must be true (but don't need crossover)
  /// 
  /// This allows combining "52W High Crossover" (event) with 
  /// "Momentum > 5%" (state filter) - the event triggers, the filter validates
  static bool evaluateHybridRule(Stock stock, ScanRule rule, {List<double>? prices, List<int>? volumes}) {
    final eventConditions = rule.conditions.where((c) => isEventCondition(c.type)).toList();
    final stateConditions = rule.conditions.where((c) => isStateFilterCondition(c.type)).toList();
    final otherConditions = rule.conditions.where((c) => 
      !isEventCondition(c.type) && !isStateFilterCondition(c.type)
    ).toList();
    
    // If no event conditions, fall back to standard evaluation
    if (eventConditions.isEmpty) {
      return evaluateRule(stock, rule, prices: prices, volumes: volumes);
    }
    
    // At least ONE event must trigger
    bool anyEventTriggered = false;
    for (final eventCondition in eventConditions) {
      if (_evaluateCondition(stock, eventCondition, prices: prices, volumes: volumes)) {
        anyEventTriggered = true;
        break;
      }
    }
    
    if (!anyEventTriggered) return false;
    
    // ALL state filters must be true
    for (final stateCondition in stateConditions) {
      if (!_evaluateCondition(stock, stateCondition, prices: prices, volumes: volumes)) {
        return false;
      }
    }
    
    // ALL other conditions must also pass (standard AND logic)
    for (final otherCondition in otherConditions) {
      if (!_evaluateCondition(stock, otherCondition, prices: prices, volumes: volumes)) {
        return false;
      }
    }
    
    return true;
  }
  
  /// Check if a rule contains any event-based conditions
  static bool hasEventConditions(ScanRule rule) {
    return rule.conditions.any((c) => isEventCondition(c.type));
  }
  
  /// Check if a rule contains any state filter conditions  
  static bool hasStateFilters(ScanRule rule) {
    return rule.conditions.any((c) => isStateFilterCondition(c.type));
  }
  
  /// Check if a rule is a hybrid (has both events and state filters)
  static bool isHybridRule(ScanRule rule) {
    return hasEventConditions(rule) && hasStateFilters(rule);
  }

  static bool _evaluateCondition(Stock stock, RuleCondition condition, {List<double>? prices, List<int>? volumes}) {
    switch (condition.type) {
      // === ORIGINAL RULES ===
      
      case RuleConditionType.rsiBelow:
        final rsi = stock.indicators?['rsi'] as double?;
        return rsi != null && rsi < condition.value;

      case RuleConditionType.rsiAbove:
        final rsi = stock.indicators?['rsi'] as double?;
        return rsi != null && rsi > condition.value;

      case RuleConditionType.priceAboveSma:
        final smaKey = 'sma${condition.value.toInt()}';
        final sma = stock.indicators?[smaKey] as double?;
        return sma != null && stock.currentPrice > sma;

      case RuleConditionType.priceBelowSma:
        final smaKey = 'sma${condition.value.toInt()}';
        final sma = stock.indicators?[smaKey] as double?;
        return sma != null && stock.currentPrice < sma;

      case RuleConditionType.priceAboveEma:
        final emaKey = 'ema${condition.value.toInt()}';
        final ema = stock.indicators?[emaKey] as double?;
        return ema != null && stock.currentPrice > ema;

      case RuleConditionType.priceBelowEma:
        final emaKey = 'ema${condition.value.toInt()}';
        final ema = stock.indicators?[emaKey] as double?;
        return ema != null && stock.currentPrice < ema;

      case RuleConditionType.macdCrossover:
        final macd = stock.indicators?['macd'] as double?;
        final signal = stock.indicators?['macdSignal'] as double?;
        final prevMacd = stock.indicators?['prevMacd'] as double?;
        final prevSignal = stock.indicators?['prevSignal'] as double?;
        if (macd == null || signal == null) return false;
        // Current MACD > signal AND previously was below
        if (prevMacd != null && prevSignal != null) {
          return macd > signal && prevMacd <= prevSignal;
        }
        return macd > signal;

      case RuleConditionType.macdCrossunder:
        final macd = stock.indicators?['macd'] as double?;
        final signal = stock.indicators?['macdSignal'] as double?;
        if (macd == null || signal == null) return false;
        return macd < signal;

      case RuleConditionType.volumeSpike:
        if (stock.avgVolume == null || stock.avgVolume == 0) return false;
        return stock.volume > stock.avgVolume! * condition.value;

      case RuleConditionType.priceNear52WeekLow:
        if (stock.weekLow52 == null || stock.weekLow52 == 0) return false;
        final percentFromLow = ((stock.currentPrice - stock.weekLow52!) / stock.weekLow52!) * 100;
        return percentFromLow <= condition.value && percentFromLow >= 0;

      case RuleConditionType.priceNear52WeekHigh:
        if (stock.weekHigh52 == null || stock.weekHigh52 == 0) return false;
        final percentFromHigh = ((stock.weekHigh52! - stock.currentPrice) / stock.weekHigh52!) * 100;
        return percentFromHigh <= condition.value && percentFromHigh >= 0;

      case RuleConditionType.bollingerBreakout:
        final upperBB = stock.indicators?['bbUpper'] as double?;
        return upperBB != null && stock.currentPrice > upperBB;

      case RuleConditionType.priceChangeAbove:
        return stock.changePercent >= condition.value;

      case RuleConditionType.priceChangeBelow:
        return stock.changePercent <= condition.value;

      // === NEW MOMENTUM RULES ===
      
      case RuleConditionType.momentum6Month:
        // 6-month return, skipping last 20 trading days
        if (prices == null || prices.length < 150) return false;
        const skipDays = 20;
        const lookbackDays = 126; // ~6 months of trading days
        if (prices.length < skipDays + lookbackDays) return false;
        
        final currentIdx = prices.length - 1 - skipDays;
        final startIdx = currentIdx - lookbackDays;
        if (startIdx < 0) return false;
        
        final startPrice = prices[startIdx];
        final endPrice = prices[currentIdx];
        if (startPrice <= 0) return false;
        
        final returnPct = ((endPrice - startPrice) / startPrice) * 100;
        return returnPct >= condition.value;

      case RuleConditionType.momentum12Month:
        // 12-month return, skipping last 20 trading days
        if (prices == null || prices.length < 270) return false;
        const skipDays = 20;
        const lookbackDays = 252; // ~12 months of trading days
        if (prices.length < skipDays + lookbackDays) return false;
        
        final currentIdx = prices.length - 1 - skipDays;
        final startIdx = currentIdx - lookbackDays;
        if (startIdx < 0) return false;
        
        final startPrice = prices[startIdx];
        final endPrice = prices[currentIdx];
        if (startPrice <= 0) return false;
        
        final returnPct = ((endPrice - startPrice) / startPrice) * 100;
        return returnPct >= condition.value;

      // === NEW 52-WEEK HIGH PROXIMITY (George & Hwang) ===
      
      case RuleConditionType.nearAllTimeHigh:
        // Within X% of 52-week HIGH (the winning strategy!)
        if (stock.weekHigh52 == null || stock.weekHigh52 == 0) return false;
        final percentFromHigh = ((stock.weekHigh52! - stock.currentPrice) / stock.weekHigh52!) * 100;
        return percentFromHigh <= condition.value && percentFromHigh >= 0;

      // === NEW BREAKOUT RULES ===
      
      case RuleConditionType.breakoutNDayHigh:
        // Price breaks above N-day high
        if (prices == null || prices.length < condition.value.toInt() + 1) return false;
        final lookback = condition.value.toInt();
        final recentPrices = prices.sublist(prices.length - lookback - 1, prices.length - 1);
        final nDayHigh = recentPrices.reduce(math.max);
        return stock.currentPrice > nDayHigh;

      case RuleConditionType.breakoutHeld:
        // Breakout held for X days (price stayed above breakout level)
        if (prices == null || prices.length < condition.value.toInt() + 50) return false;
        final holdDays = condition.value.toInt();
        final breakoutLevel = prices.sublist(0, prices.length - holdDays - 50).reduce(math.max);
        // Check if all recent days are above breakout level
        final recentPrices = prices.sublist(prices.length - holdDays);
        return recentPrices.every((p) => p >= breakoutLevel * 0.98); // 2% tolerance

      // === NEW VCP (VOLATILITY CONTRACTION) ===
      
      case RuleConditionType.vcpSetup:
        // Contracting ATR - volatility getting tighter
        if (prices == null || prices.length < 50) return false;
        final atr1 = _calculateATR(prices, 14, offset: 30); // ATR 30 days ago
        final atr2 = _calculateATR(prices, 14, offset: 0);  // Current ATR
        if (atr1 == null || atr2 == null || atr1 == 0) return false;
        // ATR should have contracted by at least 20%
        return atr2 < atr1 * 0.8;

      case RuleConditionType.bollingerSqueeze:
        // Bollinger Band width is contracting (squeeze)
        final bbWidth = stock.indicators?['bbWidth'] as double?;
        if (bbWidth == null) {
          // Calculate from prices if not in indicators
          if (prices == null || prices.length < 20) return false;
          final calculatedWidth = _calculateBBWidth(prices);
          return calculatedWidth != null && calculatedWidth < condition.value;
        }
        return bbWidth < condition.value;

      // === NEW VOLUME/FLOW RULES ===
      
      case RuleConditionType.stealthAccumulation:
        // High volume (> Xx average) but flat price (< ±1%)
        if (stock.avgVolume == null || stock.avgVolume == 0) return false;
        final volumeMultiple = stock.volume / stock.avgVolume!;
        final priceFlat = stock.changePercent.abs() < 1.0;
        return volumeMultiple >= condition.value && priceFlat;

      case RuleConditionType.obvDivergence:
        // OBV rising while price is flat or down
        if (prices == null || volumes == null || prices.length < 20 || volumes.length < 20) return false;
        
        // Calculate OBV trend
        final obvTrend = _calculateOBVTrend(prices, volumes, 20);
        if (obvTrend == null) return false;
        
        // Price should be flat or down over same period
        final priceChange = (prices.last - prices[prices.length - 20]) / prices[prices.length - 20] * 100;
        
        // OBV should be rising (positive trend) while price is flat/down
        return obvTrend > 0.1 && priceChange < 2; // OBV up, price not up much

      // === NEW REVERSAL ===
      
      case RuleConditionType.oversoldBounce:
        // Dropped X%+ in last 3 days
        if (prices == null || prices.length < 5) return false;
        final threeDaysAgo = prices[prices.length - 4];
        final current = prices.last;
        if (threeDaysAgo <= 0) return false;
        final dropPercent = ((threeDaysAgo - current) / threeDaysAgo) * 100;
        return dropPercent >= condition.value;

      // === EARNINGS & INSIDER (placeholder - needs external API) ===
      
      case RuleConditionType.earningsSurprise:
        // Requires Finnhub API - check indicators for cached data
        final epsSurprise = stock.indicators?['epsSurprise'] as double?;
        return epsSurprise != null && epsSurprise >= condition.value;

      case RuleConditionType.insiderBuying:
        // Requires ASX announcements scraping - check indicators
        final insiderBuy = stock.indicators?['insiderBuying'] as bool?;
        return insiderBuy == true;
      
      // === EVENT-BASED RULES (with crossover detection) ===
      
      case RuleConditionType.event52WeekHighCrossover:
        // Rule 1: 52-Week High Proximity Event
        // Trigger ONCE when: today >= 97% of 252-day high AND yesterday < 97%
        // Do NOT trigger if: price > 105% of prior high (already broken out)
        if (prices == null || prices.length < 30) return false;
        
        final todayClose52w = prices.last;
        final yesterdayClose52w = prices[prices.length - 2];
        
        // Calculate rolling high (use available data, up to 252 days)
        final availableDays = prices.length - 1;
        final lookbackDays = availableDays > 252 ? 252 : availableDays;
        final priorPrices52w = prices.sublist(prices.length - 1 - lookbackDays, prices.length - 1);
        final high252 = priorPrices52w.reduce((a, b) => a > b ? a : b);
        
        if (high252 <= 0) return false;
        
        final thresholdPercent52w = condition.value; // default 97%
        final threshold52w = high252 * (thresholdPercent52w / 100);
        
        // Today crosses INTO the high zone
        final todayInZone = todayClose52w >= threshold52w;
        final yesterdayOutOfZone = yesterdayClose52w < threshold52w;
        
        // Don't trigger if already broken out too far (> 105% of prior high)
        final notTooFar = todayClose52w <= high252 * 1.05;
        
        return todayInZone && yesterdayOutOfZone && notTooFar;
        
      case RuleConditionType.eventVolumeBreakout:
        // Rule 2: Volume Breakout Event
        // Trigger ONCE when: today's volume >= 1.5x avg AND yesterday < 1.5x avg
        // Do NOT trigger if: close < prior close OR day change > ±8% (earnings gap)
        if (prices == null || volumes == null || volumes.length < 32 || prices.length < 2) return false;
        
        final todayVolumeEvt = volumes.last;
        final yesterdayVolumeEvt = volumes[volumes.length - 2];
        
        // Calculate 30-day average volume (excluding today and yesterday)
        final priorVolumesEvt = volumes.sublist(0, volumes.length - 2);
        if (priorVolumesEvt.length < 30) return false;
        final avgVol30 = priorVolumesEvt.sublist(priorVolumesEvt.length - 30).reduce((a, b) => a + b) / 30;
        
        if (avgVol30 <= 0) return false;
        
        final multiplierVol = condition.value; // default 1.5x
        final thresholdVol = avgVol30 * multiplierVol;
        
        // Today crosses above threshold, yesterday was below
        final todayAboveVol = todayVolumeEvt >= thresholdVol;
        final yesterdayBelowVol = yesterdayVolumeEvt < thresholdVol;
        
        // Price filters: close > prior close AND not a gap day
        final todayPriceVol = prices.last;
        final yesterdayPriceVol = prices[prices.length - 2];
        final closeHigherVol = todayPriceVol > yesterdayPriceVol;
        final dayChangeVol = ((todayPriceVol - yesterdayPriceVol) / yesterdayPriceVol).abs() * 100;
        final notGapDay = dayChangeVol < 8; // Filter out earnings/news gaps
        
        return todayAboveVol && yesterdayBelowVol && closeHigherVol && notGapDay;
        
      case RuleConditionType.eventMomentumCrossover:
        // Rule 3: 6-Month Momentum Crossover Event
        // Trigger ONCE when: today's 6M return >= threshold AND yesterday's < threshold
        // Do NOT trigger if: 5-day spike > 15% (sharp short-term move)
        if (prices == null || prices.length < 30) return false;
        
        final momentumThresholdVal = condition.value; // default 10%
        
        // Use available data up to 126 trading days
        final availableDaysMom = prices.length;
        final lookbackMom = availableDaysMom > 127 ? 126 : availableDaysMom - 2;
        
        if (lookbackMom < 20) return false; // Need at least 20 days of data
        
        // Today's momentum return
        final todayMom = prices.last;
        final startIndexToday = prices.length - 1 - lookbackMom;
        final sixMonthsAgoToday = prices[startIndexToday];
        if (sixMonthsAgoToday <= 0) return false;
        final todayReturnMom = ((todayMom - sixMonthsAgoToday) / sixMonthsAgoToday) * 100;
        
        // Yesterday's momentum return
        final yesterdayMom = prices[prices.length - 2];
        final startIndexYesterday = prices.length - 2 - lookbackMom;
        if (startIndexYesterday < 0) return false;
        final sixMonthsAgoYesterday = prices[startIndexYesterday];
        if (sixMonthsAgoYesterday <= 0) return false;
        final yesterdayReturnMom = ((yesterdayMom - sixMonthsAgoYesterday) / sixMonthsAgoYesterday) * 100;
        
        // Crossover: today above threshold, yesterday below
        final todayAboveThreshold = todayReturnMom >= momentumThresholdVal;
        final yesterdayBelowThreshold = yesterdayReturnMom < momentumThresholdVal;
        
        // Filter out sharp short-term spikes (5-day return > 15%)
        bool notShortTermSpike = true;
        if (prices.length > 5) {
          final fiveDaysAgoMom = prices[prices.length - 6];
          if (fiveDaysAgoMom > 0) {
            final fiveDayReturnMom = ((todayMom - fiveDaysAgoMom) / fiveDaysAgoMom) * 100;
            notShortTermSpike = fiveDayReturnMom < 15;
          }
        }
        
        return todayAboveThreshold && yesterdayBelowThreshold && notShortTermSpike;
      
      // === STATE FILTER RULES ===
      // These check if a condition is currently TRUE (no crossover required)
      // Perfect for combining with event triggers
      
      case RuleConditionType.stateMomentumPositive:
        // Check if momentum is above threshold (state, not event)
        // Uses available data, adapts to shorter periods if needed
        if (prices == null || prices.length < 22) return false;
        
        final currentPriceMom = prices.last;
        // Use 6-month (126 days) if available, otherwise use what we have
        final lookbackMomState = prices.length > 126 ? 126 : prices.length - 1;
        final startPriceMom = prices[prices.length - 1 - lookbackMomState];
        if (startPriceMom <= 0) return false;
        
        final momentumReturn = ((currentPriceMom - startPriceMom) / startPriceMom) * 100;
        return momentumReturn >= condition.value; // e.g., > 5%
        
      case RuleConditionType.stateVolumeExpanding:
        // Check if recent volume (10d avg) > longer term volume (20d prior avg)
        // Indicates accumulation / increasing interest
        if (volumes == null || volumes.length < 22) return false;
        
        // Recent 10-day average
        final recentVolEnd = volumes.length;
        final recentVolStart = volumes.length - 10;
        final recentVol10 = volumes.sublist(recentVolStart, recentVolEnd);
        
        // Prior 10-day average (days 11-20 ago)
        final priorVolEnd = volumes.length - 10;
        final priorVolStart = priorVolEnd - 10 > 0 ? priorVolEnd - 10 : 0;
        final priorVol10 = volumes.sublist(priorVolStart, priorVolEnd);
        
        if (recentVol10.isEmpty || priorVol10.isEmpty) return false;
        
        final avgRecent = recentVol10.reduce((a, b) => a + b) / recentVol10.length;
        final avgPrior = priorVol10.reduce((a, b) => a + b) / priorVol10.length;
        
        if (avgPrior <= 0) return false;
        
        // Volume expansion: recent avg at least 10% higher than prior avg (relaxed from 20%)
        return avgRecent > avgPrior * 1.1;
        
      case RuleConditionType.stateAboveSma50:
        // Check if price is above 50-day SMA
        if (prices == null || prices.length < 50) return false;
        
        final recent50 = prices.sublist(prices.length - 50);
        final sma50 = recent50.reduce((a, b) => a + b) / 50;
        
        return prices.last > sma50;
        
      case RuleConditionType.stateUptrend:
        // Check if stock is in uptrend (higher highs and higher lows over 20 days)
        // Simplified: compare 20-day midpoint to 10-day midpoint
        if (prices == null || prices.length < 20) return false;
        
        // First half (days 1-10)
        final firstHalf = prices.sublist(prices.length - 20, prices.length - 10);
        final firstHalfHigh = firstHalf.reduce((a, b) => a > b ? a : b);
        final firstHalfLow = firstHalf.reduce((a, b) => a < b ? a : b);
        
        // Second half (days 11-20, more recent)
        final secondHalf = prices.sublist(prices.length - 10);
        final secondHalfHigh = secondHalf.reduce((a, b) => a > b ? a : b);
        final secondHalfLow = secondHalf.reduce((a, b) => a < b ? a : b);
        
        // Uptrend: recent highs higher AND recent lows higher
        return secondHalfHigh >= firstHalfHigh && secondHalfLow >= firstHalfLow;
        
      case RuleConditionType.stateNear52WeekHigh:
        // Check if price is near 52-week high (state, not requiring crossover today)
        // This is for live scans where we want stocks that are CURRENTLY near highs
        if (prices == null || prices.length < 20) return false;
        
        final currentPriceHigh = prices.last;
        
        // Calculate high from available data (up to 252 days)
        final availDays = prices.length;
        final lookback = availDays > 252 ? 252 : availDays;
        final historicalPricesHigh = prices.sublist(prices.length - lookback);
        final highPrice = historicalPricesHigh.reduce((a, b) => a > b ? a : b);
        
        if (highPrice <= 0) return false;
        
        // Check if current price is within threshold of high
        // condition.value is the threshold (e.g., 95 means within 5% of high)
        final thresholdPct = condition.value / 100; // e.g., 95 -> 0.95
        return currentPriceHigh >= highPrice * thresholdPct;
    }
  }

  /// Calculate Average True Range
  static double? _calculateATR(List<double> prices, int period, {int offset = 0}) {
    if (prices.length < period + offset + 1) return null;
    
    final endIdx = prices.length - offset;
    final startIdx = endIdx - period;
    if (startIdx < 1) return null;
    
    double sumTR = 0;
    for (int i = startIdx; i < endIdx; i++) {
      final high = prices[i]; // Simplified - using close as proxy
      final low = prices[i] * 0.98; // Estimate low as 2% below close
      final prevClose = prices[i - 1];
      
      final tr = [
        high - low,
        (high - prevClose).abs(),
        (low - prevClose).abs(),
      ].reduce(math.max);
      
      sumTR += tr;
    }
    
    return sumTR / period;
  }

  /// Calculate Bollinger Band width as percentage
  static double? _calculateBBWidth(List<double> prices) {
    if (prices.length < 20) return null;
    
    final recent = prices.sublist(prices.length - 20);
    final sma = recent.reduce((a, b) => a + b) / recent.length;
    
    double sumSquares = 0;
    for (final p in recent) {
      sumSquares += math.pow(p - sma, 2);
    }
    final stdDev = math.sqrt(sumSquares / recent.length);
    
    final upperBB = sma + (2 * stdDev);
    final lowerBB = sma - (2 * stdDev);
    
    if (sma == 0) return null;
    return ((upperBB - lowerBB) / sma) * 100;
  }

  /// Calculate OBV trend (simplified - returns normalized slope)
  static double? _calculateOBVTrend(List<double> prices, List<int> volumes, int period) {
    if (prices.length < period || volumes.length < period) return null;
    
    final startIdx = prices.length - period;
    double obv = 0;
    List<double> obvValues = [];
    
    for (int i = startIdx; i < prices.length; i++) {
      if (i > startIdx) {
        if (prices[i] > prices[i - 1]) {
          obv += volumes[i];
        } else if (prices[i] < prices[i - 1]) {
          obv -= volumes[i];
        }
      }
      obvValues.add(obv);
    }
    
    if (obvValues.length < 2) return null;
    
    // Simple trend: compare first half average to second half average
    final firstHalf = obvValues.sublist(0, obvValues.length ~/ 2);
    final secondHalf = obvValues.sublist(obvValues.length ~/ 2);
    
    final firstAvg = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
    final secondAvg = secondHalf.reduce((a, b) => a + b) / secondHalf.length;
    
    // Normalize by volume scale
    final avgVolume = volumes.sublist(startIdx).reduce((a, b) => a + b) / period;
    if (avgVolume == 0) return null;
    
    return (secondAvg - firstAvg) / (avgVolume * period) * 100;
  }
}