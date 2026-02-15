import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/subscription_service.dart';
import '../models/watchlist_item.dart';
import '../utils/theme.dart';
import 'stock_detail_sheet.dart';
import 'search_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});
  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  String _sortBy = 'added'; // 'added', 'gainLoss', 'name', 'dayChange'
  bool _sortAsc = false;
  
  @override
  void initState() {
    super.initState();
    // Refresh prices on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppProvider>(context, listen: false).refreshWatchlistPrices();
    });
  }

  List<WatchlistItem> _sortedWatchlist(List<WatchlistItem> items) {
    final sorted = List<WatchlistItem>.from(items);
    switch (_sortBy) {
      case 'gainLoss':
        sorted.sort((a, b) => _sortAsc 
          ? a.gainLossPercent.compareTo(b.gainLossPercent)
          : b.gainLossPercent.compareTo(a.gainLossPercent));
        break;
      case 'name':
        sorted.sort((a, b) => _sortAsc 
          ? a.displaySymbol.compareTo(b.displaySymbol)
          : b.displaySymbol.compareTo(a.displaySymbol));
        break;
      case 'dayChange':
        sorted.sort((a, b) => _sortAsc 
          ? (a.dayChangePercent ?? 0).compareTo(b.dayChangePercent ?? 0)
          : (b.dayChangePercent ?? 0).compareTo(a.dayChangePercent ?? 0));
        break;
      default: // 'added'
        sorted.sort((a, b) => _sortAsc 
          ? a.addedAt.compareTo(b.addedAt)
          : b.addedAt.compareTo(a.addedAt));
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        final watchlist = _sortedWatchlist(provider.watchlist);
        
        // Portfolio summary calculations
        double totalInvested = 0;
        double totalCurrent = 0;
        int winners = 0;
        int losers = 0;
        
        for (final item in watchlist) {
          totalInvested += item.capitalInvested;
          totalCurrent += item.capitalInvested + item.dollarGainLoss;
          if (item.gainLossPercent > 0) winners++;
          if (item.gainLossPercent < 0) losers++;
        }
        
        final totalGainLoss = totalCurrent - totalInvested;
        final totalGainLossPercent = totalInvested > 0 ? (totalGainLoss / totalInvested * 100) : 0.0;
        final isPortfolioUp = totalGainLoss >= 0;
        
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppTheme.backgroundColor,
            title: const Text('Watchlist'),
            actions: [
              IconButton(
                icon: const Icon(Icons.search, size: 22),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort, size: 22),
                onSelected: (value) {
                  setState(() {
                    if (_sortBy == value) {
                      _sortAsc = !_sortAsc;
                    } else {
                      _sortBy = value;
                      _sortAsc = false;
                    }
                  });
                },
                itemBuilder: (context) => [
                  _buildSortOption('added', 'Date Added'),
                  _buildSortOption('gainLoss', 'Total Return'),
                  _buildSortOption('dayChange', 'Day Change'),
                  _buildSortOption('name', 'Symbol'),
                ],
              ),
            ],
          ),
          body: watchlist.isEmpty
            ? _buildEmptyState(context)
            : RefreshIndicator(
                onRefresh: () => provider.refreshWatchlistPrices(),
                color: AppTheme.accentColor,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Portfolio summary card
                    if (watchlist.length >= 2) ...[
                      _buildPortfolioSummary(
                        totalInvested: totalInvested,
                        totalGainLoss: totalGainLoss,
                        totalGainLossPercent: totalGainLossPercent,
                        isUp: isPortfolioUp,
                        count: watchlist.length,
                        winners: winners,
                        losers: losers,
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // Stock items
                    ...watchlist.map((item) => _buildWatchlistCard(context, provider, item)),
                    
                    const SizedBox(height: 80),
                  ],
                ),
              ),
        );
      },
    );
  }
  
  PopupMenuItem<String> _buildSortOption(String value, String label) {
    final isActive = _sortBy == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Text(label, style: TextStyle(
            color: isActive ? AppTheme.accentColor : Colors.white,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          )),
          if (isActive) ...[
            const Spacer(),
            Icon(
              _sortAsc ? Icons.arrow_upward : Icons.arrow_downward, 
              size: 16, 
              color: AppTheme.accentColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPortfolioSummary({
    required double totalInvested,
    required double totalGainLoss,
    required double totalGainLossPercent,
    required bool isUp,
    required int count,
    required int winners,
    required int losers,
  }) {
    final gainColor = isUp ? AppTheme.successColor : AppTheme.errorColor;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gainColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            '${isUp ? '+' : '-'}\$${totalGainLoss.abs().toStringAsFixed(0)}',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: gainColor),
          ),
          const SizedBox(height: 4),
          Text(
            '${isUp ? '+' : ''}${totalGainLossPercent.toStringAsFixed(1)}% total return • $count stocks',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMiniStat('$winners', 'winners', AppTheme.successColor),
              Container(width: 1, height: 20, color: AppTheme.dividerColor, margin: const EdgeInsets.symmetric(horizontal: 16)),
              _buildMiniStat('$losers', 'losers', AppTheme.errorColor),
              Container(width: 1, height: 20, color: AppTheme.dividerColor, margin: const EdgeInsets.symmetric(horizontal: 16)),
              _buildMiniStat('\$${(totalInvested / 1000).toStringAsFixed(0)}k', 'tracked', AppTheme.textSecondaryColor),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildMiniStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
      ],
    );
  }

  Widget _buildWatchlistCard(BuildContext context, AppProvider provider, WatchlistItem item) {
    final isUp = item.gainLossPercent >= 0;
    final gainColor = isUp ? AppTheme.successColor : AppTheme.errorColor;
    final triggerRules = item.allTriggerRules;
    
    return Dismissible(
      key: Key(item.symbol),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.errorColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: AppTheme.errorColor),
      ),
      onDismissed: (_) => provider.removeFromWatchlist(item.symbol),
      child: GestureDetector(
        onTap: () => _openStockDetail(context, item.symbol, triggerRules: triggerRules),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Symbol + name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.displaySymbol, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(item.name, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  // Price + return
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(item.formattedCurrentPrice, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: gainColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.formattedReturn,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: gainColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Trigger rules row
              if (triggerRules.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.bolt, size: 12, color: AppTheme.accentColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        triggerRules.join(' • '),
                        style: const TextStyle(fontSize: 11, color: AppTheme.accentColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${item.daysSinceAdded}d ago',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 64, color: AppTheme.textTertiaryColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('No stocks tracked yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Add stocks from Discover or run a scan to find setups, then track them here to monitor performance.',
              style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Search Stocks'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.black),
            ),
          ],
        ),
      ),
    );
  }
  
  void _openStockDetail(BuildContext context, String symbol, {List<String>? triggerRules}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: StockDetailSheet(symbol: symbol, triggerRules: triggerRules),
        ),
      ),
    );
  }
}
