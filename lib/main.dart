import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'services/subscription_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/rules_screen.dart';
import 'screens/backtest_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/holdings_scanner_screen.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.surfaceColor,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const ASXRadarApp());
}

class ASXRadarApp extends StatelessWidget {
  const ASXRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SubscriptionService()..initialize()),
        ChangeNotifierProxyProvider<SubscriptionService, AppProvider>(
          create: (_) => AppProvider(),
          update: (_, subscription, appProvider) {
            appProvider?.setSubscription(subscription);
            return appProvider ?? AppProvider();
          },
        ),
      ],
      child: MaterialApp(
        title: 'ASX Radar',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Initialize app provider after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppProvider>(context, listen: false).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          DashboardScreen(),
          RulesScreen(),
          HoldingsScannerScreen(),
          BacktestScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.dividerColor, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.rule_outlined),
              activeIcon: Icon(Icons.rule),
              label: 'Rules',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet),
              label: 'Holdings',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'Backtest',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}