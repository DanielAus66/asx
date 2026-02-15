import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'services/subscription_service.dart';
import 'services/error_reporting_service.dart';
import 'services/storage_service.dart';
import 'screens/home_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/more_screen.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErrorReportingService.initialize();
  await StorageService.initialize();
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
        home: MainScreen(key: MainScreen.mainKey),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  static final GlobalKey<MainScreenState> mainKey = GlobalKey<MainScreenState>();
  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final Set<int> _visitedTabs = {0};

  /// Switch to a specific tab (0=Home, 1=Scan, 2=More)
  void switchToTab(int index) {
    if (index >= 0 && index < 3) {
      setState(() { _currentIndex = index; _visitedTabs.add(index); });
    }
  }

  /// Navigate to Scan tab, optionally jumping to a specific segment
  /// segment: 0=Scanner, 1=My Rules, 2=Backtest
  void navigateToScan({int segment = 0}) {
    setState(() { _currentIndex = 1; _visitedTabs.add(1); });
    if (segment > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScanScreen.scanKey.currentState?.jumpToSegment(segment);
      });
    }
  }

  // Backward-compat aliases used by other screens
  void navigateToStrategies({String? category}) => navigateToScan(segment: 1);
  void navigateToRules() => navigateToScan(segment: 1);
  void navigateToRadar() => navigateToScan(segment: 0);
  void navigateToBacktest() => navigateToScan(segment: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppProvider>(context, listen: false).initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Provider.of<AppProvider>(context, listen: false).refreshWatchlistPrices();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomeScreen(),
          _visitedTabs.contains(1)
              ? ScanScreen(key: ScanScreen.scanKey)
              : const SizedBox(),
          _visitedTabs.contains(2) ? const MoreScreen() : const SizedBox(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.dividerColor, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() { _currentIndex = index; _visitedTabs.add(index); }),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.radar_outlined),
              activeIcon: Icon(Icons.radar),
              label: 'Scan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.more_horiz),
              activeIcon: Icon(Icons.more_horiz),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
