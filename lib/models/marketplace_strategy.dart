import 'scan_rule.dart';

enum StrategyCategory {
  momentum,
  breakout,
  reversal,
  valueIncome,
  shortSqueeze,
  fundamental,
  swing,
  dayTrade,
}

enum PricingModel {
  free,
  subscription, // monthly fee
}

extension StrategyCategoryExt on StrategyCategory {
  String get label {
    switch (this) {
      case StrategyCategory.momentum: return 'Momentum';
      case StrategyCategory.breakout: return 'Breakout';
      case StrategyCategory.reversal: return 'Reversal';
      case StrategyCategory.valueIncome: return 'Value / Income';
      case StrategyCategory.shortSqueeze: return 'Short Squeeze';
      case StrategyCategory.fundamental: return 'Fundamental';
      case StrategyCategory.swing: return 'Swing';
      case StrategyCategory.dayTrade: return 'Day Trade';
    }
  }

  String get emoji {
    switch (this) {
      case StrategyCategory.momentum: return '🚀';
      case StrategyCategory.breakout: return '⚡';
      case StrategyCategory.reversal: return '🔄';
      case StrategyCategory.valueIncome: return '💰';
      case StrategyCategory.shortSqueeze: return '🩳';
      case StrategyCategory.fundamental: return '📊';
      case StrategyCategory.swing: return '🎯';
      case StrategyCategory.dayTrade: return '⏱️';
    }
  }
}

/// A published strategy on the marketplace
class MarketplaceStrategy {
  final String id;
  final String title;
  final String description;
  final String longDescription;
  final List<ScanRule> rules; // The actual scan rules (hidden until subscribed)
  final String publisherId;
  final String publisherName;
  final String publisherHandle; // e.g. @asxtrader
  final String? publisherAvatarInitials;
  final StrategyCategory category;
  final PricingModel pricing;
  final double? monthlyPrice; // null if free
  final int subscriberCount;
  final double averageRating; // 1.0 - 5.0
  final int ratingCount;
  final DateTime publishedAt;
  final DateTime lastUpdated;
  final bool isFeatured;
  final bool isVerified; // publisher verified by ASX Radar team
  final Map<String, dynamic>? backtestSummary; // optional backtest stats
  final List<String> tags;

  const MarketplaceStrategy({
    required this.id,
    required this.title,
    required this.description,
    required this.longDescription,
    required this.rules,
    required this.publisherId,
    required this.publisherName,
    required this.publisherHandle,
    this.publisherAvatarInitials,
    required this.category,
    required this.pricing,
    this.monthlyPrice,
    required this.subscriberCount,
    required this.averageRating,
    required this.ratingCount,
    required this.publishedAt,
    required this.lastUpdated,
    this.isFeatured = false,
    this.isVerified = false,
    this.backtestSummary,
    this.tags = const [],
  });

  bool get isFree => pricing == PricingModel.free;

  String get priceLabel {
    if (isFree) return 'Free';
    if (monthlyPrice != null) return '\$${monthlyPrice!.toStringAsFixed(2)}/mo';
    return 'Free';
  }

  String get subscriberLabel {
    if (subscriberCount >= 1000) {
      return '${(subscriberCount / 1000).toStringAsFixed(1)}k';
    }
    return subscriberCount.toString();
  }
}

/// Publisher profile with aggregated stats
class PublisherProfile {
  final String id;
  final String name;
  final String handle;
  final String bio;
  final String avatarInitials;
  final bool isVerified;
  final int totalSubscribers;
  final int strategyCount;
  final double averageRating;
  final DateTime memberSince;
  final List<MarketplaceStrategy> strategies;

  const PublisherProfile({
    required this.id,
    required this.name,
    required this.handle,
    required this.bio,
    required this.avatarInitials,
    required this.isVerified,
    required this.totalSubscribers,
    required this.strategyCount,
    required this.averageRating,
    required this.memberSince,
    required this.strategies,
  });
}

