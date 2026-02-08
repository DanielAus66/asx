enum RuleConditionType {
  // Original rules
  rsiBelow, rsiAbove, priceAboveSma, priceBelowSma, priceAboveEma, priceBelowEma,
  macdCrossover, macdCrossunder, volumeSpike, priceNear52WeekLow, priceNear52WeekHigh,
  bollingerBreakout, priceChangeAbove, priceChangeBelow,
  
  // NEW: Momentum rules (Evidence-based)
  momentum6Month,        // 6-month return (skip last 20 days)
  momentum12Month,       // 12-month return (skip last 20 days)
  
  // NEW: 52-Week High Proximity (George & Hwang 2004)
  nearAllTimeHigh,       // Within X% of 52-week HIGH (not low!)
  
  // NEW: Breakout rules
  breakoutNDayHigh,      // Price breaks above N-day high
  breakoutHeld,          // Breakout held for X days
  
  // NEW: Volatility Contraction Pattern
  vcpSetup,              // Contracting ATR/BB width + breakout
  bollingerSqueeze,      // Bollinger Band width contracting
  
  // NEW: Volume/Flow rules
  stealthAccumulation,   // High volume + flat price (< ±1%)
  obvDivergence,         // OBV rising, price flat/down
  
  // NEW: Reversal
  oversoldBounce,        // Sharp drop (-10% to -20% in 1-3 days)
  
  // NEW: Earnings & Insider (requires external API)
  earningsSurprise,      // Positive EPS beat
  insiderBuying,         // Director on-market purchases
  
  // === EVENT-BASED RULES (with crossover detection) ===
  // These trigger ONCE when crossing a threshold
  
  // Rule 1: 52-Week High Proximity Event (EOD)
  event52WeekHighCrossover,
  
  // Rule 2: Volume Breakout Event (EOD)
  eventVolumeBreakout,
  
  // Rule 3: 6-Month Momentum Event (EOD)  
  eventMomentumCrossover,
  
  // === STATE FILTER RULES ===
  // These check if a condition is TRUE (no crossover required)
  // Use as filters alongside event triggers
  
  // State: 6-month momentum is positive/above threshold
  stateMomentumPositive,
  
  // State: Recent volume expansion (avg volume last 10d > avg volume last 30d)
  stateVolumeExpanding,
  
  // State: Price above key moving average
  stateAboveSma50,
  
  // State: In uptrend (higher highs, higher lows over 20 days)
  stateUptrend,
  
  // State: Near 52-week high (within X% of high)
  stateNear52WeekHigh,
}

/// Helper to check if a condition type is an EVENT (triggers once on crossover)
bool isEventCondition(RuleConditionType type) {
  return type == RuleConditionType.event52WeekHighCrossover ||
         type == RuleConditionType.eventVolumeBreakout ||
         type == RuleConditionType.eventMomentumCrossover;
}

/// Helper to check if a condition type is a STATE FILTER (just needs to be true)
bool isStateFilterCondition(RuleConditionType type) {
  return type == RuleConditionType.stateMomentumPositive ||
         type == RuleConditionType.stateVolumeExpanding ||
         type == RuleConditionType.stateAboveSma50 ||
         type == RuleConditionType.stateUptrend ||
         type == RuleConditionType.stateNear52WeekHigh;
}

class RuleCondition {
  final RuleConditionType type;
  final double value;
  final String? parameter;

  RuleCondition({required this.type, required this.value, this.parameter});

  int? get period {
    if (type == RuleConditionType.priceAboveSma || 
        type == RuleConditionType.priceBelowSma ||
        type == RuleConditionType.priceAboveEma ||
        type == RuleConditionType.priceBelowEma ||
        type == RuleConditionType.breakoutNDayHigh) {
      return value.toInt();
    }
    return null;
  }

  Map<String, dynamic> toJson() => {'type': type.index, 'value': value, 'parameter': parameter};

  factory RuleCondition.fromJson(Map<String, dynamic> json) => RuleCondition(
    type: RuleConditionType.values[json['type'] ?? 0],
    value: (json['value'] ?? 0.0).toDouble(),
    parameter: json['parameter'],
  );

