import 'dart:math' as math;
import '../models/stock.dart';

class TechnicalIndicatorsService {
  
  /// Add all technical indicators to a stock
  /// [prices] = list of close prices (oldest first)
  /// [highs], [lows] = optional OHLC data for ATR calculation
  static Future<Stock> addIndicators(Stock stock, List<double> prices, {
    List<double>? highs,
    List<double>? lows,
  }) async {
    if (prices.isEmpty) return stock;
    
    final indicators = <String, dynamic>{};
    
    // RSI (14-period) - Wilder smoothing
    if (prices.length >= 15) {
      indicators['rsi'] = _calculateRSI(prices, 14);
    }
    
    // SMAs
    if (prices.length >= 10) indicators['sma10'] = _calculateSMA(prices, 10);
    if (prices.length >= 20) indicators['sma20'] = _calculateSMA(prices, 20);
    if (prices.length >= 50) indicators['sma50'] = _calculateSMA(prices, 50);
    if (prices.length >= 200) indicators['sma200'] = _calculateSMA(prices, 200);
    
    // EMAs
    if (prices.length >= 10) indicators['ema10'] = _calculateEMA(prices, 10);
    if (prices.length >= 20) indicators['ema20'] = _calculateEMA(prices, 20);
    if (prices.length >= 50) indicators['ema50'] = _calculateEMA(prices, 50);
    
    // MACD (12, 26, 9) - proper signal line calculation
    if (prices.length >= 35) {
      final macdData = _calculateMACD(prices);
      indicators['macd'] = macdData['macd'];
      indicators['macdSignal'] = macdData['signal'];
      indicators['macdHistogram'] = macdData['histogram'];
      indicators['prevMacd'] = macdData['prevMacd'];
      indicators['prevSignal'] = macdData['prevSignal'];
    }
    
    // Bollinger Bands (20, 2) - sample standard deviation
    if (prices.length >= 20) {
      final bbData = _calculateBollingerBands(prices, 20, 2);
      indicators['bbUpper'] = bbData['upper'];
      indicators['bbMiddle'] = bbData['middle'];
      indicators['bbLower'] = bbData['lower'];
      indicators['bbWidth'] = bbData['width'];
    }
    
    // ATR (14-period) - uses real OHLC if available, else close-to-close proxy
    if (prices.length >= 15) {
      indicators['atr'] = _calculateATR(prices, 14, highs: highs, lows: lows);
      indicators['atrPercent'] = (indicators['atr'] / stock.currentPrice) * 100;
    }
    
    // Momentum calculations
    if (prices.length >= 150) {
      indicators['momentum6M'] = _calculateMomentum(prices, 126, skipLast: 20);
    }
    if (prices.length >= 270) {
      indicators['momentum12M'] = _calculateMomentum(prices, 252, skipLast: 20);
    }
    
    // N-day highs for breakout detection
    if (prices.length >= 21) indicators['high20'] = _calculateNDayHigh(prices, 20);
    if (prices.length >= 51) indicators['high50'] = _calculateNDayHigh(prices, 50);
    if (prices.length >= 101) indicators['high100'] = _calculateNDayHigh(prices, 100);
    
    // Price change over periods
    if (prices.length >= 4) {
      indicators['change3Day'] = _calculatePriceChange(prices, 3);
    }
    if (prices.length >= 6) {
      indicators['change5Day'] = _calculatePriceChange(prices, 5);
    }
    
    return stock.copyWith(indicators: indicators);
  }