/// Mock data — replace with Firebase/Supabase backend calls
final List<MarketplaceStrategy> mockMarketplaceStrategies = [
  // ── FEATURED ──────────────────────────────────────────────────────────────
  MarketplaceStrategy(
    id: 'mkt_insider_flow',
    title: 'Insider Flow + Momentum',
    description: 'Combines director buying filings with 6M momentum crossovers. Only fires when smart money AND price agree.',
    longDescription:
        'This strategy watches for director on-market purchases (Appendix 3Y filings) and waits for the 6-month price momentum to confirm. The logic: directors know their company best. When they buy AND momentum turns positive, the probability of a sustained move increases substantially. Backtest over 5 years on ASX300 shows 61% win rate with average hold of 47 days.',
    rules: [
      ScanRule(
        id: 'insider_flow_main',
        name: 'Insider Flow + Momentum',
        description: 'Director buy + momentum crossover',
        conditions: [
          RuleCondition(type: RuleConditionType.directorTradeWithinDays, value: 14),
          RuleCondition(type: RuleConditionType.eventMomentumCrossover, value: 10),
          RuleCondition(type: RuleConditionType.stateAboveSma50, value: 0),
        ],
        createdAt: DateTime(2024, 8, 1),
      ),
    ],
    publisherId: 'pub_001',
    publisherName: 'Marcus Chen',
    publisherHandle: '@ausquant',
    publisherAvatarInitials: 'MC',
    category: StrategyCategory.fundamental,
    pricing: PricingModel.subscription,
    monthlyPrice: 9.99,
    subscriberCount: 1842,
    averageRating: 4.7,
    ratingCount: 312,
    publishedAt: DateTime(2024, 6, 15),
    lastUpdated: DateTime(2025, 1, 10),
    isFeatured: true,
    isVerified: true,
    backtestSummary: {
      'winRate': 61.2,
      'avgReturn': 14.8,
      'maxDrawdown': -8.3,
      'sharpe': 1.42,
      'avgHoldDays': 47,
    },
    tags: ['director', 'momentum', 'fundamental', 'ASX300'],
  ),

  MarketplaceStrategy(
    id: 'mkt_vcp_breakout',
    title: 'VCP Breakout System',
    description: 'Mark Minervini-style volatility contraction patterns adapted for ASX conditions. High accuracy, patient entries.',
    longDescription:
        'The Volatility Contraction Pattern (VCP) identifies stocks coiling before a major move. This system finds stocks with 3+ contracting price swings, Bollinger Band squeeze, and near 52-week highs. Entry triggers on volume breakout above the contraction pivot. Designed specifically for ASX small-to-mid caps where VCP patterns are common due to lower liquidity.',
    rules: [
      ScanRule(
        id: 'vcp_breakout_main',
        name: 'VCP Breakout System',
        description: 'BB squeeze + near high + volume',
        conditions: [
          RuleCondition(type: RuleConditionType.bollingerSqueeze, value: 5),
          RuleCondition(type: RuleConditionType.stateNear52WeekHigh, value: 95),
          RuleCondition(type: RuleConditionType.eventVolumeBreakout, value: 1.5),
        ],
        createdAt: DateTime(2024, 3, 1),
      ),
    ],
    publisherId: 'pub_002',
    publisherName: 'Sarah Nguyen',
    publisherHandle: '@vcpqueen',
    publisherAvatarInitials: 'SN',
    category: StrategyCategory.breakout,
    pricing: PricingModel.subscription,
    monthlyPrice: 7.99,
    subscriberCount: 2341,
    averageRating: 4.9,
    ratingCount: 528,
    publishedAt: DateTime(2024, 3, 20),
    lastUpdated: DateTime(2025, 1, 28),
    isFeatured: true,
    isVerified: true,
    backtestSummary: {
      'winRate': 58.4,
      'avgReturn': 19.2,
      'maxDrawdown': -11.1,
      'sharpe': 1.68,
      'avgHoldDays': 31,
    },
    tags: ['VCP', 'Minervini', 'breakout', 'small-cap'],
  ),

  MarketplaceStrategy(
    id: 'mkt_post_halt',
    title: 'Post-Halt Catalyst Play',
    description: 'Catches stocks resuming from trading halts with price-sensitive announcements. Pure ASX edge — not available anywhere else.',
    longDescription:
        'Trading halts followed by market-sensitive announcements are a uniquely Australian opportunity. This strategy monitors ASIC halt filings and fires when a stock resumes with: (1) a price-sensitive announcement, (2) a >5% day gain, and (3) volume above 2x average. The key insight: retail often sells too early on resumption — this rule catches the second wave of buying 1-3 days after.',
    rules: [
      ScanRule(
        id: 'post_halt_main',
        name: 'Post-Halt Catalyst Play',
        description: 'Halt resume + sensitive ann + price surge',
        conditions: [
          RuleCondition(type: RuleConditionType.resumedFromHalt, value: 3),
          RuleCondition(type: RuleConditionType.marketSensitiveWithinDays, value: 3),
          RuleCondition(type: RuleConditionType.priceChangeAbove, value: 5),
        ],
        createdAt: DateTime(2024, 9, 1),
      ),
    ],
    publisherId: 'pub_003',
    publisherName: 'Tom Mackay',
    publisherHandle: '@asxcatalyst',
    publisherAvatarInitials: 'TM',
    category: StrategyCategory.fundamental,
    pricing: PricingModel.free,
    subscriberCount: 3104,
    averageRating: 4.5,
    ratingCount: 619,
    publishedAt: DateTime(2024, 9, 5),
    lastUpdated: DateTime(2025, 2, 1),
    isFeatured: true,
    isVerified: true,
    backtestSummary: {
      'winRate': 55.8,
      'avgReturn': 11.4,
      'maxDrawdown': -9.7,
      'sharpe': 1.21,
      'avgHoldDays': 8,
    },
    tags: ['halt', 'announcement', 'catalyst', 'free'],
  ),

  // ── TRENDING ──────────────────────────────────────────────────────────────
  MarketplaceStrategy(
    id: 'mkt_short_squeeze',
    title: 'Short Squeeze Hunter',
    description: 'Identifies heavily shorted ASX stocks showing early signs of forced covering. Uses ASIC short data + technical triggers.',
    longDescription:
        'Uses ASIC daily short position reports to find stocks with >8% short interest, then waits for a technical trigger (MACD crossover or 20-day breakout) that forces shorts to cover. The compounding effect of short covering can produce outsized moves in 2-5 days. Risk is managed by requiring above-average volume confirmation.',
    rules: [
      ScanRule(
        id: 'short_squeeze_adv',
        name: 'Short Squeeze Hunter',
        description: 'High short + MACD cross + breakout',
        conditions: [
          RuleCondition(type: RuleConditionType.shortInterestAbove, value: 8),
          RuleCondition(type: RuleConditionType.macdCrossover, value: 0),
          RuleCondition(type: RuleConditionType.breakoutNDayHigh, value: 20),
        ],
        createdAt: DateTime(2024, 11, 1),
      ),
    ],
    publisherId: 'pub_004',
    publisherName: 'Dev Patel',
    publisherHandle: '@shortpaindev',
    publisherAvatarInitials: 'DP',
    category: StrategyCategory.shortSqueeze,
    pricing: PricingModel.subscription,
    monthlyPrice: 5.99,
    subscriberCount: 987,
    averageRating: 4.3,
    ratingCount: 142,
    publishedAt: DateTime(2024, 11, 12),
    lastUpdated: DateTime(2025, 1, 20),
    isFeatured: false,
    isVerified: false,
    backtestSummary: {
      'winRate': 49.1,
      'avgReturn': 22.3,
      'maxDrawdown': -14.2,
      'sharpe': 1.09,
      'avgHoldDays': 6,
    },
    tags: ['ASIC', 'short', 'squeeze', 'technical'],
  ),

  MarketplaceStrategy(
    id: 'mkt_earnings_swing',
    title: 'Earnings Season Swing',
    description: 'Targets oversold ASX stocks 1-2 weeks before earnings. Pre-earnings run + post-earnings drift.',
    longDescription:
        'February and August earnings seasons on the ASX create predictable patterns. Stocks that are oversold (RSI < 35) in the 2 weeks before earnings release often experience a pre-earnings run as short sellers cover and speculators position. This strategy captures that move. Exit before the announcement itself to avoid binary risk.',
    rules: [
      ScanRule(
        id: 'earnings_swing_main',
        name: 'Earnings Season Swing',
        description: 'Oversold + earnings approaching + volume',
        conditions: [
          RuleCondition(type: RuleConditionType.earningsWithinDays, value: 14),
          RuleCondition(type: RuleConditionType.rsiBelow, value: 35),
          RuleCondition(type: RuleConditionType.volumeSpike, value: 1.5),
        ],
        createdAt: DateTime(2024, 7, 1),
      ),
    ],
    publisherId: 'pub_005',
    publisherName: 'Lisa Ho',
    publisherHandle: '@earningsedge',
    publisherAvatarInitials: 'LH',
    category: StrategyCategory.swing,
    pricing: PricingModel.free,
    subscriberCount: 1563,
    averageRating: 4.1,
    ratingCount: 274,
    publishedAt: DateTime(2024, 7, 22),
    lastUpdated: DateTime(2025, 1, 5),
    isFeatured: false,
    isVerified: true,
    backtestSummary: {
      'winRate': 53.7,
      'avgReturn': 7.9,
      'maxDrawdown': -6.1,
      'sharpe': 1.18,
      'avgHoldDays': 12,
    },
    tags: ['earnings', 'oversold', 'seasonal', 'free'],
  ),

  MarketplaceStrategy(
    id: 'mkt_stealth_acc',
    title: 'Stealth Accumulation Finder',
    description: 'Detects institutions quietly building positions: high volume, flat price, rising OBV. Before the price move.',
    longDescription:
        'Institutions can\'t buy everything at once without moving the price. So they accumulate slowly — buying on weakness, absorbing supply. This manifests as: volume 2x+ average, price change < 1%, and OBV trending higher over 20 days. By the time retail notices, the move has started. This strategy gets you in early.',
    rules: [
      ScanRule(
        id: 'stealth_acc_main',
        name: 'Stealth Accumulation Finder',
        description: 'High vol + flat price + OBV divergence',
        conditions: [
          RuleCondition(type: RuleConditionType.stealthAccumulation, value: 2),
          RuleCondition(type: RuleConditionType.obvDivergence, value: 0),
          RuleCondition(type: RuleConditionType.stateAboveSma50, value: 0),
        ],
        createdAt: DateTime(2024, 5, 1),
      ),
    ],
    publisherId: 'pub_001',
    publisherName: 'Marcus Chen',
    publisherHandle: '@ausquant',
    publisherAvatarInitials: 'MC',
    category: StrategyCategory.momentum,
    pricing: PricingModel.free,
    subscriberCount: 2218,
    averageRating: 4.6,
    ratingCount: 401,
    publishedAt: DateTime(2024, 5, 10),
    lastUpdated: DateTime(2024, 12, 15),
    isFeatured: false,
    isVerified: true,
    backtestSummary: {
      'winRate': 56.3,
      'avgReturn': 13.1,
      'maxDrawdown': -7.4,
      'sharpe': 1.35,
      'avgHoldDays': 28,
    },
    tags: ['OBV', 'accumulation', 'institutional', 'free'],
  ),
];