  String get description {
    switch (type) {
      // Original
      case RuleConditionType.rsiBelow: return 'RSI < ${value.toInt()}';
      case RuleConditionType.rsiAbove: return 'RSI > ${value.toInt()}';
      case RuleConditionType.priceAboveSma: return 'Price > SMA(${value.toInt()})';
      case RuleConditionType.priceBelowSma: return 'Price < SMA(${value.toInt()})';
      case RuleConditionType.priceAboveEma: return 'Price > EMA(${value.toInt()})';
      case RuleConditionType.priceBelowEma: return 'Price < EMA(${value.toInt()})';
      case RuleConditionType.macdCrossover: return 'MACD bullish cross';
      case RuleConditionType.macdCrossunder: return 'MACD bearish cross';
      case RuleConditionType.volumeSpike: return 'Volume > ${value.toStringAsFixed(1)}x avg';
      case RuleConditionType.priceNear52WeekLow: return 'Within ${value.toInt()}% of 52W low';
      case RuleConditionType.priceNear52WeekHigh: return 'Within ${value.toInt()}% of 52W high';
      case RuleConditionType.bollingerBreakout: return 'BB breakout';
      case RuleConditionType.priceChangeAbove: return 'Day change > ${value.toStringAsFixed(1)}%';
      case RuleConditionType.priceChangeBelow: return 'Day change < ${value.toStringAsFixed(1)}%';
      
      // NEW Momentum
      case RuleConditionType.momentum6Month: return '6M return > ${value.toInt()}%';
      case RuleConditionType.momentum12Month: return '12M return > ${value.toInt()}%';
      
      // NEW 52-Week High
      case RuleConditionType.nearAllTimeHigh: return 'Within ${value.toInt()}% of 52W HIGH';
      
      // NEW Breakout
      case RuleConditionType.breakoutNDayHigh: return 'Breaks ${value.toInt()}-day high';
      case RuleConditionType.breakoutHeld: return 'Breakout held ${value.toInt()} days';
      
      // NEW VCP
      case RuleConditionType.vcpSetup: return 'VCP setup (volatility contracting)';
      case RuleConditionType.bollingerSqueeze: return 'BB squeeze (width < ${value.toInt()}%)';
      
      // NEW Volume/Flow
      case RuleConditionType.stealthAccumulation: return 'Vol > ${value.toStringAsFixed(1)}x, price flat';
      case RuleConditionType.obvDivergence: return 'OBV divergence (bullish)';
      
      // NEW Reversal
      case RuleConditionType.oversoldBounce: return 'Dropped ${value.toInt()}%+ in 3 days';
      
      // NEW Earnings/Insider
      case RuleConditionType.earningsSurprise: return 'EPS beat > ${value.toInt()}%';
      case RuleConditionType.insiderBuying: return 'Director buying';
      
      // Event-based rules (with cooldowns)
      case RuleConditionType.event52WeekHighCrossover: return '⚡ Crosses into 52W high zone';
      case RuleConditionType.eventVolumeBreakout: return '⚡ Volume breakout event';
      case RuleConditionType.eventMomentumCrossover: return '⚡ 6M momentum crossover';
      
      // State filter rules (check if TRUE, no crossover needed)
      case RuleConditionType.stateMomentumPositive: return '📊 6M momentum > ${value.toInt()}%';
      case RuleConditionType.stateVolumeExpanding: return '📊 Volume expanding (10d > prior avg)';
      case RuleConditionType.stateAboveSma50: return '📊 Price > SMA50';
      case RuleConditionType.stateUptrend: return '📊 In uptrend (20d)';
      case RuleConditionType.stateNear52WeekHigh: return '📊 Within ${(100 - value).toInt()}% of 52W high';
    }
  }
}

class ScanRule {
  final String id;
  final String name;
  final String description;
  final List<RuleCondition> conditions;
  final bool isActive;
  final bool isCommunityRule;
  final DateTime createdAt;
  final DateTime? lastTriggered;
  final int matchCount;

  ScanRule({
    required this.id, required this.name, required this.description,
    required this.conditions, this.isActive = true, this.isCommunityRule = false,
    required this.createdAt, this.lastTriggered, this.matchCount = 0,
  });

  ScanRule copyWith({
    String? id, String? name, String? description, List<RuleCondition>? conditions,
    bool? isActive, bool? isCommunityRule, DateTime? createdAt, DateTime? lastTriggered, int? matchCount,
  }) => ScanRule(
    id: id ?? this.id, name: name ?? this.name, description: description ?? this.description,
    conditions: conditions ?? this.conditions, isActive: isActive ?? this.isActive,
    isCommunityRule: isCommunityRule ?? this.isCommunityRule, createdAt: createdAt ?? this.createdAt,
    lastTriggered: lastTriggered ?? this.lastTriggered, matchCount: matchCount ?? this.matchCount,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'description': description,
    'conditions': conditions.map((c) => c.toJson()).toList(),
    'isActive': isActive, 'isCommunityRule': isCommunityRule,
    'createdAt': createdAt.toIso8601String(),
    'lastTriggered': lastTriggered?.toIso8601String(), 'matchCount': matchCount,
  };