  /// Calculate RSI using Wilder's smoothing method (exponential moving average)
  /// This is the industry-standard RSI calculation (Wilder, 1978)
  static double _calculateRSI(List<double> prices, int period) {
    if (prices.length < period + 1) return 50.0;
    
    // Step 1: Calculate initial average gain/loss over first `period` changes
    double avgGain = 0;
    double avgLoss = 0;
    
    for (int i = 1; i <= period; i++) {
      final change = prices[i] - prices[i - 1];
      if (change > 0) {
        avgGain += change;
      } else {
        avgLoss += change.abs();
      }
    }
    
    avgGain /= period;
    avgLoss /= period;
    
    // Step 2: Apply Wilder's smoothing for remaining prices
    // Formula: avgGain = (prevAvgGain * (period - 1) + currentGain) / period
    for (int i = period + 1; i < prices.length; i++) {
      final change = prices[i] - prices[i - 1];
      final currentGain = change > 0 ? change : 0.0;
      final currentLoss = change < 0 ? change.abs() : 0.0;
      
      avgGain = (avgGain * (period - 1) + currentGain) / period;
      avgLoss = (avgLoss * (period - 1) + currentLoss) / period;
    }
    
    if (avgLoss == 0) return 100.0;
    
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  /// Calculate Simple Moving Average
  static double _calculateSMA(List<double> prices, int period) {
    if (prices.length < period) return prices.last;
    final recent = prices.sublist(prices.length - period);
    return recent.reduce((a, b) => a + b) / period;
  }

  /// Calculate Exponential Moving Average
  static double _calculateEMA(List<double> prices, int period) {
    if (prices.length < period) return prices.last;
    
    final multiplier = 2 / (period + 1);
    double ema = prices.sublist(0, period).reduce((a, b) => a + b) / period;
    
    for (int i = period; i < prices.length; i++) {
      ema = (prices[i] - ema) * multiplier + ema;
    }
    
    return ema;
  }

  /// Calculate full EMA series (returns EMA value at each point from `period` onwards)
  static List<double> _calculateEMASeries(List<double> prices, int period) {
    if (prices.length < period) return [];
    
    final multiplier = 2 / (period + 1);
    double ema = prices.sublist(0, period).reduce((a, b) => a + b) / period;
    
    final series = <double>[ema];
    for (int i = period; i < prices.length; i++) {
      ema = (prices[i] - ema) * multiplier + ema;
      series.add(ema);
    }
    
    return series;
  }

  /// Calculate MACD with proper 9-period EMA signal line
  /// 
  /// MACD Line = EMA(12) - EMA(26)
  /// Signal Line = 9-period EMA of the MACD Line
  /// Histogram = MACD Line - Signal Line
  static Map<String, double> _calculateMACD(List<double> prices) {
    // Calculate full EMA-12 and EMA-26 series
    final ema12Series = _calculateEMASeries(prices, 12);
    final ema26Series = _calculateEMASeries(prices, 26);
    
    if (ema26Series.isEmpty) {
      return {'macd': 0, 'signal': 0, 'histogram': 0, 'prevMacd': 0, 'prevSignal': 0};
    }
    
    // MACD line series: aligned to ema26Series
    // ema12Series starts at prices index 12, ema26Series starts at prices index 26
    // When ema26 has its first value, ema12 is at its (26-12)=14th value
    const ema12Offset = 26 - 12; // = 14
    
    final macdSeries = <double>[];
    for (int i = 0; i < ema26Series.length; i++) {
      final ema12Index = i + ema12Offset;
      if (ema12Index < ema12Series.length) {
        macdSeries.add(ema12Series[ema12Index] - ema26Series[i]);
      }
    }
    
    if (macdSeries.isEmpty) {
      return {'macd': 0, 'signal': 0, 'histogram': 0, 'prevMacd': 0, 'prevSignal': 0};
    }
    
    // Signal line: 9-period EMA of the MACD series
    final signalSeries = _calculateEMASeries(macdSeries, 9);
    
    if (signalSeries.isEmpty) {
      final macd = macdSeries.last;
      return {'macd': macd, 'signal': macd, 'histogram': 0, 'prevMacd': macd, 'prevSignal': macd};
    }
    
    final macd = macdSeries.last;
    final signal = signalSeries.last;
    
    // Previous values for crossover detection
    final prevMacd = macdSeries.length >= 2 ? macdSeries[macdSeries.length - 2] : macd;
    final prevSignal = signalSeries.length >= 2 ? signalSeries[signalSeries.length - 2] : signal;
    
    return {
      'macd': macd,
      'signal': signal,
      'histogram': macd - signal,
      'prevMacd': prevMacd,
      'prevSignal': prevSignal,
    };
  }

  /// Calculate Bollinger Bands using sample standard deviation (N-1)
  static Map<String, double> _calculateBollingerBands(List<double> prices, int period, double stdDevMultiplier) {
    if (prices.length < period) {
      return {'upper': prices.last, 'middle': prices.last, 'lower': prices.last, 'width': 0};
    }
    
    final recent = prices.sublist(prices.length - period);
    final sma = recent.reduce((a, b) => a + b) / period;
    
    double sumSquares = 0;
    for (final price in recent) {
      sumSquares += math.pow(price - sma, 2);
    }
    // Use sample standard deviation (divide by period - 1, not period)
    final stdDev = math.sqrt(sumSquares / (period - 1));
    
    final upper = sma + (stdDevMultiplier * stdDev);
    final lower = sma - (stdDevMultiplier * stdDev);
    final width = sma > 0 ? ((upper - lower) / sma) * 100 : 0;
    
    return {
      'upper': upper,
      'middle': sma,
      'lower': lower,
      'width': width.toDouble(),
    };
  }

  /// Calculate Average True Range using real OHLC data when available.
  /// Falls back to close-to-close true range when highs/lows are not provided.
  /// Uses Wilder's smoothing (same as RSI) for the ATR average.
  static double _calculateATR(List<double> prices, int period, {
    List<double>? highs,
    List<double>? lows,
  }) {
    if (prices.length < period + 1) return 0;
    
    final hasOHLC = highs != null && lows != null && 
                    highs.length == prices.length && 
                    lows.length == prices.length;
    
    // Calculate True Range for each bar
    final trValues = <double>[];
    for (int i = 1; i < prices.length; i++) {
      double tr;
      if (hasOHLC) {
        // True Range = max(High - Low, |High - PrevClose|, |Low - PrevClose|)
        final high = highs[i];
        final low = lows[i];
        final prevClose = prices[i - 1];
        tr = [
          high - low,
          (high - prevClose).abs(),
          (low - prevClose).abs(),
        ].reduce(math.max);
      } else {
        // Close-to-close proxy: TR = |close - prevClose|
        // This is the best we can do without OHLC data
        tr = (prices[i] - prices[i - 1]).abs();
      }
      trValues.add(tr);
    }
    
    if (trValues.length < period) return 0;
    
    // Initial ATR: simple average of first `period` TR values
    double atr = 0;
    for (int i = 0; i < period; i++) {
      atr += trValues[i];
    }
    atr /= period;
    
    // Wilder's smoothing for remaining values
    for (int i = period; i < trValues.length; i++) {
      atr = (atr * (period - 1) + trValues[i]) / period;
    }
    
    return atr;
  }

  /// Calculate momentum (return over period, optionally skipping recent days)
  static double _calculateMomentum(List<double> prices, int period, {int skipLast = 0}) {
    if (prices.length < period + skipLast + 1) return 0;
    
    final endIdx = prices.length - 1 - skipLast;
    final startIdx = endIdx - period;
    
    if (startIdx < 0 || endIdx < 0) return 0;
    if (prices[startIdx] <= 0) return 0;
    
    return ((prices[endIdx] - prices[startIdx]) / prices[startIdx]) * 100;
  }

  /// Calculate N-day high
  static double _calculateNDayHigh(List<double> prices, int days) {
    if (prices.length < days + 1) return prices.last;
    final lookback = prices.sublist(prices.length - days - 1, prices.length - 1);
    return lookback.reduce(math.max);
  }

  /// Calculate price change over N days
  static double _calculatePriceChange(List<double> prices, int days) {
    if (prices.length < days + 1) return 0;
    final startPrice = prices[prices.length - days - 1];
    final endPrice = prices.last;
    if (startPrice <= 0) return 0;
    return ((endPrice - startPrice) / startPrice) * 100;
  }
}
