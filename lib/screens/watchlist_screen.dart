import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/watchlist_provider.dart';
import '../utils/theme.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  String _sortBy = 'added'; // 'added', 'performance', 'symbol'
  
  @override
  void initState() {
    super.initState();
    // Refresh prices on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<WatchlistProvider>(context, listen: false).refreshPrices();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WATCHLIST'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() {
                _sortBy = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'added',
                child: Text('Date Added'),
              ),
              const PopupMenuItem(
                value: 'performance',
                child: Text('Performance'),
              ),
              const PopupMenuItem(
                value: 'symbol',
                child: Text('Symbol'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Provider.of<WatchlistProvider>(context, listen: false).refreshPrices();
            },
          ),
        ],
      ),
      body: Consumer<WatchlistProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          
          if (provider.watchlist.isEmpty) {
            return _buildEmptyState();
          }
          
          return Column(
            children: [
              // Portfolio summary
              _buildPortfolioSummary(provider),
              
              // Watchlist items
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => provider.refreshPrices(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _getSortedWatchlist(provider).length,
                    itemBuilder: (context, index) {
                      final item = _getSortedWatchlist(provider)[index];
                      return _buildWatchlistCard(context, item, provider);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<WatchlistItem> _getSortedWatchlist(WatchlistProvider provider) {
    final list = List<WatchlistItem>.from(provider.watchlist);
    
    switch (_sortBy) {
      case 'performance':
        list.sort((a, b) => (b.priceChangePercent ?? 0).compareTo(a.priceChangePercent ?? 0));
        break;
      case 'symbol':
        list.sort((a, b) => a.symbol.compareTo(b.symbol));
        break;
      case 'added':
      default:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
    }
    
    return list;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.bookmark_outline,
            size: 64,
            color: AppTheme.textSecondaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            'Your Watchlist is Empty',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Add stocks from scan results, volume alerts,\nor backtest matches to track their performance.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondaryColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioSummary(WatchlistProvider provider) {
    final stats = provider.portfolioStats;
    final totalChange = stats['totalChangePercent'] ?? 0;
    final winners = stats['winners']?.toInt() ?? 0;
    final losers = stats['losers']?.toInt() ?? 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          bottom: BorderSide(color: AppTheme.accentColor.withOpacity(0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PORTFOLIO PERFORMANCE',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondaryColor,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${totalChange >= 0 ? '+' : ''}${totalChange.toStringAsFixed(2)}%',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: totalChange >= 0 ? AppTheme.successColor : AppTheme.errorColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'since added',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.arrow_upward, color: AppTheme.successColor, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '$winners',
                              style: const TextStyle(
                                color: AppTheme.successColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.arrow_downward, color: AppTheme.errorColor, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '$losers',
                              style: const TextStyle(
                                color: AppTheme.errorColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${provider.watchlist.length} stocks',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWatchlistCard(BuildContext context, WatchlistItem item, WatchlistProvider provider) {
    final change = item.priceChangePercent ?? 0;
    final isPositive = change >= 0;
    final changeColor = isPositive ? AppTheme.successColor : AppTheme.errorColor;
    
    return Dismissible(
      key: Key(item.symbol),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.errorColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
      ),
      onDismissed: (_) => provider.removeFromWatchlist(item.symbol),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.symbol.replaceAll('.AX', ''),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentColor,
                          ),
                        ),
                        Text(
                          item.name,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondaryColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Performance badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: changeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: changeColor.withOpacity(0.5)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPositive ? Icons.trending_up : Icons.trending_down,
                              color: changeColor,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${isPositive ? '+' : ''}${change.toStringAsFixed(2)}%',
                              style: TextStyle(
                                color: changeColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'since added',
                          style: TextStyle(
                            color: changeColor.withOpacity(0.8),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              
              // Price details
              Row(
                children: [
                  Expanded(
                    child: _buildDetailColumn(
                      'Current',
                      '\$${item.currentPrice?.toStringAsFixed(3) ?? '-'}',
                    ),
                  ),
                  Expanded(
                    child: _buildDetailColumn(
                      'Added At',
                      '\$${item.addedPrice.toStringAsFixed(3)}',
                    ),
                  ),
                  Expanded(
                    child: _buildDetailColumn(
                      'Change',
                      '${isPositive ? '+' : ''}\$${item.priceChange?.toStringAsFixed(3) ?? '-'}',
                      valueColor: changeColor,
                    ),
                  ),
                  Expanded(
                    child: _buildDetailColumn(
                      'Added',
                      DateFormat('MMM d').format(item.addedAt),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailColumn(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondaryColor,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}