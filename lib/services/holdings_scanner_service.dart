import 'dart:math' as math;
import '../models/holding.dart';
import '../models/stock.dart';
import '../models/scan_rule.dart';
import 'scan_engine_service.dart';
import 'api_service.dart';
import 'technical_indicators_service.dart';

enum HoldingSignal {
  strongHold,   // Multiple bullish indicators
  hold,         // Neutral, no action needed
  trim,         // Take partial profits
  exit,         // Close position
  add,          // Opportunity to add
}

class HoldingAnalysis {
  final Holding holding;
  final Stock enrichedStock;
  final HoldingSignal signal;
  final List<String> reasons;
  final double confidence;
  final Map<String, dynamic> metrics;

  HoldingAnalysis({
    required this.holding,
    required this.enrichedStock,
    required this.signal,
    required this.reasons,
    required this.confidence,
    required this.metrics,
  });
}

class HoldingsScannerService {
  
  /// Analyze a single holding and generate signal
  static Future<HoldingAnalysis> analyzeHolding(
    Holding holding,
    {List<ScanRule>? exitRules, List<ScanRule>? addRules}
  ) async {
    final List<String> reasons = [];
    double bullishScore = 0;
    double bearishScore = 0;
    
    // Fetch current data
    final stock = await ApiService.fetchStock(holding.symbol);
    if (stock == null) {
      return HoldingAnalysis(
        holding: holding,
        enrichedStock: Stock(
          symbol: holding.symbol,
          name: holding.name,
          currentPrice: holding.avgCostBasis,
          previousClose: holding.avgCostBasis,
          change: 0, changePercent: 0, volume: 0, marketCap: 0,
          lastUpdate: DateTime.now(),
        ),
        signal: HoldingSignal.hold,
        reasons: ['⚠️ Unable to fetch current data - stock may be halted or delisted'],
        confidence: 0,
        metrics: {},
      );
    }
    
    // Fetch historical data
    final priceData = await ApiService.fetchHistoricalPricesAndVolumes(holding.symbol, days: 300);
    final prices = (priceData['prices'])?.map((p) => (p as num).toDouble()).toList() ?? [];
    final volumes = (priceData['volumes'])?.map((v) => (v as num).toInt()).toList() ?? [];
    
    // Enrich with indicators
    Stock enrichedStock = stock;
    if (prices.isNotEmpty) {
      enrichedStock = await TechnicalIndicatorsService.addIndicators(stock, prices);
    }
    
    // Update holding with current price
    final updatedHolding = holding.copyWith(currentPrice: enrichedStock.currentPrice);
    
    final metrics = <String, dynamic>{
      'currentPrice': enrichedStock.currentPrice,
      'unrealizedGain': updatedHolding.unrealizedGainPercent,
      'daysHeld': updatedHolding.daysHeld,
    };
    
    // ========== EXIT SIGNALS (Bearish) ==========
    
    // 1. Stop loss hit
    if (updatedHolding.isAtStopLoss) {
      bearishScore += 50;
      reasons.add('🔴 STOP LOSS HIT: Price \$${enrichedStock.currentPrice.toStringAsFixed(2)} below stop \$${holding.stopLoss!.toStringAsFixed(2)}');
    }
    
    // 2. Large drawdown from recent high
    if (prices.length > 60) {
      final lookback = prices.length > 60 ? 60 : prices.length;
      final recentHigh = prices.sublist(prices.length - lookback).reduce(math.max);
      final drawdown = ((recentHigh - enrichedStock.currentPrice) / recentHigh) * 100;
      metrics['drawdownFromHigh'] = drawdown;
      
      if (drawdown > 25) {
        bearishScore += 30;
        reasons.add('🔴 MAJOR DRAWDOWN: ${drawdown.toStringAsFixed(1)}% from 60-day high');
      } else if (drawdown > 15) {
        bearishScore += 15;
        reasons.add('⚠️ Drawdown: ${drawdown.toStringAsFixed(1)}% from 60-day high');
      }
    }
    
    // 3. RSI
    final rsi = enrichedStock.indicators?['rsi'] as double?;
    if (rsi != null) {
      metrics['rsi'] = rsi;
      if (rsi > 80) {
        bearishScore += 20;
        reasons.add('⚠️ RSI extremely overbought at ${rsi.toStringAsFixed(0)} - high risk of pullback');
      } else if (rsi > 70) {
        bearishScore += 10;
        reasons.add('⚠️ RSI overbought at ${rsi.toStringAsFixed(0)} - consider trimming');
      } else if (rsi < 25) {
        bullishScore += 15;
        reasons.add('✅ RSI deeply oversold at ${rsi.toStringAsFixed(0)} - potential bounce');
      } else if (rsi < 35) {
        bullishScore += 8;
        reasons.add('✅ RSI oversold at ${rsi.toStringAsFixed(0)}');
      }
    }
    
    // 4. MACD crossovers
    final macd = enrichedStock.indicators?['macd'] as double?;
    final signal = enrichedStock.indicators?['macdSignal'] as double?;
    final prevMacd = enrichedStock.indicators?['prevMacd'] as double?;
    final prevSignal = enrichedStock.indicators?['prevSignal'] as double?;
    
    if (macd != null && signal != null) {
      metrics['macd'] = macd;
      if (prevMacd != null && prevSignal != null) {
        if (macd < signal && prevMacd >= prevSignal) {
          bearishScore += 20;
          reasons.add('🔴 MACD bearish crossover - momentum turning negative');
        } else if (macd > signal && prevMacd <= prevSignal) {
          bullishScore += 20;
          reasons.add('✅ MACD bullish crossover - momentum turning positive');
        }
      }
    }
    
    // 5. Price vs moving averages
    final sma50 = enrichedStock.indicators?['sma50'] as double?;
    
    if (sma50 != null) {
      metrics['sma50'] = sma50;
      if (enrichedStock.currentPrice < sma50 * 0.92) {
        bearishScore += 20;
        reasons.add('🔴 Price 8%+ below 50-day SMA - strong downtrend');
      } else if (enrichedStock.currentPrice < sma50 * 0.97) {
        bearishScore += 10;
        reasons.add('⚠️ Price below 50-day SMA');
      } else if (enrichedStock.currentPrice > sma50 * 1.05) {
        bullishScore += 10;
        reasons.add('✅ Price 5%+ above 50-day SMA - strong uptrend');
      }
    }
    
    // 6. Volume analysis
    if (enrichedStock.avgVolume != null && enrichedStock.avgVolume! > 0) {
      final volumeRatio = enrichedStock.volume / enrichedStock.avgVolume!;
      metrics['volumeRatio'] = volumeRatio;
      
      if (volumeRatio > 3 && enrichedStock.changePercent < -5) {
        bearishScore += 30;
        reasons.add('🔴 CAPITULATION: ${volumeRatio.toStringAsFixed(1)}x avg volume on ${enrichedStock.changePercent.toStringAsFixed(1)}% drop');
      } else if (volumeRatio > 2 && enrichedStock.changePercent < -2) {
        bearishScore += 15;
        reasons.add('⚠️ High volume selloff: ${volumeRatio.toStringAsFixed(1)}x avg volume');
      } else if (volumeRatio > 2 && enrichedStock.changePercent > 3) {
        bullishScore += 20;
        reasons.add('✅ Breakout volume: ${volumeRatio.toStringAsFixed(1)}x avg on +${enrichedStock.changePercent.toStringAsFixed(1)}%');
      }
    }
    
    // ========== ADD SIGNALS (Bullish) ==========
    
    // 7. Target price check
    if (holding.targetPrice != null) {
      final percentToTarget = ((holding.targetPrice! - enrichedStock.currentPrice) / enrichedStock.currentPrice) * 100;
      metrics['percentToTarget'] = percentToTarget;
      
      if (updatedHolding.isAtTarget) {
        bearishScore += 15;
        reasons.add('🎯 TARGET REACHED at \$${holding.targetPrice!.toStringAsFixed(2)} - consider taking profits');
      } else if (percentToTarget < 5) {
        bearishScore += 5;
        reasons.add('🎯 Near target (${percentToTarget.toStringAsFixed(0)}% away)');
      } else if (percentToTarget > 30) {
        bullishScore += 10;
        reasons.add('✅ ${percentToTarget.toStringAsFixed(0)}% upside to target');
      }
    }
    
    // 8. Near 52-week extremes
    if (enrichedStock.weekLow52 != null && enrichedStock.weekLow52! > 0) {
      final percentFromLow = ((enrichedStock.currentPrice - enrichedStock.weekLow52!) / enrichedStock.weekLow52!) * 100;
      metrics['percentFrom52WkLow'] = percentFromLow;
      
      if (percentFromLow < 5) {
        bullishScore += 15;
        reasons.add('✅ Near 52-week low (${percentFromLow.toStringAsFixed(1)}% above) - potential value');
      }
    }
    
    if (enrichedStock.weekHigh52 != null && enrichedStock.weekHigh52! > 0) {
      final percentFromHigh = ((enrichedStock.weekHigh52! - enrichedStock.currentPrice) / enrichedStock.weekHigh52!) * 100;
      metrics['percentFrom52WkHigh'] = percentFromHigh;
      
      if (percentFromHigh < 5) {
        bullishScore += 10;
        reasons.add('✅ Near 52-week high - strong momentum');
      }
    }
    
    // 9. Momentum
    final momentum6M = enrichedStock.indicators?['momentum6M'] as double?;
    if (momentum6M != null) {
      metrics['momentum6M'] = momentum6M;
      if (momentum6M > 30) {
        bullishScore += 15;
        reasons.add('✅ Strong 6-month momentum: +${momentum6M.toStringAsFixed(0)}%');
      } else if (momentum6M > 10) {
        bullishScore += 8;
        reasons.add('✅ Positive 6-month momentum: +${momentum6M.toStringAsFixed(0)}%');
      } else if (momentum6M < -20) {
        bearishScore += 15;
        reasons.add('⚠️ Weak 6-month momentum: ${momentum6M.toStringAsFixed(0)}%');
      }
    }
    
    // 10. Unrealized gain management
    if (updatedHolding.unrealizedGainPercent > 100) {
      bearishScore += 10;
      reasons.add('💰 Position up ${updatedHolding.unrealizedGainPercent.toStringAsFixed(0)}% - consider taking some profits');
    } else if (updatedHolding.unrealizedGainPercent > 50) {
      bearishScore += 5;
      reasons.add('💰 Healthy gain of ${updatedHolding.unrealizedGainPercent.toStringAsFixed(0)}%');
    } else if (updatedHolding.unrealizedGainPercent < -30) {
      bearishScore += 10;
      reasons.add('⚠️ Down ${updatedHolding.unrealizedGainPercent.toStringAsFixed(0)}% - reassess thesis');
    }
    
    // 11. Custom exit rules
    if (exitRules != null) {
      for (final rule in exitRules) {
        if (ScanEngineService.evaluateRule(enrichedStock, rule, prices: prices, volumes: volumes)) {
          bearishScore += 25;
          reasons.add('🔴 EXIT RULE: ${rule.name}');
        }
      }
    }
    
    // 12. Custom add rules
    if (addRules != null) {
      for (final rule in addRules) {
        if (ScanEngineService.evaluateRule(enrichedStock, rule, prices: prices, volumes: volumes)) {
          bullishScore += 25;
          reasons.add('✅ ADD RULE: ${rule.name}');
        }
      }
    }
    
    // ========== DETERMINE FINAL SIGNAL ==========
    
    HoldingSignal finalSignal;
    double confidence;
    
    if (updatedHolding.isAtStopLoss) {
      finalSignal = HoldingSignal.exit;
      confidence = 95;
    } else if (bearishScore >= 70) {
      finalSignal = HoldingSignal.exit;
      confidence = math.min(95, bearishScore);
    } else if (bearishScore >= 40 && bearishScore > bullishScore * 1.5) {
      finalSignal = HoldingSignal.trim;
      confidence = (bearishScore / (bearishScore + bullishScore + 10)) * 100;
    } else if (bullishScore >= 50 && bullishScore > bearishScore * 1.5) {
      finalSignal = HoldingSignal.add;
      confidence = (bullishScore / (bearishScore + bullishScore + 10)) * 100;
    } else if (bullishScore >= 35 && bearishScore < 20) {
      finalSignal = HoldingSignal.strongHold;
      confidence = 70;
    } else {
      finalSignal = HoldingSignal.hold;
      confidence = 50;
    }
    
    // Add summary reason if no specific reasons
    if (reasons.isEmpty) {
      reasons.add('No significant signals detected');
    }
    
    return HoldingAnalysis(
      holding: updatedHolding,
      enrichedStock: enrichedStock,
      signal: finalSignal,
      reasons: reasons,
      confidence: confidence.clamp(0, 100),
      metrics: metrics,
    );
  }
  
