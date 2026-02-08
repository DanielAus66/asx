class WatchlistItem {
  final String symbol;
  final String name;
  final double addedPrice; // Market price when added to watchlist
  final DateTime addedAt;
  final double capitalInvested; // Default $10,000, Pro can customize
  final String? triggerRule; // Legacy: Single rule name that triggered addition
  final List<String> triggerRules; // Multiple rules that matched (if from multi-rule scan)
  double? currentPrice;
  double? dayChange;
  double? dayChangePercent;

  WatchlistItem({
    required this.symbol,
    required this.name,
    required this.addedPrice,
    required this.addedAt,
    this.capitalInvested = 10000.0,
    this.triggerRule,
    List<String>? triggerRules,
    this.currentPrice,
    this.dayChange,
    this.dayChangePercent,
  }) : triggerRules = triggerRules ?? [];

  // All rules that triggered (combines legacy triggerRule with triggerRules list)
  List<String> get allTriggerRules {
    final rules = <String>{};
    if (triggerRule != null && triggerRule!.isNotEmpty) {
      rules.add(triggerRule!);
    }
    rules.addAll(triggerRules);
    return rules.toList();
  }

  // Shares if you had invested capitalInvested at addedPrice
  int get theoreticalShares => addedPrice > 0 ? (capitalInvested / addedPrice).floor() : 0;
  
  // Gain/loss per share
  double get gainLossPerShare => (currentPrice ?? addedPrice) - addedPrice;
  
  // Percentage gain/loss from added price
  double get gainLossPercent => addedPrice > 0 ? ((currentPrice ?? addedPrice) - addedPrice) / addedPrice * 100 : 0;
  
  // Dollar gain/loss based on theoretical investment
  double get dollarGainLoss => gainLossPerShare * theoreticalShares;
  
  bool get isUp => gainLossPercent >= 0;
  String get displaySymbol => symbol.replaceAll('.AX', '');
  String get formattedCurrentPrice => '\$${(currentPrice ?? addedPrice).toStringAsFixed((currentPrice ?? addedPrice) < 1 ? 4 : 2)}';
  String get formattedAddedPrice => '\$${addedPrice.toStringAsFixed(addedPrice < 1 ? 4 : 2)}';
  
  // Format dollar amount with comma
  String _formatDollar(double value) {
    final absValue = value.abs();
    final prefix = value >= 0 ? '+' : '-';
    if (absValue >= 1000) {
      final thousands = (absValue / 1000).floor();
      final remainder = (absValue % 1000).toInt();
      return '$prefix\$$thousands,${remainder.toString().padLeft(3, '0')}';
    }
    return '$prefix\$${absValue.toStringAsFixed(0)}';
  }
  
  // Formatted return: +15.2% (+$1,520)
  String get formattedReturn {
    final pctStr = '${gainLossPercent >= 0 ? '+' : ''}${gainLossPercent.toStringAsFixed(1)}%';
    final dollarStr = _formatDollar(dollarGainLoss);
    return '$pctStr ($dollarStr)';
  }
  
  // Legacy format for day change
  String get formattedGainLoss => '${gainLossPerShare >= 0 ? '+' : ''}\$${gainLossPerShare.abs().toStringAsFixed(gainLossPerShare.abs() < 1 ? 4 : 2)}';
  String get formattedGainLossPercent => '${gainLossPercent >= 0 ? '+' : ''}${gainLossPercent.toStringAsFixed(2)}%';
  
  // Days since added
  int get daysSinceAdded => DateTime.now().difference(addedAt).inDays;

  Map<String, dynamic> toJson() => {
    'symbol': symbol, 
    'name': name, 
    'addedPrice': addedPrice, 
    'addedAt': addedAt.toIso8601String(),
    'capitalInvested': capitalInvested,
    'triggerRule': triggerRule,
    'triggerRules': triggerRules,
  };

  factory WatchlistItem.fromJson(Map<String, dynamic> json) => WatchlistItem(
    symbol: json['symbol'] ?? '', 
    name: json['name'] ?? '',
    addedPrice: (json['addedPrice'] ?? 0.0).toDouble(),
    addedAt: json['addedAt'] != null ? DateTime.parse(json['addedAt']) : DateTime.now(),
    capitalInvested: (json['capitalInvested'] ?? 10000.0).toDouble(),
    triggerRule: json['triggerRule'],
    triggerRules: (json['triggerRules'] as List?)?.map((r) => r.toString()).toList() ?? [],
  );

  void updatePrice(double price, {double? change, double? changePercent}) {
    currentPrice = price;
    dayChange = change;
    dayChangePercent = changePercent;
  }
  
  WatchlistItem copyWith({double? capitalInvested, String? triggerRule, List<String>? triggerRules}) => WatchlistItem(
    symbol: symbol,
    name: name,
    addedPrice: addedPrice,
    addedAt: addedAt,
    capitalInvested: capitalInvested ?? this.capitalInvested,
    triggerRule: triggerRule ?? this.triggerRule,
    triggerRules: triggerRules ?? this.triggerRules,
    currentPrice: currentPrice,
    dayChange: dayChange,
    dayChangePercent: dayChangePercent,
  );
}