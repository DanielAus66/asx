import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/subscription_service.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import 'paywall_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _refreshingSymbols = false;
  int _symbolCount = 0;

  @override
  void initState() {
    super.initState();
    _symbolCount = ApiService.allAsxSymbolsDynamic.length;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, SubscriptionService>(
      builder: (context, provider, subscription, child) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(backgroundColor: AppTheme.backgroundColor, title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSubscriptionCard(context, subscription),
              const SizedBox(height: 24),
              _buildSection('Data', [
                _buildTile(context, icon: Icons.refresh, title: 'Refresh Data', subtitle: 'Update stock prices and indicators', onTap: () async {
                  await provider.refreshData();
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data refreshed'), backgroundColor: AppTheme.successColor));
                }),
                _buildTile(context, icon: Icons.delete_outline, title: 'Clear Cache', subtitle: 'Remove cached stock data', onTap: () => _confirmClearCache(context, provider)),
              ]),
              const SizedBox(height: 24),
              _buildSection('ASX Universe', [
                _buildStatTile('Total ASX Symbols', '$_symbolCount stocks'),
                _buildTile(
                  context, 
                  icon: Icons.download, 
                  title: 'Refresh ASX List', 
                  subtitle: _refreshingSymbols ? 'Fetching...' : 'Download latest ASX company list',
                  trailing: _refreshingSymbols ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  onTap: _refreshingSymbols ? null : () async {
                    setState(() => _refreshingSymbols = true);
                    try {
                      final count = await ApiService.refreshAsxSymbols();
                      setState(() {
                        _symbolCount = count > 0 ? count : _symbolCount;
                        _refreshingSymbols = false;
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(count > 0 ? 'Updated: $count ASX symbols' : 'Could not fetch list, using cached data'),
                            backgroundColor: count > 0 ? AppTheme.successColor : AppTheme.warningColor,
                          ),
                        );
                      }
                    } catch (e) {
                      setState(() => _refreshingSymbols = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to refresh ASX list'), backgroundColor: AppTheme.errorColor),
                        );
                      }
                    }
                  },
                ),
              ]),
              const SizedBox(height: 24),
              _buildSection('Personal', [
                _UserNameTile(),
                _PortfolioSourceTile(),
              ]),
              const SizedBox(height: 24),
              _buildSection('Statistics', [
                _buildStatTile('Watchlist', '${provider.watchlist.length}${subscription.isPro ? '' : ' / ${SubscriptionService.freeMaxWatchlist}'}'),
                _buildStatTile('Rules', '${provider.rules.length} (${provider.activeRules.length} active)'),
                _buildStatTile('Alerts', '${provider.alerts.length}'),
                _buildStatTile('Cached Stocks', '${provider.stockCache.length}'),
              ]),
              const SizedBox(height: 24),
              _buildSection('About', [
                _buildTile(context, icon: Icons.info_outline, title: 'Version', subtitle: '1.0.0', onTap: null),
                _buildTile(context, icon: Icons.code, title: 'Data Source', subtitle: 'Yahoo Finance', onTap: null),
              ]),
              
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubscriptionCard(BuildContext context, SubscriptionService subscription) {
    if (subscription.isPro) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF9500)]), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.star, color: Colors.black),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(subscription.isProPlus ? 'Pro+ Member' : 'Pro Member', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (subscription.expiryDate != null) Text('Renews ${_formatDate(subscription.expiryDate!)}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.successColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: const Text('ACTIVE', style: TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.dividerColor),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildProStat('Rules', 'All', Icons.rule),
                _buildProStat('Scan', 'Full ASX', Icons.radar),
                _buildProStat('Backtest', 'Unlimited', Icons.history),
              ],
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: () => PaywallScreen.show(context),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Row(
              children: [
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.person, color: AppTheme.textSecondaryColor)),
                const SizedBox(width: 16),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Free Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('Limited features', style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor))])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(8)),
                  child: const Text('UPGRADE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.dividerColor),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildFreeStat('Rules', '2 of 6'),
                _buildFreeStat('Scan', '20 stocks'),
                _buildFreeStat('Backtest', '1/day'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProStat(String label, String value, IconData icon) {
    return Column(children: [
      Icon(icon, color: AppTheme.accentColor, size: 20),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondaryColor)),
    ]);
  }

  Widget _buildFreeStat(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondaryColor)),
    ]);
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
        child: Column(children: children),
      ),
    ]);
  }

  Widget _buildTile(BuildContext context, {required IconData icon, required String title, required String subtitle, VoidCallback? onTap, Widget? trailing}) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondaryColor),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: AppTheme.textTertiaryColor) : null),
      onTap: onTap,
    );
  }

  Widget _buildStatTile(String label, String value) {
    return ListTile(
      title: Text(label),
      trailing: Text(value, style: const TextStyle(color: AppTheme.textSecondaryColor)),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _confirmClearCache(BuildContext context, AppProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Clear Cache?'),
        content: const Text('This will remove all cached stock data. You\'ll need to refresh to get new data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear', style: TextStyle(color: AppTheme.errorColor))),
        ],
      ),
    );
    if (confirmed == true) {
      await StorageService.clearAll();
      await provider.initialize();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared')));
    }
  }
}

