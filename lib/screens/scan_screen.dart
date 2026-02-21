import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/holding.dart';
import '../models/stock.dart';
import '../services/subscription_service.dart';
import '../utils/theme.dart';
import '../widgets/scan_filters_sheet.dart';
import 'stock_detail_sheet.dart';
import 'paywall_screen.dart';
import 'rules_screen.dart';
import 'backtest_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  static final GlobalKey<ScanScreenState> scanKey = GlobalKey<ScanScreenState>();
  @override
  State<ScanScreen> createState() => ScanScreenState();
}

class ScanScreenState extends State<ScanScreen> {
  late PageController _pageController;
  int _currentSegment = 0;

  @override
  void initState() { super.initState(); _pageController = PageController(); }
  @override
  void dispose() { _pageController.dispose(); super.dispose(); }

  void jumpToSegment(int index) {
    if (index >= 0 && index < 2) {
      _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(children: [
          _buildSegmentedHeader(),
          Expanded(child: PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentSegment = index),
            children: const [_ScannerView(), RulesScreen()],
          )),
        ]),
      ),
    );
  }

  Widget _buildSegmentedHeader() {
    const labels = ['Scanner', 'Rules'];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(10)),
          child: Row(children: List.generate(labels.length, (i) {
            final isActive = _currentSegment == i;
            return Expanded(child: GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); _pageController.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.surfaceColor : Colors.transparent, borderRadius: BorderRadius.circular(8),
                  boxShadow: isActive ? [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 1))] : null,
                ),
                child: Text(labels[i], textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, color: isActive ? AppTheme.accentColor : AppTheme.textSecondaryColor)),
              ),
            ));
          })),
        ),
        const SizedBox(height: 4),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SCANNER VIEW — Live scan results + backtest launch
// ════════════════════════════════════════════════════════════

