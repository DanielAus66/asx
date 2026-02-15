import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import '../providers/app_provider.dart';
import '../services/subscription_service.dart';
import '../utils/theme.dart';
import 'paywall_screen.dart';

class StockDetailSheet extends StatefulWidget {
  final String symbol;
  final List<String>? triggerRules;
  const StockDetailSheet({super.key, required this.symbol, this.triggerRules});
  @override
  State<StockDetailSheet> createState() => _StockDetailSheetState();
}

class _StockDetailSheetState extends State<StockDetailSheet> {
  String _selectedRange = '1M';
  List<Map<String, dynamic>> _chartData = [];
  bool _loadingChart = true;
  final List<String> _ranges = ['1D', '1W', '1M', '3M', '1Y', 'ALL'];

  @override
  void initState() {
    super.initState();
    _loadChart();
    _refreshStockData();
  }

  Future<void> _refreshStockData() async {
    // Fetch fresh stock data to ensure price is accurate
    final provider = Provider.of<AppProvider>(context, listen: false);
    await provider.getStock(widget.symbol); // This fetches fresh data
    if (mounted) setState(() {}); // Trigger rebuild with new data
  }

  Future<void> _loadChart() async {
    setState(() => _loadingChart = true);
    final provider = Provider.of<AppProvider>(context, listen: false);
    final data = await provider.getChartData(widget.symbol, _selectedRange);
    if (mounted) setState(() { _chartData = data; _loadingChart = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        final stock = provider.stockCache[widget.symbol];
        final inWatchlist = provider.isInWatchlist(widget.symbol);
        final canAdd = provider.canAddToWatchlist();
        
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.textTertiaryColor, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),
                  if (stock != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(stock.displaySymbol, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                            Text(stock.name, style: const TextStyle(color: AppTheme.textSecondaryColor)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(stock.formattedPrice, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: (stock.changePercent >= 0 ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                            child: Text(stock.formattedChange, style: TextStyle(color: stock.changePercent >= 0 ? AppTheme.successColor : AppTheme.errorColor, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Range selector
                    Row(
                      children: _ranges.map((range) {
                        final isSelected = _selectedRange == range;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () { setState(() => _selectedRange = range); _loadChart(); },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(color: isSelected ? AppTheme.accentColor : AppTheme.cardColor, borderRadius: BorderRadius.circular(8)),
                              child: Text(range, style: TextStyle(color: isSelected ? Colors.black : AppTheme.textSecondaryColor, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, fontSize: 13), textAlign: TextAlign.center),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    // Chart with volume and timeline
                    Container(
                      height: 280,
                      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                      child: _loadingChart
                          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
                          : _chartData.isEmpty
                              ? const Center(child: Text('No chart data', style: TextStyle(color: AppTheme.textSecondaryColor)))
                              : Column(
                                  children: [
                                    // Price chart
                                    Expanded(
                                      flex: 3,
                                      child: CustomPaint(
                                        painter: PriceChartPainter(_chartData, stock.changePercent >= 0 ? AppTheme.successColor : AppTheme.errorColor),
                                        size: Size.infinite,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Volume chart
                                    SizedBox(
                                      height: 50,
                                      child: CustomPaint(
                                        painter: VolumeChartPainter(_chartData),
                                        size: Size.infinite,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    // Timeline labels
                                    SizedBox(
                                      height: 20,
                                      child: CustomPaint(
                                        painter: TimelinePainter(_chartData, _selectedRange),
                                        size: Size.infinite,
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                    const SizedBox(height: 24),
                    // Stats
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildStat('Volume', stock.formattedVolume),
                        if (stock.weekHigh52 != null) _buildStat('52W High', '\$${stock.weekHigh52!.toStringAsFixed(2)}'),
                        if (stock.weekLow52 != null) _buildStat('52W Low', '\$${stock.weekLow52!.toStringAsFixed(2)}'),
                        if (stock.rsi != null) _buildStat('RSI', stock.rsi!.toStringAsFixed(1)),
                        if (stock.sma20 != null) _buildStat('SMA20', '\$${stock.sma20!.toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Signal context - why this stock was surfaced
                    if (widget.triggerRules != null && widget.triggerRules!.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.bolt, size: 16, color: AppTheme.accentColor),
                                const SizedBox(width: 6),
                                const Text('Why this was surfaced', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: widget.triggerRules!.map((rule) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.cardColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_getRuleIcon(rule), size: 14, color: AppTheme.accentColor),
                                    const SizedBox(width: 6),
                                    Text(rule, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              )).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Watchlist button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          if (inWatchlist) {
                            provider.removeFromWatchlist(widget.symbol);
                            Navigator.pop(context);
                          } else if (canAdd) {
                            provider.addToWatchlist(widget.symbol, stock.name, stock.currentPrice);
                            Navigator.pop(context);
                          } else {
                            PaywallScreen.show(context, feature: ProFeature.unlimitedWatchlist);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: inWatchlist ? AppTheme.errorColor : (canAdd ? AppTheme.accentColor : AppTheme.cardColor),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(inWatchlist ? Icons.bookmark_remove : (canAdd ? Icons.bookmark_add : Icons.lock), color: inWatchlist || canAdd ? Colors.black : AppTheme.textSecondaryColor),
                            const SizedBox(width: 8),
                            Text(
                              inWatchlist ? 'Remove from Watchlist' : (canAdd ? 'Add to Watchlist' : 'Upgrade to Add More'),
                              style: TextStyle(color: inWatchlist || canAdd ? Colors.black : AppTheme.textSecondaryColor, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else
                    const Center(child: CircularProgressIndicator(color: AppTheme.accentColor)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  IconData _getRuleIcon(String ruleName) {
    final lower = ruleName.toLowerCase();
    if (lower.contains('momentum') || lower.contains('big mover')) return Icons.trending_up;
    if (lower.contains('breakout') || lower.contains('52-week') || lower.contains('52w')) return Icons.open_in_new;
    if (lower.contains('rsi') || lower.contains('oversold') || lower.contains('reversal') || lower.contains('bounce')) return Icons.change_circle_outlined;
    if (lower.contains('volume') || lower.contains('obv') || lower.contains('accumulation')) return Icons.bar_chart;
    if (lower.contains('golden') || lower.contains('cross') || lower.contains('trend') || lower.contains('sma')) return Icons.auto_graph;
    if (lower.contains('vcp') || lower.contains('squeeze')) return Icons.compress;
    return Icons.bolt;
  }

  Widget _buildStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Price chart painter with gradient fill
class PriceChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final Color color;
  PriceChartPainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final prices = data.map((d) => (d['close'] as num).toDouble()).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final range = maxPrice - minPrice;
    if (range == 0) return;
    
    final paint = Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke;
    final fillPaint = Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, 
      end: Alignment.bottomCenter, 
      colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)]
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    
    final path = Path();
    final fillPath = Path();
    
    for (int i = 0; i < prices.length; i++) {
      final x = (i / (prices.length - 1)) * size.width;
      final y = size.height - ((prices[i] - minPrice) / range) * size.height * 0.9 - size.height * 0.05;
      
      if (i == 0) { 
        path.moveTo(x, y); 
        fillPath.moveTo(x, size.height); 
        fillPath.lineTo(x, y); 
      } else { 
        path.lineTo(x, y); 
        fillPath.lineTo(x, y); 
      }
    }
    
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
    
    // Draw price labels on right side
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final labelStyle = TextStyle(color: Colors.grey[600], fontSize: 9);
    
    // Max price label
    textPainter.text = TextSpan(text: '\$${maxPrice.toStringAsFixed(2)}', style: labelStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 4, 2));
    
    // Min price label
    textPainter.text = TextSpan(text: '\$${minPrice.toStringAsFixed(2)}', style: labelStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 4, size.height - textPainter.height - 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Volume bar chart painter
class VolumeChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  VolumeChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final volumes = data.map((d) {
      final vol = d['volume'];
      if (vol == null) return 0.0;
      return (vol as num).toDouble();
    }).toList();
    
    if (volumes.every((v) => v == 0)) return;
    
    final maxVolume = volumes.reduce((a, b) => a > b ? a : b);
    if (maxVolume == 0) return;
    
    final barWidth = size.width / volumes.length * 0.8;
    final gap = size.width / volumes.length * 0.2;
    
    for (int i = 0; i < volumes.length; i++) {
      final x = (i / volumes.length) * size.width + gap / 2;
      final barHeight = (volumes[i] / maxVolume) * size.height * 0.9;
      final y = size.height - barHeight;
      
      // Color based on price movement
      Color barColor = Colors.grey.withValues(alpha: 0.5);
      if (i > 0 && data[i]['close'] != null && data[i-1]['close'] != null) {
        final currentClose = (data[i]['close'] as num).toDouble();
        final prevClose = (data[i-1]['close'] as num).toDouble();
        barColor = currentClose >= prevClose 
          ? AppTheme.successColor.withValues(alpha: 0.6) 
          : AppTheme.errorColor.withValues(alpha: 0.6);
      }
      
      final paint = Paint()..color = barColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(1),
        ),
        paint,
      );
    }
    
    // Draw "Vol" label
    final textPainter = TextPainter(
      text: TextSpan(text: 'Vol', style: TextStyle(color: Colors.grey[600], fontSize: 9)),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(2, 0));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Timeline labels painter
class TimelinePainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final String range;
  TimelinePainter(this.data, this.range);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final labelStyle = TextStyle(color: Colors.grey[600], fontSize: 9);
    
    // Determine how many labels to show based on data length
    int labelCount = 5;
    if (data.length < 10) labelCount = data.length;
    if (labelCount < 2) return;
    
    final step = (data.length - 1) / (labelCount - 1);
    
    for (int i = 0; i < labelCount; i++) {
      final dataIndex = (i * step).round().clamp(0, data.length - 1);
      final item = data[dataIndex];
      
      // Get timestamp and format based on range
      String label = '';
      if (item['timestamp'] != null) {
        final timestamp = item['timestamp'] as int;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        
        if (range == '1D') {
          label = DateFormat('HH:mm').format(date);
        } else if (range == '1W' || range == '1M') {
          label = DateFormat('d MMM').format(date);
        } else {
          label = DateFormat('MMM yy').format(date);
        }
      } else if (item['date'] != null) {
        label = item['date'].toString();
      }
      
      if (label.isEmpty) continue;
      
      textPainter.text = TextSpan(text: label, style: labelStyle);
      textPainter.layout();
      
      final x = (dataIndex / (data.length - 1)) * size.width - textPainter.width / 2;
      final clampedX = x.clamp(0.0, size.width - textPainter.width);
      
      textPainter.paint(canvas, Offset(clampedX, 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}