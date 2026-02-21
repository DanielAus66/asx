import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/subscription_service.dart';
import '../services/scan_scheduler_service.dart';
import '../utils/theme.dart';
import 'settings_screen.dart';
import 'alerts_screen.dart';
import 'holdings_scanner_screen.dart';
import 'background_scanner_screen.dart';
import 'paywall_screen.dart';

/// More tab — settings, account, less-frequent features
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionService>(
      builder: (context, subscription, child) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 8),
                const Text('More', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                const SizedBox(height: 24),

                // Pro badge / upgrade prompt
                if (!subscription.isPro)
                  _buildUpgradeCard(context)
                else
                  _buildProBadge(),
                const SizedBox(height: 20),

                // Menu items
                _buildMenuItem(
                  context,
                  icon: Icons.notifications_outlined,
                  label: 'Alerts',
                  subtitle: 'Price & signal notifications',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsScreen())),
                ),
                _buildBackgroundScannerItem(context),
                _buildMenuItem(
                  context,
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Holdings Scanner',
                  subtitle: 'Scan your portfolio for signals',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HoldingsScannerScreen())),
                ),
                const Divider(color: AppTheme.dividerColor, height: 32),
                _buildMenuItem(
                  context,
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  subtitle: 'Account, data, appearance',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.info_outline,
                  label: 'About ASX Radar',
                  subtitle: 'Version, licenses, support',
                  onTap: () => _showAbout(context),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUpgradeCard(BuildContext context) {
    return GestureDetector(
      onTap: () => PaywallScreen.show(context, feature: ProFeature.fullAsxScan),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.accentColor.withValues(alpha: 0.15), AppTheme.accentColor.withValues(alpha: 0.05)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.bolt, color: AppTheme.accentColor, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Upgrade to Pro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 2),
                Text('Full ASX scan, unlimited rules & backtests', style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.accentColor),
          ],
        ),
      ),
    );
  }

  Widget _buildProBadge() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(6)),
            child: const Text('PRO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          const Text('All features unlocked', style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildBackgroundScannerItem(BuildContext context) {
    return Consumer<ScanSchedulerService>(
      builder: (context, scheduler, _) {
        final isOn = scheduler.enabled && scheduler.isServiceRunning;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackgroundScannerScreen()),
            ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: isOn
                        ? AppTheme.accentColor.withValues(alpha: 0.12)
                        : AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isOn ? Icons.radar : Icons.radar_outlined,
                    color: isOn ? AppTheme.accentColor : AppTheme.textSecondaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Background Scanner',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(
                      isOn
                          ? 'Active · ${scheduler.interval.label}'
                          : 'Off — tap to enable notifications',
                      style: TextStyle(
                          fontSize: 12,
                          color: isOn
                              ? AppTheme.accentColor
                              : AppTheme.textSecondaryColor),
                    ),
                  ],
                )),
                if (isOn)
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.successColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: AppTheme.successColor.withValues(alpha: 0.5), blurRadius: 4)
                      ],
                    ),
                  )
                else
                  const Icon(Icons.chevron_right, color: AppTheme.textTertiaryColor, size: 20),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: AppTheme.textSecondaryColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
              ])),
              const Icon(Icons.chevron_right, color: AppTheme.textTertiaryColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'ASX Radar',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.radar, color: Colors.black, size: 28),
      ),
    );
  }
}