/// Publisher profiles — indexed by publisher ID
final Map<String, PublisherProfile> mockPublisherProfiles = {
  'pub_001': PublisherProfile(
    id: 'pub_001',
    name: 'Marcus Chen',
    handle: '@ausquant',
    bio: 'Quantitative analyst, 12 years on ASX. Built systematic strategies at two family offices. Now sharing what actually works on the ASX — not generic US strategies. Focus on combining fundamental catalysts with technical confirmation.',
    avatarInitials: 'MC',
    isVerified: true,
    totalSubscribers: 4060,
    strategyCount: 2,
    averageRating: 4.65,
    memberSince: DateTime(2024, 4, 1),
    strategies: mockMarketplaceStrategies.where((s) => s.publisherId == 'pub_001').toList(),
  ),
  'pub_002': PublisherProfile(
    id: 'pub_002',
    name: 'Sarah Nguyen',
    handle: '@vcpqueen',
    bio: 'Full-time ASX trader. Studied the VCP methodology for 4 years and adapted it to Australian market structure. My strategies focus on patience — waiting for the highest-probability setups before pulling the trigger.',
    avatarInitials: 'SN',
    isVerified: true,
    totalSubscribers: 2341,
    strategyCount: 1,
    averageRating: 4.9,
    memberSince: DateTime(2024, 2, 15),
    strategies: mockMarketplaceStrategies.where((s) => s.publisherId == 'pub_002').toList(),
  ),
  'pub_003': PublisherProfile(
    id: 'pub_003',
    name: 'Tom Mackay',
    handle: '@asxcatalyst',
    bio: 'Ex-ASX floor trader. I track halts, announcements and capital raises full time. The ASX regulatory framework creates trading opportunities that US-focused traders simply miss. This is pure edge from years of watching the tape.',
    avatarInitials: 'TM',
    isVerified: true,
    totalSubscribers: 3104,
    strategyCount: 1,
    averageRating: 4.5,
    memberSince: DateTime(2024, 8, 1),
    strategies: mockMarketplaceStrategies.where((s) => s.publisherId == 'pub_003').toList(),
  ),
};
