import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/subscription_service.dart';
import '../models/stock.dart';
import '../utils/theme.dart';
import 'stock_detail_sheet.dart';
import 'paywall_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Stock> _results = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _results = []; _error = null; });
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final results = await provider.searchStocks(query.trim());
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
          _error = results.isEmpty ? 'No stocks found for "$query"' : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Search failed: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppTheme.backgroundColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Search ASX stocks...',
                hintStyle: TextStyle(color: AppTheme.textTertiaryColor),
                border: InputBorder.none,
              ),
              onChanged: (value) {
                // Debounce search
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (_controller.text == value) {
                    _search(value);
                  }
                });
              },
              onSubmitted: _search,
            ),
            actions: [
              if (_controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                    setState(() { _results = []; _error = null; });
                  },
                ),
            ],
          ),
          body: _buildBody(provider, subscription),
        );
      },
    );
  }

  Widget _buildBody(AppProvider provider, SubscriptionService subscription) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.accentColor),
            SizedBox(height: 16),
            Text('Searching...', style: TextStyle(color: AppTheme.textSecondaryColor)),
          ],
        ),
      );
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off, size: 64, color: AppTheme.textTertiaryColor),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppTheme.textSecondaryColor), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              const Text(
                'Tips:\n• Enter stock code (BHP, CBA, CSL)\n• Enter company name (Woolworths, Telstra)\n• Check your internet connection',
                style: TextStyle(fontSize: 13, color: AppTheme.textTertiaryColor),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty && _controller.text.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search, size: 64, color: AppTheme.textTertiaryColor),
              const SizedBox(height: 16),
              const Text('Search ASX Stocks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                'Enter a stock code or company name\nto find ASX listed stocks',
                style: TextStyle(color: AppTheme.textSecondaryColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: ['BHP', 'CBA', 'CSL', 'WOW', 'TLS'].map((code) {
                  return ActionChip(
                    label: Text(code),
                    backgroundColor: AppTheme.cardColor,
                    onPressed: () {
                      _controller.text = code;
                      _search(code);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final stock = _results[index];
        final isUp = stock.changePercent >= 0;
        final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
        final inWatchlist = provider.isInWatchlist(stock.symbol);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onTap: () {
              // Add to cache first so detail sheet can find it
              provider.stockCache[stock.symbol] = stock;
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => StockDetailSheet(symbol: stock.symbol),
              );
            },
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  stock.displaySymbol.substring(0, stock.displaySymbol.length > 3 ? 3 : stock.displaySymbol.length),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
            title: Text(stock.displaySymbol, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              stock.name,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(stock.formattedPrice, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '${isUp ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    inWatchlist ? Icons.bookmark : Icons.bookmark_border,
                    color: inWatchlist ? AppTheme.accentColor : AppTheme.textTertiaryColor,
                  ),
                  onPressed: () {
                    if (inWatchlist) {
                      provider.removeFromWatchlist(stock.symbol);
                    } else if (provider.canAddToWatchlist()) {
                      provider.addToWatchlist(stock.symbol, stock.name, stock.currentPrice);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${stock.displaySymbol} added to watchlist'),
                          backgroundColor: AppTheme.successColor,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    } else {
                      PaywallScreen.show(context, feature: ProFeature.unlimitedWatchlist);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
