class Stock {
  final String symbol;
  final String name;
  final double currentPrice;
  final double previousClose;
  final double change;
  final double changePercent;
  final int volume;
  final double marketCap;
  final DateTime lastUpdate;
  final double? weekHigh52;
  final double? weekLow52;
  final double? rsi;
  final double? sma20;
  final double? sma50;
  final double? ema12;
  final double? ema26;
  final double? macd;
  final double? macdSignal;
  final double? bollingerUpper;
  final double? bollingerLower;
  final double? avgVolume;
  final Map<String, dynamic>? indicators; // Flexible indicator storage

  Stock({
    required this.symbol,
    required this.name,
    required this.currentPrice,
    required this.previousClose,
    required this.change,
    required this.changePercent,
    required this.volume,
    required this.marketCap,
    required this.lastUpdate,
    this.weekHigh52,
    this.weekLow52,
    this.rsi,
    this.sma20,
    this.sma50,
    this.ema12,
    this.ema26,
    this.macd,
    this.macdSignal,
    this.bollingerUpper,
    this.bollingerLower,
    this.avgVolume,
    this.indicators,
  });

  Stock copyWith({
    String? symbol, String? name, double? currentPrice, double? previousClose,
    double? change, double? changePercent, int? volume, double? marketCap,
    DateTime? lastUpdate, double? weekHigh52, double? weekLow52, double? rsi,
    double? sma20, double? sma50, double? ema12, double? ema26, double? macd,
    double? macdSignal, double? bollingerUpper, double? bollingerLower, double? avgVolume,
    Map<String, dynamic>? indicators,
  }) {
    return Stock(
      symbol: symbol ?? this.symbol, name: name ?? this.name,
      currentPrice: currentPrice ?? this.currentPrice,
      previousClose: previousClose ?? this.previousClose,
      change: change ?? this.change, changePercent: changePercent ?? this.changePercent,
      volume: volume ?? this.volume, marketCap: marketCap ?? this.marketCap,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      weekHigh52: weekHigh52 ?? this.weekHigh52, weekLow52: weekLow52 ?? this.weekLow52,
      rsi: rsi ?? this.rsi, sma20: sma20 ?? this.sma20, sma50: sma50 ?? this.sma50,
      ema12: ema12 ?? this.ema12, ema26: ema26 ?? this.ema26,
      macd: macd ?? this.macd, macdSignal: macdSignal ?? this.macdSignal,
      bollingerUpper: bollingerUpper ?? this.bollingerUpper,
      bollingerLower: bollingerLower ?? this.bollingerLower,
      avgVolume: avgVolume ?? this.avgVolume,
      indicators: indicators ?? this.indicators,
    );
  }

  Map<String, dynamic> toJson() => {
    'symbol': symbol, 'name': name, 'currentPrice': currentPrice,
    'previousClose': previousClose, 'change': change, 'changePercent': changePercent,
    'volume': volume, 'marketCap': marketCap, 'lastUpdate': lastUpdate.toIso8601String(),
    'weekHigh52': weekHigh52, 'weekLow52': weekLow52, 'rsi': rsi,
    'sma20': sma20, 'sma50': sma50, 'ema12': ema12, 'ema26': ema26,
    'macd': macd, 'macdSignal': macdSignal,
    'bollingerUpper': bollingerUpper, 'bollingerLower': bollingerLower, 'avgVolume': avgVolume,
    'indicators': indicators,
  };

  factory Stock.fromJson(Map<String, dynamic> json) => Stock(
    symbol: json['symbol'] ?? '', name: json['name'] ?? '',
    currentPrice: (json['currentPrice'] ?? 0.0).toDouble(),
    previousClose: (json['previousClose'] ?? 0.0).toDouble(),
    change: (json['change'] ?? 0.0).toDouble(),
    changePercent: (json['changePercent'] ?? 0.0).toDouble(),
    volume: json['volume'] ?? 0, marketCap: (json['marketCap'] ?? 0.0).toDouble(),
    lastUpdate: json['lastUpdate'] != null ? DateTime.parse(json['lastUpdate']) : DateTime.now(),
    weekHigh52: json['weekHigh52']?.toDouble(), weekLow52: json['weekLow52']?.toDouble(),
    rsi: json['rsi']?.toDouble(), sma20: json['sma20']?.toDouble(), sma50: json['sma50']?.toDouble(),
    ema12: json['ema12']?.toDouble(), ema26: json['ema26']?.toDouble(),
    macd: json['macd']?.toDouble(), macdSignal: json['macdSignal']?.toDouble(),
    bollingerUpper: json['bollingerUpper']?.toDouble(),
    bollingerLower: json['bollingerLower']?.toDouble(), avgVolume: json['avgVolume']?.toDouble(),
    indicators: json['indicators'] as Map<String, dynamic>?,
  );

  bool get isUp => changePercent >= 0;
  String get displaySymbol => symbol.replaceAll('.AX', '');
  String get formattedPrice => '\$${currentPrice.toStringAsFixed(currentPrice < 1 ? 4 : 2)}';
  String get formattedChange => '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%';
  String get formattedVolume {
    if (volume >= 1000000000) return '${(volume / 1000000000).toStringAsFixed(1)}B';
    if (volume >= 1000000) return '${(volume / 1000000).toStringAsFixed(1)}M';
    if (volume >= 1000) return '${(volume / 1000).toStringAsFixed(1)}K';
    return volume.toString();
  }
}
