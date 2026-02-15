/// Filters for excluding stocks from scans and backtests
class ScanFilters {
  /// Minimum stock price (exclude stocks below this)
  final double? minPrice;
  
  /// Maximum stock price (exclude stocks above this)
  final double? maxPrice;
  
  /// Minimum average daily dollar volume (price × volume)
  /// e.g., 100000 = $100K minimum daily turnover
  final double? minDailyDollarVolume;
  
  /// Maximum single-day gap percentage to exclude
  /// e.g., 15 = exclude stocks with >15% gap up/down in single day
  final double? maxSingleDayGap;
  
  /// Whether filters are enabled
  final bool enabled;
  
  const ScanFilters({
    this.minPrice,
    this.maxPrice,
    this.minDailyDollarVolume,
    this.maxSingleDayGap,
    this.enabled = true,
  });
  
  /// Default filters - reasonable defaults for ASX
  static const ScanFilters defaultFilters = ScanFilters(
    minPrice: 0.10,          // Exclude penny stocks under 10c
    maxPrice: null,          // No max price by default
    minDailyDollarVolume: 50000, // At least $50K daily turnover
    maxSingleDayGap: 20,     // Exclude >20% single-day gaps
    enabled: true,
  );
  
  /// No filters
  static const ScanFilters none = ScanFilters(enabled: false);
  
  ScanFilters copyWith({
    double? minPrice,
    double? maxPrice,
    double? minDailyDollarVolume,
    double? maxSingleDayGap,
    bool? enabled,
  }) => ScanFilters(
    minPrice: minPrice ?? this.minPrice,
    maxPrice: maxPrice ?? this.maxPrice,
    minDailyDollarVolume: minDailyDollarVolume ?? this.minDailyDollarVolume,
    maxSingleDayGap: maxSingleDayGap ?? this.maxSingleDayGap,
    enabled: enabled ?? this.enabled,
  );
  
  Map<String, dynamic> toJson() => {
    'minPrice': minPrice,
    'maxPrice': maxPrice,
    'minDailyDollarVolume': minDailyDollarVolume,
    'maxSingleDayGap': maxSingleDayGap,
    'enabled': enabled,
  };
  
  factory ScanFilters.fromJson(Map<String, dynamic> json) => ScanFilters(
    minPrice: (json['minPrice'] as num?)?.toDouble(),
    maxPrice: (json['maxPrice'] as num?)?.toDouble(),
    minDailyDollarVolume: (json['minDailyDollarVolume'] as num?)?.toDouble(),
    maxSingleDayGap: (json['maxSingleDayGap'] as num?)?.toDouble(),
    enabled: json['enabled'] ?? true,
  );
  
  /// Check if a stock passes all filters
  /// Returns true if stock should be INCLUDED, false if it should be EXCLUDED
  bool passesFilters({
    required double currentPrice,
    double? avgVolume,
    double? dayChangePercent,
    List<double>? historicalPrices,
  }) {
    if (!enabled) return true;
    
    // Price filter
    if (minPrice != null && currentPrice < minPrice!) return false;
    if (maxPrice != null && currentPrice > maxPrice!) return false;
    
    // Daily dollar volume filter
    if (minDailyDollarVolume != null && avgVolume != null) {
      final dailyDollarVolume = currentPrice * avgVolume;
      if (dailyDollarVolume < minDailyDollarVolume!) return false;
    }
    
    // Single-day gap filter (check recent price history)
    if (maxSingleDayGap != null && historicalPrices != null && historicalPrices.length >= 2) {
      // Check last 5 days for large gaps
      final checkDays = historicalPrices.length > 5 ? 5 : historicalPrices.length - 1;
      final startIdx = historicalPrices.length - checkDays;
      for (int i = startIdx < 1 ? 1 : startIdx; i < historicalPrices.length; i++) {
        final today = historicalPrices[i];
        final yesterday = historicalPrices[i - 1];
        if (yesterday > 0) {
          final gapPercent = ((today - yesterday) / yesterday * 100).abs();
          if (gapPercent > maxSingleDayGap!) return false;
        }
      }
    }
    
    return true;
  }
  
  @override
  String toString() {
    if (!enabled) return 'Filters: Off';
    final parts = <String>[];
    if (minPrice != null) parts.add('Min \$${minPrice!.toStringAsFixed(2)}');
    if (maxPrice != null) parts.add('Max \$${maxPrice!.toStringAsFixed(2)}');
    if (minDailyDollarVolume != null) parts.add('Vol >\$${(minDailyDollarVolume! / 1000).toStringAsFixed(0)}K');
    if (maxSingleDayGap != null) parts.add('Gap <${maxSingleDayGap!.toStringAsFixed(0)}%');
    return parts.isEmpty ? 'No filters' : parts.join(', ');
  }
}