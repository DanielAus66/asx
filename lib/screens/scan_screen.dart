import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/subscription_service.dart';
import '../utils/theme.dart';
import '../widgets/scan_filters_sheet.dart';
import 'stock_detail_sheet.dart';
import 'paywall_screen.dart';
import 'rules_screen.dart';
import 'backtest_screen.dart';

/// The Scan tab — the entire scanning engine.
/// 3 horizontal segments: Scanner | My Rules | Backtest
/// Accessed via sticky segmented header + horizontal swipe.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  static final GlobalKey<ScanScreenState> scanKey = GlobalKey<ScanScreenState>();

  @override
  State<ScanScreen> createState() => ScanScreenState();
}

class ScanScreenState extends State<ScanScreen> {
  late PageController _pageController;
  int _currentSegment = 0;

  final List<String> _segmentLabels = ['Scanner', 'My Rules', 'Backtest'];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Jump to a segment (0=Scanner, 1=Rules, 2=Backtest)
  void jumpToSegment(int index) {
    if (index >= 0 && index < 3) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Sticky segmented header
            _buildSegmentedHeader(),
            // Swipeable content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentSegment = index),
                children: const [
                  _ScannerView(),
                  RulesScreen(),
                  BacktestScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          // Segmented control (Bloomberg-style)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: List.generate(_segmentLabels.length, (i) {
                final isActive = _currentSegment == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _pageController.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive ? AppTheme.surfaceColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: isActive
                            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 1))]
                            : null,
                      ),
                      child: Text(
                        _segmentLabels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          color: isActive ? AppTheme.accentColor : AppTheme.textSecondaryColor,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// SCANNER VIEW (Segment 0)
// Hero scan button, progress, results — the action surface
// ────────────────────────────────────────────────────────────

class _ScannerView extends StatelessWidget {
  const _ScannerView();

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        final canFullScan = subscription.hasFeature(ProFeature.fullAsxScan);
        final activeRuleCount = provider.activeRules.length;

        return RefreshIndicator(
          onRefresh: () => provider.refreshData(),
          color: AppTheme.accentColor,
          child: CustomScrollView(
            slivers: [
              // Header subtitle
              SliverToBoxAdapter(child: _buildSubtitle(provider, activeRuleCount)),

              // Hero scan buttons
              SliverToBoxAdapter(child: _buildScanButtons(context, provider, subscription, canFullScan)),

              // Active filters row
              SliverToBoxAdapter(child: _buildFiltersRow(context, provider)),

              // Scan progress
              if (provider.isScanning)
                SliverToBoxAdapter(child: _buildScanProgress(context, provider)),

              // Results
              if (!provider.isScanning && provider.scanResults.isNotEmpty) ...[
                SliverToBoxAdapter(child: _buildResultsHeader(provider)),
                _buildScanResults(context, provider),
              ],

              // Empty state
              if (!provider.isScanning && provider.scanResults.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyState(context, activeRuleCount)),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubtitle(AppProvider provider, int activeRuleCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: activeRuleCount > 0 ? AppTheme.successColor : AppTheme.textTertiaryColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$activeRuleCount rule${activeRuleCount != 1 ? 's' : ''} active',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor),
          ),
          if (provider.scanFilters.enabled) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'FILTERS ON',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.accentColor, letterSpacing: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScanButtons(BuildContext context, AppProvider provider, SubscriptionService subscription, bool canFullScan) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        children: [
          // Hero Full ASX Scan button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: provider.isScanning
                  ? null
                  : () {
                      if (canFullScan) {
                        HapticFeedback.mediumImpact();
                        provider.runScan(fullScan: true);
                      } else {
                        PaywallScreen.show(context, feature: ProFeature.fullAsxScan);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.black,
                disabledBackgroundColor: AppTheme.accentColor.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.radar, size: 22),
                  const SizedBox(width: 10),
                  const Text('FULL ASX SCAN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  if (!canFullScan) ...[const SizedBox(width: 8), const Icon(Icons.lock, size: 16)],
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            canFullScan ? '~2,200 stocks \u00B7 Est. 3-5 min' : 'Full scan requires Pro',
            style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor),
          ),
          const SizedBox(height: 12),

          // Secondary row: Quick Scan + Filters
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: provider.isScanning ? null : () {
                      HapticFeedback.lightImpact();
                      provider.runQuickScan();
                    },
                    icon: const Icon(Icons.bolt, size: 18),
                    label: const Text('Quick Scan', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentColor,
                      side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final newFilters = await ScanFiltersSheet.show(context, provider.scanFilters);
                    if (newFilters != null) provider.updateScanFilters(newFilters);
                  },
                  icon: Icon(Icons.tune, size: 18,
                    color: provider.scanFilters.enabled ? AppTheme.accentColor : AppTheme.textSecondaryColor),
                  label: Text('Filters', style: TextStyle(fontWeight: FontWeight.w600,
                    color: provider.scanFilters.enabled ? AppTheme.accentColor : AppTheme.textSecondaryColor)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: provider.scanFilters.enabled
                        ? AppTheme.accentColor.withValues(alpha: 0.5) : AppTheme.dividerColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow(BuildContext context, AppProvider provider) {
    if (!provider.scanFilters.enabled) return const SizedBox(height: 16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.filter_list, size: 14, color: AppTheme.accentColor),
            const SizedBox(width: 8),
            Expanded(child: Text(provider.scanFilters.toString(),
                style: const TextStyle(fontSize: 11, color: AppTheme.accentColor), overflow: TextOverflow.ellipsis)),
            GestureDetector(
              onTap: () async {
                final newFilters = await ScanFiltersSheet.show(context, provider.scanFilters);
                if (newFilters != null) provider.updateScanFilters(newFilters);
              },
              child: const Text('Edit', style: TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanProgress(BuildContext context, AppProvider provider) {
    final progress = provider.scanTotal > 0 ? provider.scanProgress / provider.scanTotal : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Row(children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.accentColor)),
              const SizedBox(width: 14),
              const Expanded(child: Text('Scanning ASX...', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
              TextButton(
                onPressed: () => provider.stopScan(),
                style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor, padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                child: const Text('STOP'),
              ),
            ]),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, backgroundColor: AppTheme.backgroundColor,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentColor), minHeight: 6),
            ),
            const SizedBox(height: 12),
            Text(provider.scanStatus, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Valid stocks: ${provider.validStocksFound}', style: const TextStyle(fontSize: 12, color: AppTheme.textTertiaryColor)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text('${provider.scanResults.length} matches',
                    style: const TextStyle(fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsHeader(AppProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(children: [
        const Text('Scan Results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: Text('${provider.scanResults.length}',
              style: const TextStyle(fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
        ),
        const Spacer(),
        // Sort dropdown
        if (provider.scanResults.length > 1)
          _SortDropdown(
            current: provider.scanSortOption,
            onChanged: (option) => provider.setScanSort(option),
          ),
        if (provider.lastRefresh != null) ...[
          const SizedBox(width: 8),
          Text(_formatTime(provider.lastRefresh!), style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
        ],
      ]),
    );
  }

  Widget _buildScanResults(BuildContext context, AppProvider provider) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) => _buildScanResultCard(context, provider, provider.scanResults[i]),
        childCount: provider.scanResults.length,
      ),
    );
  }

  Widget _buildScanResultCard(BuildContext context, AppProvider provider, ScanResult result) {
    final stock = result.stock;
    final isUp = stock.changePercent >= 0;
    final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
    final isInWatchlist = provider.isInWatchlist(stock.symbol);

    return GestureDetector(
      onTap: () => _showStockDetail(context, stock.symbol, triggerRules: result.matchedRuleNames),
      onLongPress: () => _showScanResultMenu(context, provider, result),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(isUp ? Icons.trending_up : Icons.trending_down, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(stock.displaySymbol, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              if (isInWatchlist) ...[const SizedBox(width: 6), const Icon(Icons.bookmark, size: 13, color: AppTheme.accentColor)],
            ]),
            const SizedBox(height: 3),
            Wrap(spacing: 4, runSpacing: 2, children: result.matchedRuleNames.take(3).map((ruleName) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: _getSignalColor(ruleName).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
              child: Text(ruleName, style: TextStyle(fontSize: 9, color: _getSignalColor(ruleName), fontWeight: FontWeight.w600)),
            )).toList()),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(stock.formattedPrice, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 2),
            Text('${isUp ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, int activeRuleCount) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(children: [
        const SizedBox(height: 40),
        Icon(Icons.radar, size: 64, color: AppTheme.textTertiaryColor.withValues(alpha: 0.5)),
        const SizedBox(height: 20),
        const Text('No scan results yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          activeRuleCount > 0
              ? 'Tap the scan button above to find stocks matching your $activeRuleCount active rule${activeRuleCount > 1 ? 's' : ''}.'
              : 'Swipe right to My Rules and enable some rules first.',
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondaryColor),
          textAlign: TextAlign.center,
        ),
        if (activeRuleCount == 0) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => ScanScreen.scanKey.currentState?.jumpToSegment(1),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentColor,
              side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Set Up Rules'),
          ),
        ],
      ]),
    );
  }

  void _showStockDetail(BuildContext context, String symbol, {List<String>? triggerRules}) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => StockDetailSheet(symbol: symbol, triggerRules: triggerRules),
    );
  }

  void _showScanResultMenu(BuildContext context, AppProvider provider, ScanResult result) {
    final stock = result.stock;
    final isInWatchlist = provider.isInWatchlist(stock.symbol);
    showModalBottomSheet(
      context: context, backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(stock.displaySymbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            Text(stock.name, style: const TextStyle(color: AppTheme.textSecondaryColor)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: result.matchedRuleNames.map((ruleName) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt, size: 12, color: AppTheme.accentColor), const SizedBox(width: 4),
                Text(ruleName, style: const TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w500)),
              ]),
            )).toList()),
            const SizedBox(height: 16),
            if (!isInWatchlist)
              ListTile(
                leading: const Icon(Icons.bookmark_add, color: AppTheme.successColor),
                title: const Text('Add to Watchlist'),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.addToWatchlist(stock.symbol, stock.name, stock.currentPrice,
                      triggerRule: result.ruleName, triggerRules: result.matchedRuleNames);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${stock.displaySymbol} added to watchlist'), backgroundColor: AppTheme.successColor));
                },
              )
            else
              const ListTile(leading: Icon(Icons.check_circle, color: AppTheme.textTertiaryColor),
                  title: Text('Already tracking', style: TextStyle(color: AppTheme.textTertiaryColor))),
            ListTile(
              leading: const Icon(Icons.open_in_new, color: AppTheme.textSecondaryColor),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(ctx);
                _showStockDetail(context, stock.symbol, triggerRules: result.matchedRuleNames);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Color _getSignalColor(String ruleName) {
    final lower = ruleName.toLowerCase();
    if (lower.contains('breakout') || lower.contains('52')) return const Color(0xFFA78BFA);
    if (lower.contains('volume')) return AppTheme.successColor;
    if (lower.contains('momentum') || lower.contains('big mover')) return const Color(0xFF5B8DEF);
    if (lower.contains('rsi') || lower.contains('oversold') || lower.contains('reversal')) return AppTheme.errorColor;
    if (lower.contains('golden') || lower.contains('cross') || lower.contains('trend')) return AppTheme.accentColor;
    return AppTheme.accentColor;
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ────────────────────────────────────────────────────────────
// Sort dropdown chip
// ────────────────────────────────────────────────────────────

class _SortDropdown extends StatelessWidget {
  final ScanSortOption current;
  final ValueChanged<ScanSortOption> onChanged;

  const _SortDropdown({required this.current, required this.onChanged});

  String _label(ScanSortOption o) {
    switch (o) {
      case ScanSortOption.matchTime: return 'Recent';
      case ScanSortOption.alphabetical: return 'A-Z';
      case ScanSortOption.priceHigh: return 'Price ↓';
      case ScanSortOption.priceLow: return 'Price ↑';
      case ScanSortOption.changeHigh: return 'Change ↓';
      case ScanSortOption.changeLow: return 'Change ↑';
      case ScanSortOption.volumeHigh: return 'Volume';
      case ScanSortOption.rulesMatched: return 'Rules';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSortSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sort, size: 14, color: AppTheme.textSecondaryColor),
          const SizedBox(width: 4),
          Text(_label(current), style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor, fontWeight: FontWeight.w500)),
          const Icon(Icons.expand_more, size: 14, color: AppTheme.textTertiaryColor),
        ]),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sort Results', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: ScanSortOption.values.map((option) {
                  final isActive = option == current;
                  return GestureDetector(
                    onTap: () {
                      onChanged(option);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive ? AppTheme.accentColor : AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _label(option),
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500,
                          color: isActive ? Colors.black : AppTheme.textSecondaryColor,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