  factory ScanRule.fromJson(Map<String, dynamic> json) => ScanRule(
    id: json['id'] ?? '', name: json['name'] ?? '', description: json['description'] ?? '',
    conditions: (json['conditions'] as List?)?.map((c) => RuleCondition.fromJson(c)).toList() ?? [],
    isActive: json['isActive'] ?? true, isCommunityRule: json['isCommunityRule'] ?? false,
    createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
    lastTriggered: json['lastTriggered'] != null ? DateTime.parse(json['lastTriggered']) : null,
    matchCount: json['matchCount'] ?? 0,
  );
}

/// Default rules - mix of original + new evidence-based rules
final List<ScanRule> defaultRules = [
  // === FREE TIER RULES ===
  
  // Original oversold RSI
  ScanRule(
    id: 'oversold_rsi', 
    name: 'Oversold RSI', 
    description: 'Stocks with RSI below 30 - potential bounce candidates',
    conditions: [RuleCondition(type: RuleConditionType.rsiBelow, value: 30)], 
    createdAt: DateTime.now(),
  ),
  
  // Original near 52-week low
  ScanRule(
    id: 'near_52_low', 
    name: 'Near 52-Week Low', 
    description: 'Stocks within 5% of 52-week low',
    conditions: [RuleCondition(type: RuleConditionType.priceNear52WeekLow, value: 5)], 
    createdAt: DateTime.now(),
  ),

  // === PRO RULES (Event-based with cooldowns) ===
  
  // Rule 1: 52-Week High Proximity Event
  // Triggers ONCE when price crosses INTO 97% of 252-day high
  // Cooldown: 45 trading days
  ScanRule(
    id: 'event_52w_high', 
    name: '52W High Crossover ⚡', 
    description: 'Event: Price crosses into 97% of 52-week high (45-day cooldown). Anchoring bias - winners keep winning.',
    conditions: [RuleCondition(type: RuleConditionType.event52WeekHighCrossover, value: 97)], 
    createdAt: DateTime.now(),
  ),
  
  // Rule 2: Volume Breakout Event
  // Triggers ONCE when volume crosses above 1.5x average with positive close
  // Cooldown: 30 trading days
  ScanRule(
    id: 'event_volume_breakout', 
    name: 'Volume Breakout ⚡', 
    description: 'Event: Volume crosses 1.5x average + close > prior close (30-day cooldown). Institutional interest signal.',
    conditions: [RuleCondition(type: RuleConditionType.eventVolumeBreakout, value: 1.5)], 
    createdAt: DateTime.now(),
  ),
  
  // Rule 3: 6-Month Momentum Event
  // Triggers ONCE when 6-month return crosses above +10%
  // Cooldown: 60 trading days
  ScanRule(
    id: 'event_momentum_6m', 
    name: '6M Momentum Crossover ⚡', 
    description: 'Event: 6-month return crosses above +10% (60-day cooldown). Institutional underreaction.',
    conditions: [RuleCondition(type: RuleConditionType.eventMomentumCrossover, value: 10)], 
    createdAt: DateTime.now(),
  ),
  
  // === COMBO RULES (Event + State Filters) ===
  // These use EVENT triggers with STATE filters for higher quality signals
  // NOTE: Event rules trigger only on crossover day - USE FOR BACKTEST ONLY
  
  // Combo: 52W High Crossover + Momentum + Volume (BACKTEST ONLY)
  // Event triggers when price crosses into 52W high zone
  // BUT only if momentum is positive AND volume is expanding
  ScanRule(
    id: 'combo_52w_momentum_volume', 
    name: '⚡ 52W Crossover [Backtest]', 
    description: '⚠️ BACKTEST ONLY - Event: Crosses into 52W high zone on specific day. Filters: 6M momentum > 5%, volume expanding.',
    conditions: [
      RuleCondition(type: RuleConditionType.event52WeekHighCrossover, value: 97),
      RuleCondition(type: RuleConditionType.stateMomentumPositive, value: 5),
      RuleCondition(type: RuleConditionType.stateVolumeExpanding, value: 0),
    ], 
    createdAt: DateTime.now(),
  ),
  
  // STATE-BASED COMBO: Near 52W High + Momentum + Volume (LIVE SCAN)
  // All state filters - finds stocks currently meeting all conditions
  ScanRule(
    id: 'combo_near_high_momentum_volume', 
    name: '🎯 Near 52W High + Momentum [Live]', 
    description: '✅ LIVE SCAN - Currently within 5% of 52W high + 6M momentum > 5% + volume expanding.',
    conditions: [
      RuleCondition(type: RuleConditionType.stateNear52WeekHigh, value: 95),
      RuleCondition(type: RuleConditionType.stateMomentumPositive, value: 5),
      RuleCondition(type: RuleConditionType.stateVolumeExpanding, value: 0),
    ], 
    createdAt: DateTime.now(),
  ),
  
  // Combo: Volume Breakout + Uptrend + Above SMA50 (BACKTEST ONLY)
  ScanRule(
    id: 'combo_volume_trend', 
    name: '⚡ Volume Breakout + Trend [Backtest]', 
    description: '⚠️ BACKTEST ONLY - Event: Volume breakout on specific day. Filters: In uptrend, above SMA50.',
    conditions: [
      RuleCondition(type: RuleConditionType.eventVolumeBreakout, value: 1.5),
      RuleCondition(type: RuleConditionType.stateUptrend, value: 0),
      RuleCondition(type: RuleConditionType.stateAboveSma50, value: 0),
    ], 
    createdAt: DateTime.now(),
  ),
  
  // STATE-BASED COMBO: Uptrend + Above SMA50 + Momentum (LIVE SCAN)
  ScanRule(
    id: 'combo_trend_momentum', 
    name: '🎯 Trend + Momentum [Live]', 
    description: '✅ LIVE SCAN - Currently in uptrend + above SMA50 + 6M momentum > 10%.',
    conditions: [
      RuleCondition(type: RuleConditionType.stateUptrend, value: 0),
      RuleCondition(type: RuleConditionType.stateAboveSma50, value: 0),
      RuleCondition(type: RuleConditionType.stateMomentumPositive, value: 10),
    ], 
    createdAt: DateTime.now(),
  ),
  
  // === OTHER PRO RULES ===
  
  // NEW: Stealth Accumulation
  ScanRule(
    id: 'stealth_accumulation', 
    name: 'Stealth Accumulation', 
    description: 'High volume but flat price - institutions accumulating quietly',
    conditions: [RuleCondition(type: RuleConditionType.stealthAccumulation, value: 2)], 
    createdAt: DateTime.now(),
  ),
  
  // NEW: Breakout with confirmation
  ScanRule(
    id: 'breakout_50day', 
    name: '50-Day Breakout', 
    description: 'Price breaks above 50-day high with volume',
    conditions: [
      RuleCondition(type: RuleConditionType.breakoutNDayHigh, value: 50),
      RuleCondition(type: RuleConditionType.volumeSpike, value: 1.5),
    ], 
    createdAt: DateTime.now(),
  ),
  
  // NEW: VCP Setup (Volatility Contraction Pattern)
  ScanRule(
    id: 'vcp_setup', 
    name: 'VCP Setup', 
    description: 'Contracting volatility + near highs - supply exhaustion pattern',
    conditions: [
      RuleCondition(type: RuleConditionType.bollingerSqueeze, value: 5),
      RuleCondition(type: RuleConditionType.nearAllTimeHigh, value: 10),
    ], 
    createdAt: DateTime.now(),
  ),
  
  // NEW: OBV Divergence (bullish)
  ScanRule(
    id: 'obv_divergence', 
    name: 'OBV Divergence', 
    description: 'OBV rising while price flat - hidden accumulation',
    conditions: [RuleCondition(type: RuleConditionType.obvDivergence, value: 0)], 
    createdAt: DateTime.now(),
  ),
  
  // NEW: Oversold Bounce (short-term reversal)
  ScanRule(
    id: 'oversold_bounce', 
    name: 'Oversold Bounce', 
    description: 'Dropped 10%+ in 3 days without news - mean reversion play',
    conditions: [RuleCondition(type: RuleConditionType.oversoldBounce, value: 10)], 
    createdAt: DateTime.now(),
  ),
  
  // Original overbought RSI
  ScanRule(
    id: 'overbought_rsi', 
    name: 'Overbought RSI', 
    description: 'Stocks with RSI above 70 - potential pullback',
    conditions: [RuleCondition(type: RuleConditionType.rsiAbove, value: 70)], 
    createdAt: DateTime.now(),
  ),
  
  // Original golden cross
  ScanRule(
    id: 'golden_cross', 
    name: 'Golden Cross', 
    description: 'Price above SMA20 & SMA50 with MACD crossover',
    conditions: [
      RuleCondition(type: RuleConditionType.priceAboveSma, value: 20),
      RuleCondition(type: RuleConditionType.priceAboveSma, value: 50),
      RuleCondition(type: RuleConditionType.macdCrossover, value: 0),
    ], 
    createdAt: DateTime.now(),
  ),
  
  // Big movers
  ScanRule(
    id: 'big_movers', 
    name: 'Big Movers', 
    description: 'Stocks up more than 5% today',
    conditions: [RuleCondition(type: RuleConditionType.priceChangeAbove, value: 5)], 
    createdAt: DateTime.now(),
  ),
];