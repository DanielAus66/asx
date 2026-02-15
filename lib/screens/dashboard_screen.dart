import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../services/subscription_service.dart';
import '../utils/theme.dart';
import '../widgets/scan_filters_sheet.dart';
import 'stock_detail_sheet.dart';
import 'alerts_screen.dart';
import 'search_screen.dart';
import 'paywall_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () => provider.refreshData(),
              color: AppTheme.accentColor,
              child: CustomScrollView(slivers: [
                _buildAppBar(context, provider, subscription),
                SliverToBoxAdapter(child: _buildSubscriptionBanner(context, subscription)),
                SliverToBoxAdapter(child: _buildPortfolioCard(context, provider)),
                SliverToBoxAdapter(child: _buildScanSection(context, provider, subscription)),
                if (provider.watchlist.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _buildWatchlistHeader(context, provider, subscription)),
                  _buildWatchlist(context, provider),
                ],
                if (provider.scanResults.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _buildHeader(context, 'Scan Results', '${provider.scanResults.length} matches')),
                  _buildScanResults(context, provider),
                ],
                if (provider.watchlist.isEmpty && provider.scanResults.isEmpty)
                  SliverToBoxAdapter(child: _buildEmpty(context)),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBar(BuildContext context, AppProvider provider, SubscriptionService subscription) {
    return SliverAppBar(
      floating: true,
      backgroundColor: AppTheme.backgroundColor,
      title: Row(
        children: [
          const Text('ASX Radar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24)),
          if (subscription.isPro) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF9500)]),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(subscription.isProPlus ? 'PRO+' : 'PRO', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.search), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()))),
        Stack(children: [
          IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsScreen()))),
          if (provider.unreadAlertCount > 0)
            Positioned(right: 8, top: 8, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: AppTheme.errorColor, shape: BoxShape.circle), child: Text('${provider.unreadAlertCount}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))),
        ]),
      ],
    );
  }

  Widget _buildSubscriptionBanner(BuildContext context, SubscriptionService subscription) {
    if (subscription.isPro) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => PaywallScreen.show(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppTheme.accentColor.withValues(alpha: 0.2), AppTheme.accentColor.withValues(alpha: 0.1)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.star, color: AppTheme.accentColor, size: 20),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Upgrade to Pro', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            Text('Full ASX scan, unlimited rules & more', style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(8)),
            child: const Text('\$7.99/mo', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  Widget _buildPortfolioCard(BuildContext context, AppProvider provider) {
    return Consumer<SubscriptionService>(
      builder: (context, subscription, child) {
        if (provider.watchlist.isEmpty) {
          return Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Portfolio Tracker', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textSecondaryColor)),
              const SizedBox(height: 12),
              const Text('Add stocks to track performance', style: TextStyle(color: AppTheme.textTertiaryColor)),
              const SizedBox(height: 4),
              Text(subscription.isPro ? 'Set your own capital per trade' : 'Simulates \$10,000 invested per stock', style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
            ]),
          );
        }
        
        // Calculate total portfolio stats based on $10K per stock (or custom for Pro)
        double totalInvested = 0;
        double totalCurrentValue = 0;
        for (final item in provider.watchlist) {
          final shares = item.theoreticalShares;
          totalInvested += shares * item.addedPrice;
          totalCurrentValue += shares * (item.currentPrice ?? item.addedPrice);
        }
        final totalReturn = totalCurrentValue - totalInvested;
        final totalReturnPercent = totalInvested > 0 ? (totalReturn / totalInvested) * 100 : 0;
        final isUp = totalReturn >= 0;
        final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
        
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                const Text('Portfolio', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textSecondaryColor)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.textTertiaryColor.withValues(alpha: 0.3))),
                  child: Text(subscription.isPro ? 'Custom' : '\$10K/stock', style: const TextStyle(fontSize: 9, color: AppTheme.textTertiaryColor)),
                ),
              ]),
              if (provider.lastRefresh != null) Text(DateFormat('HH:mm').format(provider.lastRefresh!), style: const TextStyle(fontSize: 10, color: AppTheme.textTertiaryColor)),
            ]),
            const SizedBox(height: 8),
            // Total value
            Text('\$${_formatLargeNumber(totalCurrentValue)}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            // Return row
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Icon(isUp ? Icons.trending_up : Icons.trending_down, color: color, size: 14),
                  const SizedBox(width: 4),
                  Text('${isUp ? '+' : ''}${totalReturnPercent.toStringAsFixed(1)}%', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
              const SizedBox(width: 8),
              Text('${isUp ? '+' : ''}\$${_formatLargeNumber(totalReturn.abs())}', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              Text('${provider.watchlist.length} stocks', style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
            ]),
            const SizedBox(height: 16),
            // Stats row
            Row(children: [
              _badge('${provider.winnersCount}', 'Winners', AppTheme.successColor),
              const SizedBox(width: 8),
              _badge('${provider.losersCount}', 'Losers', AppTheme.errorColor),
              const Spacer(),
              // Dividends toggle (Pro only)
              GestureDetector(
                onTap: () {
                  if (subscription.isPro) {
                    provider.toggleDividends();
                  } else {
                    PaywallScreen.show(context, feature: ProFeature.unlimitedWatchlist);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: provider.includeDividends 
                      ? AppTheme.successColor.withValues(alpha: 0.15) 
                      : AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: provider.includeDividends ? AppTheme.successColor.withValues(alpha: 0.3) : AppTheme.textTertiaryColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(
                      provider.includeDividends ? Icons.check_circle : (subscription.isPro ? Icons.circle_outlined : Icons.lock),
                      size: 12,
                      color: provider.includeDividends ? AppTheme.successColor : (subscription.isPro ? AppTheme.textSecondaryColor : AppTheme.accentColor),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Dividends',
                      style: TextStyle(
                        fontSize: 10,
                        color: provider.includeDividends ? AppTheme.successColor : (subscription.isPro ? AppTheme.textSecondaryColor : AppTheme.accentColor),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
            // Info text
            if (provider.includeDividends) ...[
              const SizedBox(height: 8),
              const Text('* Dividend data coming soon', style: TextStyle(fontSize: 9, color: AppTheme.textTertiaryColor, fontStyle: FontStyle.italic)),
            ],
          ]),
        );
      },
    );
  }
  
  String _formatLargeNumber(double value) {
    final absValue = value.abs();
    if (absValue >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (absValue >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }

  Widget _badge(String val, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Text(val, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11)),
      ]),
    );
  }

  Widget _buildScanSection(BuildContext context, AppProvider provider, SubscriptionService subscription) {
    final canFullScan = subscription.hasFeature(ProFeature.fullAsxScan);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Filters row
        Row(
          children: [
            GestureDetector(
              onTap: () async {
                final newFilters = await ScanFiltersSheet.show(context, provider.scanFilters);
                if (newFilters != null) {
                  provider.updateScanFilters(newFilters);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: provider.scanFilters.enabled ? AppTheme.accentColor.withValues(alpha: 0.15) : AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: provider.scanFilters.enabled ? AppTheme.accentColor : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_list,
                      size: 16,
                      color: provider.scanFilters.enabled ? AppTheme.accentColor : AppTheme.textSecondaryColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      provider.scanFilters.enabled ? 'Filters: On' : 'Filters: Off',
                      style: TextStyle(
                        fontSize: 12,
                        color: provider.scanFilters.enabled ? AppTheme.accentColor : AppTheme.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (provider.scanFilters.enabled) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  provider.scanFilters.toString(),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        
        // Scan buttons
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: provider.isScanning ? null : () => provider.runQuickScan(),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.accentColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('QUICK SCAN', style: TextStyle(color: AppTheme.accentColor)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: provider.isScanning ? null : () {
                  if (canFullScan) {
                    provider.runScan(fullScan: true);
                  } else {
                    PaywallScreen.show(context, feature: ProFeature.fullAsxScan);
                  }
                },
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.radar, size: 20),
                  const SizedBox(width: 8),
                  const Text('FULL ASX SCAN'),
                  if (!canFullScan) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.lock, size: 14)),
                ]),
              ),
            ),
          ),
        ]),
        
        // Progress section
        if (provider.isScanning) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor)),
                  SizedBox(width: 12),
                  Text('Scanning ASX...', style: TextStyle(fontWeight: FontWeight.w600)),
                ]),
                TextButton(
                  onPressed: () => provider.stopScan(),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor, padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                  child: const Text('STOP'),
                ),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: provider.scanTotal > 0 ? provider.scanProgress / provider.scanTotal : 0,
                  backgroundColor: AppTheme.backgroundColor,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(provider.scanStatus, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Valid stocks: ${provider.validStocksFound}', style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                Text('Matches: ${provider.scanResults.length}', style: const TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
        ],
        
        if (!provider.isScanning) ...[
          const SizedBox(height: 8),
          Text(canFullScan ? 'Quick: ~20 stocks | Full: All 17,000+ ASX symbols' : 'Quick: ~20 stocks | Full scan requires Pro',
            style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
        ],
      ]),
    );
  }

  Widget _buildWatchlistHeader(BuildContext context, AppProvider provider, SubscriptionService subscription) {
    final remaining = provider.remainingWatchlistSlots;
    final showLimit = !subscription.isPro && remaining >= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          const Text('Watchlist', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('${provider.watchlist.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textSecondaryColor)),
        ]),
        if (showLimit)
          GestureDetector(
            onTap: () => PaywallScreen.show(context, feature: ProFeature.unlimitedWatchlist),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: remaining <= 1 ? AppTheme.errorColor.withValues(alpha: 0.15) : AppTheme.cardColor, borderRadius: BorderRadius.circular(6)),
              child: Text('$remaining slots left', style: TextStyle(fontSize: 11, color: remaining <= 1 ? AppTheme.errorColor : AppTheme.textSecondaryColor, fontWeight: FontWeight.w500)),
            ),
          ),
      ]),
    );
  }

  Widget _buildHeader(BuildContext context, String title, String count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        Text(count, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.accentColor)),
      ]),
    );
  }

  Widget _buildWatchlist(BuildContext context, AppProvider provider) {
    return SliverList(delegate: SliverChildBuilderDelegate(
      (ctx, i) => _watchlistTile(context, provider.watchlist[i]),
      childCount: provider.watchlist.length,
    ));
  }

  Widget _buildScanResults(BuildContext context, AppProvider provider) {
    return SliverList(delegate: SliverChildBuilderDelegate(
      (ctx, i) => _scanResultTile(context, provider.scanResults[i]),
      childCount: provider.scanResults.length,
    ));
  }

  Widget _watchlistTile(BuildContext context, dynamic item) {
    final isUp = item.gainLossPercent >= 0;
    final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
    final shares = item.theoreticalShares;
    final currentValue = shares * (item.currentPrice ?? item.addedPrice);
    
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        return GestureDetector(
          onLongPress: () => _showWatchlistItemMenu(context, provider, subscription, item),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => StockDetailSheet(symbol: item.symbol)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: Container(
                width: 48, 
                height: 48, 
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isUp ? Icons.trending_up : Icons.trending_down, color: color, size: 20),
                    Text('$shares', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              title: Row(
                children: [
                  Text(item.displaySymbol, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text(item.formattedReturn, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${item.name} • ${item.daysSinceAdded}d held', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor), overflow: TextOverflow.ellipsis),
                          if (item.triggerRule != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.bolt, size: 10, color: AppTheme.accentColor),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(item.triggerRule!, style: const TextStyle(fontSize: 9, color: AppTheme.accentColor), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.capitalInvested != 10000.0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3)),
                        child: Text('\$${(item.capitalInvested / 1000).toStringAsFixed(0)}K', style: const TextStyle(fontSize: 8, color: AppTheme.accentColor)),
                      ),
                  ],
                ),
              ),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('\$${currentValue.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text('${item.formattedCurrentPrice}/share', style: const TextStyle(color: AppTheme.textTertiaryColor, fontSize: 10)),
              ]),
            ),
          ),
        );
      },
    );
  }
  
  void _showWatchlistItemMenu(BuildContext context, AppProvider provider, SubscriptionService subscription, dynamic item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(item.displaySymbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Text(item.name, style: const TextStyle(color: AppTheme.textSecondaryColor)),
              if (item.triggerRule != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.bolt, size: 14, color: AppTheme.accentColor),
                    const SizedBox(width: 4),
                    Text('Added via: ${item.triggerRule}', style: const TextStyle(fontSize: 12, color: AppTheme.accentColor)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              
              // Current investment info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Capital Invested', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                      Text('\$${item.capitalInvested.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('Shares', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                      Text('${item.theoreticalShares}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Edit capital button (Pro only)
              ListTile(
                leading: Icon(
                  Icons.attach_money,
                  color: subscription.isPro ? AppTheme.accentColor : AppTheme.textTertiaryColor,
                ),
                title: const Text('Change Capital Amount'),
                subtitle: Text(
                  subscription.isPro ? 'Set custom investment amount' : 'Pro feature',
                  style: TextStyle(fontSize: 11, color: subscription.isPro ? AppTheme.textSecondaryColor : AppTheme.textTertiaryColor),
                ),
                trailing: subscription.isPro 
                  ? const Icon(Icons.chevron_right) 
                  : const Icon(Icons.lock, size: 16, color: AppTheme.textTertiaryColor),
                onTap: () {
                  Navigator.pop(ctx);
                  if (subscription.isPro) {
                    _showEditCapitalDialog(context, provider, item);
                  } else {
                    PaywallScreen.show(context, feature: ProFeature.unlimitedWatchlist);
                  }
                },
              ),
              
              const Divider(),
              
              // Remove from watchlist
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
                title: const Text('Remove from Watchlist', style: TextStyle(color: AppTheme.errorColor)),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.removeFromWatchlist(item.symbol);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showEditCapitalDialog(BuildContext context, AppProvider provider, dynamic item) {
    final controller = TextEditingController(text: item.capitalInvested.toStringAsFixed(0));
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: Text('Edit Capital - ${item.displaySymbol}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How much would you have invested?', style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                hintText: '10000',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [5000, 10000, 25000, 50000].map((amount) => 
                ActionChip(
                  label: Text('\$${(amount / 1000).toStringAsFixed(0)}K'),
                  onPressed: () => controller.text = amount.toString(),
                  backgroundColor: AppTheme.backgroundColor,
                ),
              ).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newCapital = double.tryParse(controller.text) ?? 10000;
              if (newCapital > 0) {
                provider.updateWatchlistCapital(item.symbol, newCapital);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _scanResultTile(BuildContext context, ScanResult result) {
    final stock = result.stock;
    final isUp = stock.changePercent >= 0;
    final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
    
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final isInWatchlist = provider.isInWatchlist(stock.symbol);
        
        return GestureDetector(
          onLongPress: () => _showScanResultMenu(context, provider, result),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => StockDetailSheet(symbol: stock.symbol)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Icon(isUp ? Icons.trending_up : Icons.trending_down, color: color)),
              title: Row(
                children: [
                  Text(stock.displaySymbol, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (isInWatchlist) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.bookmark, size: 14, color: AppTheme.accentColor),
                  ],
                ],
              ),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(stock.name, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                // Show all matched rules
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: result.matchedRuleNames.take(3).map((ruleName) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text(ruleName, style: const TextStyle(fontSize: 9, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                  )).toList(),
                ),
                if (result.matchedRuleNames.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('+${result.matchedRuleNames.length - 3} more', style: const TextStyle(fontSize: 9, color: AppTheme.textTertiaryColor)),
                  ),
              ]),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(stock.formattedPrice, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${isUp ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%', style: TextStyle(color: color, fontSize: 13)),
              ]),
            ),
          ),
        );
      },
    );
  }
  
  void _showScanResultMenu(BuildContext context, AppProvider provider, ScanResult result) {
    final stock = result.stock;
    final isInWatchlist = provider.isInWatchlist(stock.symbol);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(stock.displaySymbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              Text(stock.name, style: const TextStyle(color: AppTheme.textSecondaryColor)),
              const SizedBox(height: 8),
              // Show all matched rules
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: result.matchedRuleNames.map((ruleName) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, size: 12, color: AppTheme.accentColor),
                      const SizedBox(width: 4),
                      Text(ruleName, style: const TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w500)),
                    ],
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),
              
              if (!isInWatchlist)
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: AppTheme.successColor),
                  title: const Text('Add to Watchlist'),
                  subtitle: Text('Matched: ${result.matchedRuleNames.join(", ")}', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(ctx);
                    provider.addToWatchlist(
                      stock.symbol, 
                      stock.name, 
                      stock.currentPrice, 
                      triggerRule: result.ruleName,
                      triggerRules: result.matchedRuleNames,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${stock.displaySymbol} added to watchlist'), backgroundColor: AppTheme.successColor),
                    );
                  },
                )
              else
                const ListTile(
                  leading: Icon(Icons.check_circle, color: AppTheme.textTertiaryColor),
                  title: Text('Already in Watchlist', style: TextStyle(color: AppTheme.textTertiaryColor)),
                  subtitle: Text('This stock is already being tracked', style: TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                ),
              
              ListTile(
                leading: const Icon(Icons.open_in_new, color: AppTheme.textSecondaryColor),
                title: const Text('View Details'),
                onTap: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => StockDetailSheet(symbol: stock.symbol));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(48),
      child: Column(children: [
        Icon(Icons.radar, size: 64, color: AppTheme.textTertiaryColor),
        SizedBox(height: 16),
        Text('Welcome to ASX Radar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text('Tap QUICK SCAN to find stocks matching your rules.\n\nUpgrade to Pro for Full ASX Scan.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor), textAlign: TextAlign.center),
      ]),
    );
  }
}