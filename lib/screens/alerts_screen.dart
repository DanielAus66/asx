import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';
import 'stock_detail_sheet.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        title: const Text('Alerts'),
        actions: [
          Consumer<AppProvider>(builder: (context, provider, child) {
            if (provider.alerts.isEmpty) return const SizedBox();
            return IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _confirmClear(context, provider));
          }),
        ],
      ),
      body: Consumer<AppProvider>(builder: (context, provider, child) {
        if (provider.alerts.isEmpty) {
          return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.notifications_off_outlined, size: 64, color: AppTheme.textTertiaryColor),
            SizedBox(height: 16),
            Text('No alerts yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('Alerts will appear when scans find matching stocks', style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16), itemCount: provider.alerts.length,
          itemBuilder: (context, index) {
            final alert = provider.alerts[index];
            final isRead = alert['isRead'] == true;
            final change = (alert['change'] as num?)?.toDouble() ?? 0;
            final isUp = change >= 0;
            final color = isUp ? AppTheme.successColor : AppTheme.errorColor;
            final timestamp = DateTime.parse(alert['timestamp']);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isRead ? AppTheme.cardColor : AppTheme.cardColor.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: isRead ? null : Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
              ),
              child: ListTile(
                onTap: () {
                  provider.markAlertRead(alert['id']);
                  showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                    builder: (_) => StockDetailSheet(symbol: alert['symbol']));
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(width: 44, height: 44,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Icon(isUp ? Icons.trending_up : Icons.trending_down, color: color)),
                title: Row(children: [
                  Text((alert['symbol'] as String).replaceAll('.AX', ''), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  if (!isRead) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(4)),
                    child: const Text('NEW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black))),
                ]),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(alert['ruleName'] ?? '', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
                  Text(DateFormat('MMM d, HH:mm').format(timestamp), style: const TextStyle(fontSize: 10, color: AppTheme.textTertiaryColor)),
                ]),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('\$${(alert['price'] as num).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${isUp ? '+' : ''}${change.toStringAsFixed(2)}%', style: TextStyle(color: color, fontSize: 13)),
                ]),
              ),
            );
          },
        );
      }),
    );
  }

  void _confirmClear(BuildContext context, AppProvider provider) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surfaceColor,
      title: const Text('Clear All Alerts?'),
      content: const Text('This action cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        TextButton(onPressed: () { provider.clearAlerts(); Navigator.pop(context); },
          child: const Text('CLEAR', style: TextStyle(color: AppTheme.errorColor))),
      ],
    ));
  }
}
