class Holding {
  final String symbol;
  final String name;
  final int quantity;
  final double avgCostBasis;
  final DateTime firstPurchased;
  final DateTime? lastPurchased;
  final double? currentPrice;
  final double? targetPrice;
  final double? stopLoss;
  final String? notes;

  Holding({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.avgCostBasis,
    required this.firstPurchased,
    this.lastPurchased,
    this.currentPrice,
    this.targetPrice,
    this.stopLoss,
    this.notes,
  });

  double get marketValue => (currentPrice ?? avgCostBasis) * quantity;
  double get costBasis => avgCostBasis * quantity;
  double get unrealizedGain => marketValue - costBasis;
  double get unrealizedGainPercent => costBasis > 0 ? (unrealizedGain / costBasis) * 100 : 0;
  int get daysHeld => DateTime.now().difference(firstPurchased).inDays;
  bool get isAtTarget => targetPrice != null && currentPrice != null && currentPrice! >= targetPrice!;
  bool get isAtStopLoss => stopLoss != null && currentPrice != null && currentPrice! <= stopLoss!;
  
  // Formatted returns
  String get formattedReturn {
    final pct = unrealizedGainPercent;
    final dollar = unrealizedGain;
    final pctStr = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';
    final dollarStr = '${dollar >= 0 ? '+' : ''}\$${_formatNumber(dollar.abs())}';
    return '$pctStr ($dollarStr)';
  }
  
  String _formatNumber(double value) {
    if (value >= 1000) {
      final thousands = (value / 1000).floor();
      final remainder = ((value % 1000)).toInt();
      return '$thousands,${remainder.toString().padLeft(3, '0')}';
    }
    return value.toStringAsFixed(0);
  }

  Holding copyWith({
    String? symbol, String? name, int? quantity, double? avgCostBasis,
    DateTime? firstPurchased, DateTime? lastPurchased, double? currentPrice,
    double? targetPrice, double? stopLoss, String? notes,
  }) => Holding(
    symbol: symbol ?? this.symbol,
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    avgCostBasis: avgCostBasis ?? this.avgCostBasis,
    firstPurchased: firstPurchased ?? this.firstPurchased,
    lastPurchased: lastPurchased ?? this.lastPurchased,
    currentPrice: currentPrice ?? this.currentPrice,
    targetPrice: targetPrice ?? this.targetPrice,
    stopLoss: stopLoss ?? this.stopLoss,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'name': name,
    'quantity': quantity,
    'avgCostBasis': avgCostBasis,
    'firstPurchased': firstPurchased.toIso8601String(),
    'lastPurchased': lastPurchased?.toIso8601String(),
    'currentPrice': currentPrice,
    'targetPrice': targetPrice,
    'stopLoss': stopLoss,
    'notes': notes,
  };

  factory Holding.fromJson(Map<String, dynamic> json) => Holding(
    symbol: json['symbol'] ?? '',
    name: json['name'] ?? '',
    quantity: json['quantity'] ?? 0,
    avgCostBasis: (json['avgCostBasis'] ?? json['entryPrice'] ?? 0.0).toDouble(),
    firstPurchased: json['firstPurchased'] != null 
      ? DateTime.parse(json['firstPurchased']) 
      : (json['entryDate'] != null ? DateTime.parse(json['entryDate']) : DateTime.now()),
    lastPurchased: json['lastPurchased'] != null 
      ? DateTime.parse(json['lastPurchased']) 
      : null,
    currentPrice: (json['currentPrice'] as num?)?.toDouble(),
    targetPrice: (json['targetPrice'] as num?)?.toDouble(),
    stopLoss: (json['stopLoss'] as num?)?.toDouble(),
    notes: json['notes'],
  );
}