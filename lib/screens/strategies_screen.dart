import 'package:flutter/material.dart';
import '../utils/theme.dart';
import 'rules_screen.dart';
import 'backtest_screen.dart';

/// Combined Strategy tab: Rules + Backtest Lab in one flow
class StrategiesScreen extends StatefulWidget {
  final String? initialCategory;

  const StrategiesScreen({super.key, this.initialCategory});

  static final GlobalKey<StrategiesScreenState> strategiesKey = GlobalKey<StrategiesScreenState>();

  @override
  State<StrategiesScreen> createState() => StrategiesScreenState();
}

class StrategiesScreenState extends State<StrategiesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _activeCategory;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _activeCategory = widget.initialCategory;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void filterByCategory(String category) {
    setState(() => _activeCategory = category);
    _tabController.animateTo(0);
  }

  void clearFilter() {
    setState(() => _activeCategory = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'Strategy',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5),
              ),
            ),

            // Tab bar
            Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(3),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: AppTheme.accentColor,
                unselectedLabelColor: AppTheme.textSecondaryColor,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(text: 'My Rules', height: 36),
                  Tab(text: 'Backtest Lab', height: 36),
                ],
              ),
            ),

            // Category filter chip
            if (_activeCategory != null)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(_getCategoryIcon(_activeCategory!), size: 14, color: AppTheme.accentColor),
                    const SizedBox(width: 8),
                    Text(
                      _getCategoryLabel(_activeCategory!),
                      style: const TextStyle(fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: clearFilter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(4)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.close, size: 12, color: AppTheme.textSecondaryColor),
                          SizedBox(width: 4),
                          Text('Clear', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
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

  String _getCategoryLabel(String category) {
    switch (category) {
      case 'momentum': return 'Momentum Rules';
      case 'breakouts': return 'Breakout Rules';
      case 'reversal': return 'Reversal Rules';
      case 'golden': return 'Trend Rules';
      default: return category;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'momentum': return Icons.trending_up;
      case 'breakouts': return Icons.open_in_new;
      case 'reversal': return Icons.change_circle_outlined;
      case 'golden': return Icons.show_chart;
      default: return Icons.rule;
    }
  }
}
