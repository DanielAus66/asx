import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/scan_scheduler_service.dart';
import '../utils/theme.dart';

class BackgroundScannerScreen extends StatefulWidget {
  const BackgroundScannerScreen({super.key});

  @override
  State<BackgroundScannerScreen> createState() => _BackgroundScannerScreenState();
}

class _BackgroundScannerScreenState extends State<BackgroundScannerScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh running state when app comes back to foreground
      Provider.of<ScanSchedulerService>(context, listen: false)
          .refreshRunningState();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Background Scanner',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.backgroundColor,
      ),
      body: Consumer<ScanSchedulerService>(
        builder: (context, scheduler, _) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── Market status ──────────────────────────────────────────
              _buildMarketStatusCard(scheduler),
              const SizedBox(height: 20),

              // ── Enable toggle ──────────────────────────────────────────
              _buildEnableCard(context, scheduler),
              const SizedBox(height: 20),

              if (scheduler.enabled) ...[
                // ── Interval picker ────────────────────────────────────
                _buildSectionLabel('Scan Interval'),
                const SizedBox(height: 8),
                _buildIntervalPicker(context, scheduler),
                const SizedBox(height: 20),

                // ── Market hours toggle ────────────────────────────────
                _buildOptionRow(
                  icon: Icons.access_time,
                  title: 'Market hours only',
                  subtitle:
                      'Only scan Mon–Fri, 10:00am–4:00pm AEST. Saves battery.',
                  value: scheduler.marketHoursOnly,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    scheduler.setMarketHoursOnly(v);
                  },
                ),
                const SizedBox(height: 20),

                // ── What gets scanned ──────────────────────────────────
                _buildInfoCard(),
                const SizedBox(height: 20),

                // ── Scan now ───────────────────────────────────────────
                if (scheduler.isServiceRunning) _buildScanNowButton(scheduler),
                const SizedBox(height: 20),

                // ── Battery optimisation ───────────────────────────────
                _buildBatteryCard(context),
              ],

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  // ── Cards ──────────────────────────────────────────────────────────────────

  Widget _buildMarketStatusCard(ScanSchedulerService scheduler) {
    final isOpen = ScanSchedulerService.isMarketHours;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOpen
              ? AppTheme.successColor.withValues(alpha: 0.3)
              : AppTheme.dividerColor,
        ),
      ),
      child: Row(children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color: isOpen ? AppTheme.successColor : AppTheme.textTertiaryColor,
            shape: BoxShape.circle,
            boxShadow: isOpen
                ? [BoxShadow(color: AppTheme.successColor.withValues(alpha: 0.5), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              isOpen ? 'Market Open' : 'Market Closed',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isOpen ? AppTheme.successColor : AppTheme.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              ScanSchedulerService.marketStatusLabel,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor),
            ),
          ]),
        ),
        const Text('AEST', style: TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
      ]),
    );
  }

  Widget _buildEnableCard(BuildContext context, ScanSchedulerService scheduler) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheduler.enabled
            ? AppTheme.accentColor.withValues(alpha: 0.08)
            : AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheduler.enabled
              ? AppTheme.accentColor.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: scheduler.enabled
                ? AppTheme.accentColor.withValues(alpha: 0.15)
                : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            scheduler.isServiceRunning ? Icons.radar : Icons.radar_outlined,
            color: scheduler.enabled ? AppTheme.accentColor : AppTheme.textSecondaryColor,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Background Scanner',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              scheduler.isServiceRunning
                  ? 'Running · watching your watchlist'
                  : scheduler.enabled
                      ? 'Enabled but not running'
                      : 'Off — notifications disabled',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor),
            ),
          ]),
        ),
        Switch(
          value: scheduler.enabled,
          onChanged: (v) async {
            HapticFeedback.mediumImpact();
            await scheduler.setEnabled(v);
          },
          activeThumbColor: AppTheme.accentColor,
        ),
      ]),
    );
  }

  Widget _buildIntervalPicker(
      BuildContext context, ScanSchedulerService scheduler) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: ScanInterval.values.map((interval) {
          final selected = scheduler.interval == interval;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                scheduler.setInterval(interval);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.surfaceColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  interval.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? AppTheme.accentColor : AppTheme.textSecondaryColor,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOptionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: AppTheme.textSecondaryColor),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor, height: 1.4)),
        ])),
        Switch(value: value, onChanged: onChanged, activeThumbColor: AppTheme.accentColor),
      ]),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.info_outline, size: 15, color: AppTheme.textSecondaryColor),
            SizedBox(width: 8),
            Text('What gets scanned',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
          ]),
          const SizedBox(height: 10),
          const Text(
            'Background scanning uses your active rules but only evaluates conditions that work with current price data — no internet-heavy historical downloads.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor, height: 1.5),
          ),
          const SizedBox(height: 10),
          _ruleTag('Price change >', Icons.trending_up),
          _ruleTag('Near 52-week high / low', Icons.show_chart),
          _ruleTag('Volume spike', Icons.bar_chart),
          _ruleTag('Stealth accumulation', Icons.visibility_off),
          const SizedBox(height: 8),
          const Text(
            'Rules requiring historical prices (RSI, MACD, momentum) still run when you open the app and scan manually.',
            style: TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _ruleTag(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 13, color: AppTheme.accentColor),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimaryColor)),
      ]),
    );
  }

  Widget _buildScanNowButton(ScanSchedulerService scheduler) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        scheduler.triggerImmediateScan();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scan triggered — check notifications in a moment'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow, size: 18, color: AppTheme.accentColor),
            SizedBox(width: 8),
            Text('Scan Now',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.battery_alert, size: 15, color: AppTheme.warningColor),
            SizedBox(width: 8),
            Text('Battery Optimisation',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.warningColor)),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Some manufacturers (Samsung, Xiaomi, Oppo) aggressively kill background apps. If you stop receiving notifications, disable battery optimisation for ASX Radar.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor, height: 1.5),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _showBatteryInstructions(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings, size: 13, color: AppTheme.warningColor),
                  SizedBox(width: 6),
                  Text('How to fix this',
                      style: TextStyle(fontSize: 12, color: AppTheme.warningColor, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor));
  }

  void _showBatteryInstructions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: AppTheme.dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Fix Background Scanning',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _instructionStep('1', 'Open Android Settings'),
            _instructionStep('2', 'Go to Apps → ASX Radar'),
            _instructionStep('3', 'Tap Battery → set to "Unrestricted"'),
            _instructionStep('4', 'Also check: Settings → Battery → Background app limits'),
            const SizedBox(height: 16),
            const Text(
              'On Samsung: Settings → Device Care → Battery → App Power Management → add ASX Radar to "Never sleeping apps".',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondaryColor, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _instructionStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22, height: 22,
            decoration: const BoxDecoration(
              color: AppTheme.accentColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondaryColor, height: 1.4))),
        ],
      ),
    );
  }
}