  /// Analyze entire portfolio
  static Future<List<HoldingAnalysis>> analyzePortfolio(
    List<Holding> holdings,
    {List<ScanRule>? exitRules, List<ScanRule>? addRules}
  ) async {
    final results = <HoldingAnalysis>[];
    
    for (final holding in holdings) {
      final analysis = await analyzeHolding(
        holding,
        exitRules: exitRules,
        addRules: addRules,
      );
      results.add(analysis);
      
      // Rate limiting
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    // Sort by urgency (exits first)
    results.sort((a, b) {
      final order = {
        HoldingSignal.exit: 0,
        HoldingSignal.trim: 1,
        HoldingSignal.add: 2,
        HoldingSignal.strongHold: 3,
        HoldingSignal.hold: 4,
      };
      return order[a.signal]!.compareTo(order[b.signal]!);
    });
    
    return results;
  }
  
  /// Get signal color
  static int getSignalColor(HoldingSignal signal) {
    switch (signal) {
      case HoldingSignal.exit: return 0xFFE53935;      // Red
      case HoldingSignal.trim: return 0xFFFF9800;      // Orange
      case HoldingSignal.add: return 0xFF4CAF50;       // Green
      case HoldingSignal.strongHold: return 0xFF2196F3; // Blue
      case HoldingSignal.hold: return 0xFF9E9E9E;      // Grey
    }
  }
  
  /// Get signal label
  static String getSignalLabel(HoldingSignal signal) {
    switch (signal) {
      case HoldingSignal.exit: return '🔴 EXIT';
      case HoldingSignal.trim: return '🟠 TRIM';
      case HoldingSignal.add: return '🟢 ADD';
      case HoldingSignal.strongHold: return '🔵 STRONG HOLD';
      case HoldingSignal.hold: return '⚪ HOLD';
    }
  }
}