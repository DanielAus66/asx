import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/holding.dart';
import '../models/scan_rule.dart';
import '../services/holdings_scanner_service.dart';
import '../services/storage_service.dart';
import '../services/subscription_service.dart';
import '../utils/theme.dart';

class HoldingsScannerScreen extends StatefulWidget {
  final List<ScanRule>? exitRules;
  final List<ScanRule>? addRules;
  
  const HoldingsScannerScreen({super.key, this.exitRules, this.addRules});
  
  @override
  State<HoldingsScannerScreen> createState() => _HoldingsScannerScreenState();
}

class _HoldingsScannerScreenState extends State<HoldingsScannerScreen> {
  List<Holding> _holdings = [];
  List<HoldingAnalysis> _analyses = [];
  bool _isScanning = false;
  bool _isLoading = true;
  String _scanStatus = '';
  
  @override
  void initState() {
    super.initState();
    _loadHoldings();
  }
  
  Future<void> _loadHoldings() async {
    final holdings = await StorageService.loadHoldings();
    setState(() {
      _holdings = holdings;
      _isLoading = false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionService>(
      builder: (context, subscription, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            title: const Text('Holdings'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(icon: const Icon(Icons.add), onPressed: _showAddHoldingDialog),
              if (_holdings.isNotEmpty)
                IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _confirmClearAll),
            ],
          ),
          body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)))
            : Column(
                children: [
                  if (_analyses.isNotEmpty) _buildSummaryCard(),
                  if (_scanStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_scanStatus, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ),
                  Expanded(
                    child: _holdings.isEmpty
                      ? _buildEmptyState()
                      : _analyses.isEmpty ? _buildHoldingsList() : _buildAnalysisList(),
                  ),
                ],
              ),
          floatingActionButton: _holdings.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: _isScanning ? null : _runScan,
                backgroundColor: _isScanning ? Colors.grey : const Color(0xFFFF9800),
                icon: _isScanning 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.radar, color: Colors.black),
                label: Text(_isScanning ? 'Scanning...' : 'Analyze', style: const TextStyle(color: Colors.black)),
              )
            : null,
        );
      },
    );
  }
  
  Widget _buildSummaryCard() {
    final exitCount = _analyses.where((a) => a.signal == HoldingSignal.exit).length;
    final trimCount = _analyses.where((a) => a.signal == HoldingSignal.trim).length;
    final addCount = _analyses.where((a) => a.signal == HoldingSignal.add).length;
    final holdCount = _analyses.length - exitCount - trimCount - addCount;
    
    // Calculate total portfolio value and return
    double totalValue = 0;
    double totalCost = 0;
    for (final h in _holdings) {
      totalValue += h.marketValue;
      totalCost += h.costBasis;
    }
    final totalReturn = totalValue - totalCost;
    final totalReturnPct = totalCost > 0 ? (totalReturn / totalCost) * 100 : 0;
    final isPositive = totalReturn >= 0;
    
    return Card(
      margin: const EdgeInsets.all(16),
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Portfolio value
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Portfolio Value', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                    Text('\$${_formatNumber(totalValue)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isPositive ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${isPositive ? '+' : ''}${totalReturnPct.toStringAsFixed(1)}% (${isPositive ? '+' : ''}\$${_formatNumber(totalReturn.abs())})',
                    style: TextStyle(color: isPositive ? AppTheme.successColor : AppTheme.errorColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Signal badges
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSignalBadge('EXIT', exitCount, const Color(0xFFE53935)),
                _buildSignalBadge('TRIM', trimCount, const Color(0xFFFF9800)),
                _buildSignalBadge('ADD', addCount, const Color(0xFF4CAF50)),
                _buildSignalBadge('HOLD', holdCount, Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatNumber(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }
  
  Widget _buildSignalBadge(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          ),
          child: Center(child: Text(count.toString(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18))),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }
  
  Widget _buildHoldingsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _holdings.length,
      itemBuilder: (context, index) {
        final h = _holdings[index];
        final isPositive = h.unrealizedGainPercent >= 0;
        final returnColor = isPositive ? AppTheme.successColor : AppTheme.errorColor;
        
        return Card(
          color: const Color(0xFF1E1E1E),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              children: [
                Text(h.symbol.replaceAll('.AX', ''), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: returnColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    h.formattedReturn,
                    style: TextStyle(color: returnColor, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  '${h.quantity} shares @ \$${h.avgCostBasis.toStringAsFixed(2)} • ${h.daysHeld}d',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                if (h.currentPrice != null)
                  Text(
                    'Current: \$${h.currentPrice!.toStringAsFixed(2)} • Value: \$${_formatNumber(h.marketValue)}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showAddHoldingDialog(existing: h, index: index),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  onPressed: () => _removeHolding(index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildAnalysisList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _analyses.length,
      itemBuilder: (context, index) => _buildAnalysisCard(_analyses[index]),
    );
  }
  
  Widget _buildAnalysisCard(HoldingAnalysis a) {
    final color = Color(HoldingsScannerService.getSignalColor(a.signal));
    final label = HoldingsScannerService.getSignalLabel(a.signal);
    final h = a.holding;
    final isPositive = h.unrealizedGainPercent >= 0;
    
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
        ),
        title: Row(
          children: [
            Text(h.symbol.replaceAll('.AX', ''), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isPositive ? Colors.green : Colors.red).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                h.formattedReturn,
                style: TextStyle(color: isPositive ? Colors.green : Colors.red, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        subtitle: Text('Confidence: ${a.confidence.toStringAsFixed(0)}%', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16, runSpacing: 8,
                  children: [
                    _metric('Qty', '${h.quantity}'),
                    _metric('Cost', '\$${h.avgCostBasis.toStringAsFixed(2)}'),
                    _metric('Current', '\$${a.enrichedStock.currentPrice.toStringAsFixed(2)}'),
                    _metric('Value', '\$${_formatNumber(h.marketValue)}'),
                    if (a.metrics['rsi'] != null) _metric('RSI', (a.metrics['rsi'] as double).toStringAsFixed(0)),
                  ],
                ),
                const Divider(height: 24),
                ...a.reasons.map((r) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(r, style: const TextStyle(fontSize: 12)))),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _metric(String l, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(l, style: const TextStyle(fontSize: 9, color: Colors.grey)), Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))],
  );
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text('No holdings added', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          const SizedBox(height: 8),
          Text('Track your actual ASX positions', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _showAddHoldingDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Holding'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800), foregroundColor: Colors.black),
          ),
        ],
      ),
    );
  }
  
  Future<void> _showAddHoldingDialog({Holding? existing, int? index}) async {
    final symbolCtl = TextEditingController(text: existing?.symbol.replaceAll('.AX', ''));
    final qtyCtl = TextEditingController(text: existing?.quantity.toString() ?? '');
    final costCtl = TextEditingController(text: existing?.avgCostBasis.toStringAsFixed(2) ?? '');
    final targetCtl = TextEditingController(text: existing?.targetPrice?.toStringAsFixed(2) ?? '');
    final stopCtl = TextEditingController(text: existing?.stopLoss?.toStringAsFixed(2) ?? '');
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(existing != null ? 'Edit Holding' : 'Add Holding'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: symbolCtl,
                decoration: const InputDecoration(labelText: 'Symbol (e.g., BHP)', border: OutlineInputBorder()),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtl,
                decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: costCtl,
                decoration: const InputDecoration(labelText: 'Avg Cost (\$)', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: targetCtl,
                decoration: const InputDecoration(labelText: 'Target (\$) - optional', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: stopCtl,
                decoration: const InputDecoration(labelText: 'Stop Loss (\$) - optional', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800)),
            onPressed: () {
              final sym = symbolCtl.text.trim().toUpperCase();
              final qty = int.tryParse(qtyCtl.text) ?? 0;
              final cost = double.tryParse(costCtl.text) ?? 0;
              if (sym.isEmpty || qty <= 0 || cost <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Fill symbol, qty, cost')));
                return;
              }
              Navigator.pop(ctx, {
                'symbol': '$sym.AX', 'quantity': qty, 'avgCostBasis': cost,
                'targetPrice': double.tryParse(targetCtl.text), 'stopLoss': double.tryParse(stopCtl.text),
              });
            },
            child: const Text('Save', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    
    if (result != null) {
      final holding = Holding(
        symbol: result['symbol'],
        name: result['symbol'].toString().replaceAll('.AX', ''),
        quantity: result['quantity'],
        avgCostBasis: result['avgCostBasis'],
        firstPurchased: existing?.firstPurchased ?? DateTime.now(),
        targetPrice: result['targetPrice'],
        stopLoss: result['stopLoss'],
      );
      
      setState(() {
        if (index != null) {
          _holdings[index] = holding;
        } else {
          _holdings.add(holding);
        }
        _analyses = [];
      });
      await StorageService.saveHoldings(_holdings);
    }
  }
  
  Future<void> _removeHolding(int index) async {
    setState(() {
      _holdings.removeAt(index);
      _analyses = [];
    });
    await StorageService.saveHoldings(_holdings);
  }
  
  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Clear All Holdings?'),
        content: const Text('This will remove all holdings. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      setState(() {
        _holdings = [];
        _analyses = [];
      });
      await StorageService.saveHoldings(_holdings);
    }
  }
  
  Future<void> _runScan() async {
    setState(() {
      _isScanning = true;
      _scanStatus = 'Analyzing ${_holdings.length} holdings...';
    });
    
    try {
      final results = await HoldingsScannerService.analyzePortfolio(
        _holdings,
        exitRules: widget.exitRules,
        addRules: widget.addRules,
      );
      
      // Update holdings with current prices
      for (int i = 0; i < _holdings.length; i++) {
        final analysis = results.firstWhere(
          (a) => a.holding.symbol == _holdings[i].symbol,
          orElse: () => results.first,
        );
        if (analysis.holding.symbol == _holdings[i].symbol) {
          _holdings[i] = _holdings[i].copyWith(
            currentPrice: analysis.enrichedStock.currentPrice,
          );
        }
      }
      await StorageService.saveHoldings(_holdings);
      
      setState(() {
        _analyses = results;
        _scanStatus = 'Analysis complete';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      setState(() => _scanStatus = 'Error: $e');
    }
    
    setState(() => _isScanning = false);
  }
}