/// User name tile with edit functionality
class _UserNameTile extends StatefulWidget {
  @override
  State<_UserNameTile> createState() => _UserNameTileState();
}

class _UserNameTileState extends State<_UserNameTile> {
  String? _userName;
  
  @override
  void initState() {
    super.initState();
    _loadName();
  }
  
  Future<void> _loadName() async {
    final name = await StorageService.getUserName();
    setState(() => _userName = name);
  }
  
  void _editName() {
    final controller = TextEditingController(text: _userName ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Your Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Enter your name',
            filled: true,
            fillColor: AppTheme.backgroundColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondaryColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              await StorageService.saveUserName(name);
              setState(() => _userName = name.isEmpty ? null : name);
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              foregroundColor: Colors.black,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppTheme.accentColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.person_outline, color: AppTheme.accentColor),
      ),
      title: const Text('Display Name'),
      subtitle: Text(
        _userName ?? 'Not set',
        style: TextStyle(
          color: _userName != null ? AppTheme.textSecondaryColor : AppTheme.textTertiaryColor,
          fontStyle: _userName == null ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textTertiaryColor),
      onTap: _editName,
    );
  }
}

/// Portfolio source selector: Holdings Only, Watchlist Only, Both
class _PortfolioSourceTile extends StatelessWidget {
  String _label(PortfolioSource source) {
    switch (source) {
      case PortfolioSource.holdings: return 'Holdings Only';
      case PortfolioSource.watchlist: return 'Watchlist Only';
      case PortfolioSource.both: return 'Holdings + Watchlist';
    }
  }

  String _subtitle(PortfolioSource source) {
    switch (source) {
      case PortfolioSource.holdings: return 'Portfolio value from your actual shares';
      case PortfolioSource.watchlist: return 'Simulated returns from tracked stocks';
      case PortfolioSource.both: return 'Combined real + simulated P&L';
    }
  }

  IconData _icon(PortfolioSource source) {
    switch (source) {
      case PortfolioSource.holdings: return Icons.account_balance_wallet;
      case PortfolioSource.watchlist: return Icons.bookmark;
      case PortfolioSource.both: return Icons.join_full;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return ListTile(
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon(provider.portfolioSource), color: AppTheme.accentColor, size: 20),
          ),
          title: const Text('Portfolio Source'),
          subtitle: Text(
            _label(provider.portfolioSource),
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppTheme.textTertiaryColor),
          onTap: () => _showPicker(context, provider),
        );
      },
    );
  }

  void _showPicker(BuildContext context, AppProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Portfolio Source', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Choose what the Portfolio card on Home tracks', style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
              const SizedBox(height: 16),
              ...PortfolioSource.values.map((source) {
                final isActive = source == provider.portfolioSource;
                return GestureDetector(
                  onTap: () {
                    provider.setPortfolioSource(source);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.accentColor.withValues(alpha: 0.12) : AppTheme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive ? AppTheme.accentColor.withValues(alpha: 0.4) : Colors.transparent,
                      ),
                    ),
                    child: Row(children: [
                      Icon(_icon(source), size: 20,
                          color: isActive ? AppTheme.accentColor : AppTheme.textSecondaryColor),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_label(source), style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14,
                          color: isActive ? AppTheme.accentColor : AppTheme.textPrimaryColor,
                        )),
                        Text(_subtitle(source), style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                      ])),
                      if (isActive)
                        const Icon(Icons.check_circle, color: AppTheme.accentColor, size: 20),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}