class _ScannerView extends StatelessWidget {
  const _ScannerView();

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        final canFull = subscription.hasFeature(ProFeature.fullAsxScan);
        final ruleCount = provider.activeRules.length;
        return RefreshIndicator(
          onRefresh: () => provider.refreshData(),
          color: AppTheme.accentColor,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _subtitle(provider, ruleCount)),
            SliverToBoxAdapter(child: _buttons(context, provider, subscription, canFull)),
            SliverToBoxAdapter(child: _filtersRow(context, provider)),
            if (provider.isScanning) SliverToBoxAdapter(child: _scanProgress(context, provider)),
            // Show results DURING and AFTER scan
            if (provider.filteredScanResults.isNotEmpty) ...[
              SliverToBoxAdapter(child: _resultsHeader(context, provider)),
              SliverToBoxAdapter(child: _adviceBanner()),
              _scanResultsList(context, provider),
            ],
            if (!provider.isScanning && provider.filteredScanResults.isEmpty)
              SliverToBoxAdapter(child: _emptyState(context, ruleCount)),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ]),
        );
      },
    );
  }

  // ── Subtitle ──
  Widget _subtitle(AppProvider p, int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: n > 0 ? AppTheme.successColor : AppTheme.textTertiaryColor, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$n rule${n != 1 ? 's' : ''} active', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
        if (p.scanFilters.enabled) ...[
          const SizedBox(width: 12),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
            child: const Text('FILTERS ON', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.accentColor, letterSpacing: 0.5))),
        ],
      ]),
    );
  }

  // ── Scan + Backtest buttons ──
  Widget _buttons(BuildContext ctx, AppProvider p, SubscriptionService sub, bool canFull) {
    final busy = p.isScanning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(children: [
        SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
          onPressed: busy ? null : () {
            if (canFull) { HapticFeedback.mediumImpact(); p.runScan(fullScan: true); }
            else { PaywallScreen.show(ctx, feature: ProFeature.fullAsxScan); }
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.black,
            disabledBackgroundColor: AppTheme.accentColor.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.radar, size: 22), const SizedBox(width: 10),
            const Text('FULL ASX SCAN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            if (!canFull) ...[const SizedBox(width: 8), const Icon(Icons.lock, size: 16)],
          ]),
        )),
        const SizedBox(height: 6),
        Text(canFull ? '~2,200 stocks \u00B7 Est. 3-5 min' : 'Full scan requires Pro', style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: SizedBox(height: 44, child: OutlinedButton.icon(
            onPressed: busy ? null : () { HapticFeedback.lightImpact(); p.runQuickScan(); },
            icon: const Icon(Icons.bolt, size: 18), label: const Text('Quick Scan', style: TextStyle(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.accentColor, side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ))),
          const SizedBox(width: 8),
          SizedBox(height: 44, child: OutlinedButton.icon(
            onPressed: p.activeRules.isEmpty ? null : () => _showPeriodSheet(ctx, p),
            icon: const Icon(Icons.science_outlined, size: 18), label: const Text('Backtest', style: TextStyle(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textSecondaryColor, side: const BorderSide(color: AppTheme.dividerColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
          const SizedBox(width: 8),
          SizedBox(height: 44, width: 44, child: OutlinedButton(
            onPressed: () async { final f = await ScanFiltersSheet.show(ctx, p.scanFilters); if (f != null) p.updateScanFilters(f); },
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero,
              side: BorderSide(color: p.scanFilters.enabled ? AppTheme.accentColor.withValues(alpha: 0.5) : AppTheme.dividerColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Icon(Icons.tune, size: 18, color: p.scanFilters.enabled ? AppTheme.accentColor : AppTheme.textSecondaryColor),
          )),
        ]),
      ]),
    );
  }

  // ── Backtest period picker → pushes BacktestScreen ──
  void _showPeriodSheet(BuildContext context, AppProvider provider) {
    int sel = 30;
    final rules = provider.activeRules;
    showModalBottomSheet(context: context, backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.science_outlined, size: 20, color: Color(0xFF7C3AED)), SizedBox(width: 10),
            Text('Backtest Active Rules', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))]),
          const SizedBox(height: 6),
          Text('Testing ${rules.length} rule${rules.length != 1 ? 's' : ''}: ${rules.map((r) => r.name).take(3).join(', ')}${rules.length > 3 ? '...' : ''}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
          const SizedBox(height: 20),
          const Text('Lookback Period', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(children: [
            _pChip('1D', 1, sel, (p) => ss(() => sel = p)), const SizedBox(width: 8),
            _pChip('1W', 7, sel, (p) => ss(() => sel = p)), const SizedBox(width: 8),
            _pChip('1M', 30, sel, (p) => ss(() => sel = p)), const SizedBox(width: 8),
            _pChip('3M', 90, sel, (p) => ss(() => sel = p)), const SizedBox(width: 8),
            _pChip('6M', 126, sel, (p) => ss(() => sel = p)),
          ]),
          const SizedBox(height: 8),
          Text('Tests ~2,200 ASX stocks \u00B7 Est. ${sel <= 7 ? '1-2' : sel <= 30 ? '3-5' : '5-8'} min', style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => BacktestScreen(autoRules: rules, autoPeriod: sel),
              ));
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.science, size: 20), const SizedBox(width: 10),
              Text('Run Backtest \u00B7 ${_pLabel(sel)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
          )),
        ])),
      )),
    );
  }

  static Widget _pChip(String label, int days, int selected, ValueChanged<int> onTap) {
    final a = days == selected;
    return Expanded(child: GestureDetector(onTap: () => onTap(days),
      child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: a ? const Color(0xFF7C3AED) : AppTheme.cardColor, borderRadius: BorderRadius.circular(8)),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: a ? Colors.white : AppTheme.textSecondaryColor)))));
  }

  static String _pLabel(int d) { if (d <= 1) return '1 Day'; if (d <= 7) return '1 Week'; if (d <= 30) return '1 Month'; if (d <= 90) return '3 Months'; return '6 Months'; }

  // ── Filters row ──
  Widget _filtersRow(BuildContext ctx, AppProvider p) {
    if (!p.scanFilters.enabled) return const SizedBox(height: 16);
    return Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 8), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [const Icon(Icons.filter_list, size: 14, color: AppTheme.accentColor), const SizedBox(width: 8),
        Expanded(child: Text(p.scanFilters.toString(), style: const TextStyle(fontSize: 11, color: AppTheme.accentColor), overflow: TextOverflow.ellipsis)),
        GestureDetector(onTap: () async { final f = await ScanFiltersSheet.show(ctx, p.scanFilters); if (f != null) p.updateScanFilters(f); },
          child: const Text('Edit', style: TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600)))])));
  }

  // ── Scan progress ──
  Widget _scanProgress(BuildContext ctx, AppProvider p) {
    final prog = p.scanTotal > 0 ? p.scanProgress / p.scanTotal : 0.0;
    return Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 8), child: Container(
      padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2))),
      child: Column(children: [
        Row(children: [const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.accentColor)),
          const SizedBox(width: 14), const Expanded(child: Text('Scanning ASX...', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          TextButton(onPressed: () => p.stopScan(), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor, padding: EdgeInsets.zero, minimumSize: const Size(50, 30)), child: const Text('STOP'))]),
        const SizedBox(height: 16),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: prog, backgroundColor: AppTheme.backgroundColor, valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentColor), minHeight: 6)),
        const SizedBox(height: 12),
        Text(p.scanStatus, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Valid stocks: ${p.validStocksFound}', style: const TextStyle(fontSize: 12, color: AppTheme.textTertiaryColor)),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text('${p.scanResults.length} matches', style: const TextStyle(fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600)))])])));
  }

  // ── Results header ──
  Widget _resultsHeader(BuildContext ctx, AppProvider p) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
    child: Row(children: [
      const Text('Scan Results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)), const SizedBox(width: 10),
      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text('${p.filteredScanResults.length}', style: const TextStyle(fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600))),
      const Spacer(),
      if (p.filteredScanResults.length > 1) _SortDropdown(current: p.scanSortOption, onChanged: (o) => p.setScanSort(o)),
      if (p.lastRefresh != null) ...[const SizedBox(width: 8), Text(_fmtTime(p.lastRefresh!), style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor))],
    ]));

  Widget _adviceBanner() => Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: AppTheme.warningColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.2))),
    child: const Row(children: [Icon(Icons.info_outline, size: 13, color: AppTheme.warningColor), SizedBox(width: 6),
      Expanded(child: Text('General information only — not financial advice. Consider your own circumstances.', style: TextStyle(fontSize: 10, color: AppTheme.warningColor, height: 1.3)))])));

  Widget _scanResultsList(BuildContext ctx, AppProvider p) => SliverList(delegate: SliverChildBuilderDelegate(
    (c, i) => _resultCard(ctx, p, p.filteredScanResults[i]), childCount: p.filteredScanResults.length));

  Widget _resultCard(BuildContext ctx, AppProvider p, ScanResult r) {
    final s = r.stock; final up = s.changePercent >= 0; final c = up ? AppTheme.successColor : AppTheme.errorColor;
    return GestureDetector(
      onTap: () => _showDetail(ctx, s.symbol, triggerRules: r.matchedRuleNames),
      onLongPress: () => _showMenu(ctx, p, r),
      child: Container(margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(up ? Icons.trending_up : Icons.trending_down, color: c, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text(s.displaySymbol, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              if (p.isInWatchlist(s.symbol)) ...[const SizedBox(width: 6), const Icon(Icons.bookmark, size: 13, color: AppTheme.accentColor)],
              if (p.isInHoldings(s.symbol)) ...[const SizedBox(width: 4), const Icon(Icons.account_balance_wallet, size: 12, color: AppTheme.successColor)]]),
            const SizedBox(height: 3),
            Wrap(spacing: 4, runSpacing: 2, children: r.matchedRuleNames.take(3).map((n) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: _sigColor(n).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
              child: Text(n, style: TextStyle(fontSize: 9, color: _sigColor(n), fontWeight: FontWeight.w600)))).toList()),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(s.formattedPrice, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)), const SizedBox(height: 2),
            Text('${up ? '+' : ''}${s.changePercent.toStringAsFixed(2)}%', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w500))])])));
  }

  Widget _emptyState(BuildContext ctx, int n) => Padding(padding: const EdgeInsets.all(40), child: Column(children: [
    const SizedBox(height: 40), Icon(Icons.radar, size: 64, color: AppTheme.textTertiaryColor.withValues(alpha: 0.5)),
    const SizedBox(height: 20), const Text('No scan results yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8),
    Text(n > 0 ? 'Tap scan or backtest above to find stocks matching your $n active rule${n > 1 ? 's' : ''}.' : 'Swipe right to Rules and enable some rules first.',
      style: const TextStyle(fontSize: 14, color: AppTheme.textSecondaryColor), textAlign: TextAlign.center),
    if (n == 0) ...[const SizedBox(height: 16), OutlinedButton(
      onPressed: () => ScanScreen.scanKey.currentState?.jumpToSegment(1),
      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.accentColor, side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      child: const Text('Set Up Rules'))]]));

  // ── Menus ──
  void _showDetail(BuildContext ctx, String sym, {List<String>? triggerRules}) {
    showModalBottomSheet(context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (c) => StockDetailSheet(symbol: sym, triggerRules: triggerRules));
  }

  void _showMenu(BuildContext ctx, AppProvider p, ScanResult r) {
    final s = r.stock; final inW = p.isInWatchlist(s.symbol); final inH = p.isInHoldings(s.symbol);
    showModalBottomSheet(context: ctx, backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(s.displaySymbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Spacer(),
            IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(c))]),
          Text(s.name, style: const TextStyle(color: AppTheme.textSecondaryColor)), const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: r.matchedRuleNames.map((n) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.bolt, size: 12, color: AppTheme.accentColor), const SizedBox(width: 4),
              Text(n, style: const TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w500))]))).toList()),
          const SizedBox(height: 16),
          if (!inW) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.bookmark_add, color: AppTheme.successColor, size: 20),
            title: const Text('Add to Watchlist', style: TextStyle(fontSize: 14)),
            onTap: () { Navigator.pop(c); p.addToWatchlist(s.symbol, s.name, s.currentPrice, triggerRule: r.ruleName, triggerRules: r.matchedRuleNames);
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${s.displaySymbol} added to watchlist'), backgroundColor: AppTheme.successColor)); })
          else const ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.bookmark, color: AppTheme.textTertiaryColor, size: 20),
            title: Text('In Watchlist', style: TextStyle(color: AppTheme.textTertiaryColor, fontSize: 14))),
          if (!inH) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.accentColor, size: 20),
            title: const Text('Add to Holdings', style: TextStyle(fontSize: 14)),
            onTap: () { Navigator.pop(c); _addHoldingDlg(ctx, p, s); })
          else const ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.account_balance_wallet, color: AppTheme.textTertiaryColor, size: 20),
            title: Text('In Holdings', style: TextStyle(color: AppTheme.textTertiaryColor, fontSize: 14))),
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.open_in_new, color: AppTheme.textSecondaryColor, size: 20),
            title: const Text('View Details & Chart', style: TextStyle(fontSize: 14)),
            onTap: () { Navigator.pop(c); _showDetail(ctx, s.symbol, triggerRules: r.matchedRuleNames); }),
        ]))));
  }

  void _addHoldingDlg(BuildContext ctx, AppProvider p, Stock s) {
    final qc = TextEditingController(text: '100');
    final cc = TextEditingController(text: s.currentPrice.toStringAsFixed(2));
    showDialog(context: ctx, builder: (c) => AlertDialog(
      backgroundColor: AppTheme.cardColor, title: Text('Add ${s.displaySymbol} to Holdings'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: qc, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: cc, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Avg Cost Basis', prefixText: '\$ ', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        ElevatedButton(onPressed: () async {
          final q = int.tryParse(qc.text) ?? 100; final co = double.tryParse(cc.text) ?? s.currentPrice;
          if (q > 0 && co > 0) {
            await p.addHolding(Holding(symbol: s.symbol, name: s.name, quantity: q, avgCostBasis: co, firstPurchased: DateTime.now(), currentPrice: s.currentPrice));
            if (c.mounted) Navigator.pop(c);
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${s.displaySymbol} added to holdings'), backgroundColor: AppTheme.successColor));
          }
        }, child: const Text('Add')),
      ]));
  }

  static Color _sigColor(String n) { final l = n.toLowerCase();
    if (l.contains('breakout') || l.contains('52')) return const Color(0xFFA78BFA);
    if (l.contains('volume')) return AppTheme.successColor;
    if (l.contains('momentum') || l.contains('big mover')) return const Color(0xFF5B8DEF);
    if (l.contains('rsi') || l.contains('oversold') || l.contains('reversal')) return AppTheme.errorColor;
    if (l.contains('golden') || l.contains('cross') || l.contains('trend')) return AppTheme.accentColor;
    return AppTheme.accentColor; }

  static String _fmtTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ════════════════════════════════════════════════════════════
