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