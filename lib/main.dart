import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'services/subscription_service.dart';
import 'services/marketplace_service.dart';
import 'services/user_profile_service.dart';
import 'services/scan_scheduler_service.dart';
import 'services/notification_service.dart';
import 'services/error_reporting_service.dart';
import 'services/storage_service.dart';
import 'screens/home_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/marketplace_screen.dart';
import 'screens/more_screen.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErrorReportingService.initialize();
  await StorageService.initialize();
  await NotificationService.initialize(); // must init before any background task runs
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
        ChangeNotifierProvider(create: (_) => MarketplaceService()..initialize()),
        ChangeNotifierProvider(create: (_) => UserProfileService()..initialize()),
        ChangeNotifierProvider(create: (_) => ScanSchedulerService()..initialize()),
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
  late PageController _pageController;
  int _currentIndex = 0;
  bool _disclaimerShown = false;

  /// Switch to a specific tab (0=Home, 1=Scan, 2=Marketplace, 3=More)
  void switchToTab(int index) {
    if (index >= 0 && index < 4) {
      _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  /// Navigate to Scan tab, optionally jumping to a specific segment
  /// segment: 0=Scanner, 1=Rules
  void navigateToScan({int segment = 0}) {
    _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
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
  void navigateToBacktest() => navigateToScan(segment: 0);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      provider.initialize();
      // Show disclaimer after init
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_disclaimerShown) {
          _disclaimerShown = true;
          _maybeShowDisclaimer();
        }
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Provider.of<AppProvider>(context, listen: false).refreshWatchlistPrices();
    }
  }

  void _maybeShowDisclaimer() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.disclaimerAccepted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.gavel, color: AppTheme.accentColor, size: 22),
            SizedBox(width: 10),
            Expanded(child: Text('Important Disclaimer', style: TextStyle(fontSize: 17))),
          ]),
          content: const SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('General Advice Warning', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.accentColor)),
              SizedBox(height: 8),
              Text(
                'The information provided by ASX Radar is general in nature and does not take into account your personal objectives, financial situation or needs.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'ASX Radar is a stock screening tool for educational and informational purposes only. It does not constitute financial product advice, a recommendation, or an offer to buy or sell any securities.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'Before making any investment decision, you should consider seeking independent financial advice tailored to your personal circumstances from a licensed financial adviser.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'Past performance is not indicative of future results. All investments carry risk, including the potential loss of principal.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor, height: 1.5),
              ),
            ]),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  provider.acceptDisclaimer();
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('I Understand & Accept', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        children: [
          const HomeScreen(),
          ScanScreen(key: ScanScreen.scanKey),
          const MarketplaceScreen(),
          const MoreScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.dividerColor, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
          },
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.radar_outlined), activeIcon: Icon(Icons.radar), label: 'Scan'),
            BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), activeIcon: Icon(Icons.storefront), label: 'Marketplace'),
            BottomNavigationBarItem(icon: Icon(Icons.more_horiz), activeIcon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      ),
    );
  }
}