// Sort dropdown
// ════════════════════════════════════════════════════════════

class _SortDropdown extends StatelessWidget {
  final ScanSortOption current;
  final ValueChanged<ScanSortOption> onChanged;
  const _SortDropdown({required this.current, required this.onChanged});

  String _l(ScanSortOption o) { switch (o) {
    case ScanSortOption.matchTime: return 'Recent'; case ScanSortOption.alphabetical: return 'A-Z';
    case ScanSortOption.priceHigh: return 'Price ↓'; case ScanSortOption.priceLow: return 'Price ↑';
    case ScanSortOption.changeHigh: return 'Change ↓'; case ScanSortOption.changeLow: return 'Change ↑';
    case ScanSortOption.volumeHigh: return 'Volume'; case ScanSortOption.rulesMatched: return 'Rules'; } }

  @override
  Widget build(BuildContext ctx) => GestureDetector(onTap: () => _show(ctx), child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.sort, size: 14, color: AppTheme.textSecondaryColor), const SizedBox(width: 4),
      Text(_l(current), style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor, fontWeight: FontWeight.w500)),
      const Icon(Icons.expand_more, size: 14, color: AppTheme.textTertiaryColor)])));

  void _show(BuildContext ctx) {
    showModalBottomSheet(context: ctx, backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sort Results', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: ScanSortOption.values.map((o) {
            final a = o == current;
            return GestureDetector(onTap: () { onChanged(o); Navigator.pop(c); },
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: a ? AppTheme.accentColor : AppTheme.cardColor, borderRadius: BorderRadius.circular(8)),
                child: Text(_l(o), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: a ? Colors.black : AppTheme.textSecondaryColor))));
          }).toList()), const SizedBox(height: 12)]))));
  }
}
