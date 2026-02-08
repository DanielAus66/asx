import 'dart:math' as math;
import '../models/stock.dart';

class TechnicalIndicatorsService {
  
  /// Add all technical indicators to a stock
  static Future<Stock> addIndicators(Stock stock, List<double> prices) async {
    if (prices.isEmpty) return stock;
    
    final indicators = <String, dynamic>{};
    
    // RSI (14-period)
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
    
    // MACD (12, 26, 9)
    if (prices.length >= 35) {
      final macdData = _calculateMACD(prices);
      indicators['macd'] = macdData['macd'];
      indicators['macdSignal'] = macdData['signal'];
      indicators['macdHistogram'] = macdData['histogram'];
      indicators['prevMacd'] = macdData['prevMacd'];
      indicators['prevSignal'] = macdData['prevSignal'];
    }
    
    // Bollinger Bands (20, 2)
    if (prices.length >= 20) {
      final bbData = _calculateBollingerBands(prices, 20, 2);
      indicators['bbUpper'] = bbData['upper'];
      indicators['bbMiddle'] = bbData['middle'];
      indicators['bbLower'] = bbData['lower'];
      indicators['bbWidth'] = bbData['width'];
    }
    
    // ATR (14-period)
    if (prices.length >= 15) {
      indicators['atr'] = _calculateATR(prices, 14);
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

  /// Calculate RSI (Relative Strength Index)
  static double _calculateRSI(List<double> prices, int period) {
    if (prices.length < period + 1) return 50.0;
    
    double avgGain = 0;
    double avgLoss = 0;
    
    // Initial average gain/loss
    for (int i = prices.length - period; i < prices.length; i++) {
      final change = prices[i] - prices[i - 1];
      if (change > 0) {
        avgGain += change;
      } else {
        avgLoss += change.abs();
      }
    }
    
    avgGain /= period;
    avgLoss /= period;
    
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

  /// Calculate MACD (Moving Average Convergence Divergence)
  static Map<String, double> _calculateMACD(List<double> prices) {
    final ema12 = _calculateEMA(prices, 12);
    final ema26 = _calculateEMA(prices, 26);
    final macd = ema12 - ema26;
    
    // Calculate signal line (9-period EMA of MACD)
    // Simplified: use current MACD value
    final signal = macd * 0.9; // Approximation
    
    // Calculate previous values for crossover detection
    final prevPrices = prices.sublist(0, prices.length - 1);
    final prevEma12 = _calculateEMA(prevPrices, 12);
    final prevEma26 = _calculateEMA(prevPrices, 26);
    final prevMacd = prevEma12 - prevEma26;
    final prevSignal = prevMacd * 0.9;
    
    return {
      'macd': macd,
      'signal': signal,
      'histogram': macd - signal,
      'prevMacd': prevMacd,
      'prevSignal': prevSignal,
    };
  }

  /// Calculate Bollinger Bands
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
    final stdDev = math.sqrt(sumSquares / period);
    
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

  /// Calculate Average True Range (simplified using close prices)
  static double _calculateATR(List<double> prices, int period) {
    if (prices.length < period + 1) return 0;
    
    double sumTR = 0;
    for (int i = prices.length - period; i < prices.length; i++) {
      // Simplified TR using close prices (estimate high/low)
      final high = prices[i] * 1.01; // Estimate
      final low = prices[i] * 0.99;  // Estimate
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
