import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/marketplace_strategy.dart';
import '../providers/app_provider.dart';
import '../services/marketplace_service.dart';
import '../services/subscription_service.dart';
import '../utils/theme.dart';
import '../main.dart';
import 'paywall_screen.dart';
import 'publish_strategy_screen.dart';
import 'publisher_profile_sheet.dart';

// ──────────────────────────────────────────────────────────────────────────────
// MAIN MARKETPLACE SCREEN
// ──────────────────────────────────────────────────────────────────────────────

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StrategyCategory? _selectedCategory;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MarketplaceService>(context, listen: false).initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _BrowseTab(
                    selectedCategory: _selectedCategory,
                    searchQuery: _searchQuery,
                    onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
                  ),
                  const _SubscribedTab(),
                  const _CreatorTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Marketplace',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                SizedBox(height: 2),
                Text('ASX strategies by Australian traders',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
              ],
            ),
          ),
          Consumer<SubscriptionService>(
            builder: (context, subscription, _) {
              return GestureDetector(
                onTap: () {
                  if (!subscription.isPro) {
                    PaywallScreen.show(context);
                  } else {
                    PublishStrategyScreen.show(context);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.upload_outlined, size: 15, color: Colors.black),
                      SizedBox(width: 6),
                      Text('Publish', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.all(3),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(8)),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AppTheme.accentColor,
        unselectedLabelColor: AppTheme.textSecondaryColor,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Browse', height: 34),
          Tab(text: 'Subscribed', height: 34),
          Tab(text: 'My Strategies', height: 34),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// BROWSE TAB
// ──────────────────────────────────────────────────────────────────────────────

class _BrowseTab extends StatelessWidget {
  final StrategyCategory? selectedCategory;
  final String searchQuery;
  final ValueChanged<StrategyCategory?> onCategoryChanged;

  const _BrowseTab({
    required this.selectedCategory,
    required this.searchQuery,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketplaceService>(
      builder: (context, marketplace, _) {
        final featured = marketplace.featuredStrategies;
        final trending = marketplace.trendingStrategies;

        List<MarketplaceStrategy> filtered = selectedCategory != null
            ? marketplace.byCategory(selectedCategory!)
            : trending;

        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
          children: [
            // Category filter
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _categoryChip(context, null, 'All', selectedCategory == null, onCategoryChanged),
                  const SizedBox(width: 8),
                  ...StrategyCategory.values.map((cat) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _categoryChip(context, cat, '${cat.emoji} ${cat.label}', selectedCategory == cat, onCategoryChanged),
                  )),
                ],
              ),
            ),

            if (selectedCategory == null && featured.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Icon(Icons.star, size: 14, color: AppTheme.accentColor),
                  SizedBox(width: 6),
                  Text('Featured', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: featured.length,
                  itemBuilder: (_, i) => Padding(
                    padding: EdgeInsets.only(right: i < featured.length - 1 ? 12 : 0),
                    child: FeaturedStrategyCard(strategy: featured[i]),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    selectedCategory != null ? selectedCategory!.label : 'Trending',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text('${filtered.length} strategies',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textTertiaryColor)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ...filtered.map((s) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: StrategyCard(
                strategy: s,
                onTap: () => StrategyDetailSheet.show(context, s),
              ),
            )),
          ],
        );
      },
    );
  }

  Widget _categoryChip(
    BuildContext context,
    StrategyCategory? cat,
    String label,
    bool selected,
    ValueChanged<StrategyCategory?> onChange,
  ) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChange(cat);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accentColor.withValues(alpha: 0.15) : AppTheme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.accentColor.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppTheme.accentColor : AppTheme.textSecondaryColor,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// SUBSCRIBED TAB
// ──────────────────────────────────────────────────────────────────────────────

class _SubscribedTab extends StatelessWidget {
  const _SubscribedTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketplaceService>(
      builder: (context, marketplace, _) {
        final subscribed = marketplace.subscribedStrategies;
        if (subscribed.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bookmarks_outlined, size: 48, color: AppTheme.textTertiaryColor),
                  SizedBox(height: 16),
                  Text('No subscriptions yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Text(
                    'Subscribe to strategies and they\'ll appear here. Your scanner will run them automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor, height: 1.5),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${subscribed.length}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Rules are active in your scanner.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => MainScreen.mainKey.currentState?.navigateToScan(segment: 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.radar, size: 14, color: Colors.black),
                      SizedBox(width: 5),
                      Text('Run Scan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black)),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            ...subscribed.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StrategyCard(
                strategy: s,
                onTap: () => StrategyDetailSheet.show(context, s),
                showUnsubscribeButton: true,
              ),
            )),
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// CREATOR TAB
// ──────────────────────────────────────────────────────────────────────────────

class _CreatorTab extends StatelessWidget {
  const _CreatorTab();

  @override
  Widget build(BuildContext context) {
    return Consumer2<MarketplaceService, SubscriptionService>(
      builder: (context, marketplace, subscription, _) {
        if (!subscription.isPro) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 40),
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.rocket_launch_outlined, size: 32, color: AppTheme.accentColor),
                ),
                const SizedBox(height: 20),
                const Text('Become a Creator', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text(
                  'Pro subscribers can publish strategies and earn 70% of subscription revenue from every person who follows their work.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondaryColor, height: 1.6),
                ),
                const SizedBox(height: 24),
                _buildCreatorFeatureRow(Icons.people_outline, '1,842 avg subscribers for top creators'),
                _buildCreatorFeatureRow(Icons.monetization_on_outlined, 'Top creators earn \$5,000+/mo'),
                _buildCreatorFeatureRow(Icons.verified_outlined, 'Verified badge builds credibility'),
                _buildCreatorFeatureRow(Icons.analytics_outlined, 'Full analytics on subscriber growth'),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => PaywallScreen.show(context),
                    child: const Text('Upgrade to Pro'),
                  ),
                ),
              ],
            ),
          );
        }

        final stats = marketplace.revenueStats;
        final published = marketplace.publishedStrategies;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            // Revenue card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accentColor.withValues(alpha: 0.15),
                    AppTheme.accentColor.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.monetization_on, size: 16, color: AppTheme.accentColor),
                    SizedBox(width: 8),
                    Text('Creator Revenue', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _statMini('MRR', '\$${(stats['creatorMrr'] as double).toStringAsFixed(0)}')),
                    Expanded(child: _statMini('Subscribers', '${stats['totalSubscribers']}')),
                    Expanded(child: _statMini('Published', '${stats['publishedCount']}')),
                  ]),
                  if (stats['publishedCount'] == 0) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Publish your first strategy to start earning.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('My Published Strategies', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                GestureDetector(
                  onTap: () => PublishStrategyScreen.show(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add, size: 14, color: Colors.black),
                      SizedBox(width: 4),
                      Text('New', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black)),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (published.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dividerColor, width: 1, style: BorderStyle.solid),
                ),
                child: Column(children: [
                  const Icon(Icons.add_circle_outline, size: 36, color: AppTheme.textTertiaryColor),
                  const SizedBox(height: 12),
                  const Text('No strategies published yet',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text(
                    'Create a strategy from your scan rules and start building your audience.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => PublishStrategyScreen.show(context),
                    child: const Text('Publish Your First Strategy'),
                  ),
                ]),
              )
            else
              ...published.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PublishedStrategyCard(strategy: s),
              )),
          ],
        );
      },
    );
  }

  static Widget _buildCreatorFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 16, color: AppTheme.accentColor),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
      ]),
    );
  }

  Widget _statMini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondaryColor)),
      ],
    );
  }
}

class _PublishedStrategyCard extends StatelessWidget {
  final MarketplaceStrategy strategy;

  const _PublishedStrategyCard({required this.strategy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(strategy.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(strategy.priceLabel, style: const TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            _badge(Icons.people_outline, '${strategy.subscriberLabel} subscribers', AppTheme.textSecondaryColor),
            const SizedBox(width: 12),
            if (strategy.ratingCount > 0)
              _badge(Icons.star, '${strategy.averageRating.toStringAsFixed(1)} (${strategy.ratingCount})', AppTheme.warningColor),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.pending_outlined, size: 13, color: AppTheme.successColor),
              const SizedBox(width: 6),
              const Text('Under review (24–48 hrs)', style: TextStyle(fontSize: 11, color: AppTheme.successColor)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// REUSABLE STRATEGY CARDS
// ──────────────────────────────────────────────────────────────────────────────

class FeaturedStrategyCard extends StatelessWidget {
  final MarketplaceStrategy strategy;

  const FeaturedStrategyCard({super.key, required this.strategy});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => StrategyDetailSheet.show(context, strategy),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.cardColor,
              AppTheme.accentColor.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('Featured', style: TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              Text(strategy.priceLabel,
                  style: const TextStyle(fontSize: 13, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
            ]),

            const SizedBox(height: 12),

            Text(strategy.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.3),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(strategy.description,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor, height: 1.4),
                maxLines: 2, overflow: TextOverflow.ellipsis),

            const Spacer(),

            Row(children: [
              _avatar(strategy.publisherAvatarInitials ?? '?'),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(strategy.publisherName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    if (strategy.isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 11, color: AppTheme.accentColor),
                    ],
                  ]),
                  Text('${strategy.subscriberLabel} subscribers',
                      style: const TextStyle(fontSize: 10, color: AppTheme.textTertiaryColor)),
                ]),
              ),
              if (strategy.averageRating > 0)
                Row(children: [
                  const Icon(Icons.star, size: 12, color: AppTheme.warningColor),
                  const SizedBox(width: 2),
                  Text(strategy.averageRating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String initials) {
    return Container(
      width: 28, height: 28,
      decoration: const BoxDecoration(
        color: AppTheme.accentColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
      ),
    );
  }
}

class StrategyCard extends StatelessWidget {
  final MarketplaceStrategy strategy;
  final VoidCallback onTap;
  final bool showUnsubscribeButton;

  const StrategyCard({
    super.key,
    required this.strategy,
    required this.onTap,
    this.showUnsubscribeButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketplaceService>(
      builder: (context, marketplace, _) {
        final isSubscribed = marketplace.isSubscribed(strategy.id);
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: isSubscribed
                  ? Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(strategy.category.emoji, style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(strategy.title,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Text(strategy.description,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor, height: 1.4),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: strategy.isFree
                                ? AppTheme.successColor.withValues(alpha: 0.12)
                                : AppTheme.accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            strategy.priceLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: strategy.isFree ? AppTheme.successColor : AppTheme.accentColor,
                            ),
                          ),
                        ),
                        if (isSubscribed) ...[
                          const SizedBox(height: 4),
                          const Row(children: [
                            Icon(Icons.check_circle, size: 13, color: AppTheme.accentColor),
                            SizedBox(width: 3),
                            Text('Subscribed', style: TextStyle(fontSize: 10, color: AppTheme.accentColor)),
                          ]),
                        ],
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Backtest stats
                if (strategy.backtestSummary != null)
                  Row(children: [
                    _backtestChip('${strategy.backtestSummary!['winRate']}%', 'Win'),
                    const SizedBox(width: 8),
                    _backtestChip('+${strategy.backtestSummary!['avgReturn']}%', 'Avg'),
                    const SizedBox(width: 8),
                    _backtestChip('${strategy.backtestSummary!['avgHoldDays']}d', 'Hold'),
                  ]),

                const SizedBox(height: 10),

                Row(children: [
                  GestureDetector(
                    onTap: () {
                      final profile = mockPublisherProfiles[strategy.publisherId];
                      if (profile != null) {
                        PublisherProfileSheet.show(context, profile);
                      }
                    },
                    child: Row(children: [
                      Container(
                        width: 20, height: 20,
                        decoration: const BoxDecoration(color: AppTheme.accentColor, shape: BoxShape.circle),
                        child: Center(
                          child: Text(strategy.publisherAvatarInitials ?? '?',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(strategy.publisherHandle,
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                      if (strategy.isVerified) ...[
                        const SizedBox(width: 3),
                        const Icon(Icons.verified, size: 11, color: AppTheme.accentColor),
                      ],
                    ]),
                  ),
                  const Spacer(),
                  Row(children: [
                    const Icon(Icons.people_outline, size: 12, color: AppTheme.textTertiaryColor),
                    const SizedBox(width: 4),
                    Text(strategy.subscriberLabel, style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                  ]),
                  if (strategy.ratingCount > 0) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.star, size: 12, color: AppTheme.warningColor),
                    const SizedBox(width: 3),
                    Text(strategy.averageRating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                  ],
                ]),

                if (showUnsubscribeButton && isSubscribed) ...[
                  const SizedBox(height: 12),
                  // Star rating row
                  _StarRatingRow(strategy: strategy, marketplace: marketplace),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _confirmUnsubscribe(context, marketplace),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cancel_outlined, size: 14, color: AppTheme.errorColor),
                          SizedBox(width: 6),
                          Text('Unsubscribe', style: TextStyle(fontSize: 12, color: AppTheme.errorColor)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmUnsubscribe(BuildContext context, MarketplaceService marketplace) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Unsubscribe from ${strategy.title}?'),
        content: const Text('This strategy\'s rules will stop running during scans.',
            style: TextStyle(color: AppTheme.textSecondaryColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await marketplace.unsubscribe(strategy.id);
              // Remove the strategy's rules from the scanner
              if (!context.mounted) return;
              final provider = Provider.of<AppProvider>(context, listen: false);
              for (final rule in strategy.rules) {
                await provider.deleteRule(rule.id);
              }
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('Unsubscribe', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  Widget _backtestChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(6)),
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(fontSize: 9, color: AppTheme.textTertiaryColor)),
      ]),
    );
  }
}


// ──────────────────────────────────────────────────────────────────────────────
// STAR RATING ROW  (shown in subscribed cards only)
// ──────────────────────────────────────────────────────────────────────────────

class _StarRatingRow extends StatelessWidget {
  final MarketplaceStrategy strategy;
  final MarketplaceService marketplace;

  const _StarRatingRow({required this.strategy, required this.marketplace});

  @override
  Widget build(BuildContext context) {
    final userRating = marketplace.userRatingFor(strategy.id);
    return Row(children: [
      const Text('Rate:', style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
      const SizedBox(width: 6),
      ...List.generate(5, (i) {
        final starValue = (i + 1).toDouble();
        final filled = userRating != null && starValue <= userRating;
        return GestureDetector(
          onTap: () async {
            HapticFeedback.selectionClick();
            await marketplace.rateStrategy(strategy.id, starValue);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 20,
              color: filled ? AppTheme.warningColor : AppTheme.textTertiaryColor,
            ),
          ),
        );
      }),
      if (userRating != null) ...[
        const SizedBox(width: 6),
        Text('Your rating', style: const TextStyle(fontSize: 10, color: AppTheme.textTertiaryColor)),
      ],
    ]);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STRATEGY DETAIL SHEET
// ──────────────────────────────────────────────────────────────────────────────

class StrategyDetailSheet extends StatelessWidget {
  final MarketplaceStrategy strategy;

  const StrategyDetailSheet({super.key, required this.strategy});

  static Future<void> show(BuildContext context, MarketplaceStrategy strategy) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StrategyDetailSheet(strategy: strategy),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppTheme.dividerColor, borderRadius: BorderRadius.circular(2)),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(children: [
                    Text(strategy.category.emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(strategy.title,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: strategy.isFree
                            ? AppTheme.successColor.withValues(alpha: 0.12)
                            : AppTheme.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        strategy.priceLabel,
                        style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold,
                          color: strategy.isFree ? AppTheme.successColor : AppTheme.accentColor,
                        ),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // Publisher
                  GestureDetector(
                    onTap: () {
                      final profile = mockPublisherProfiles[strategy.publisherId];
                      if (profile != null) {
                        Navigator.pop(context);
                        PublisherProfileSheet.show(context, profile);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: const BoxDecoration(color: AppTheme.accentColor, shape: BoxShape.circle),
                          child: Center(
                            child: Text(strategy.publisherAvatarInitials ?? '?',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(strategy.publisherName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            if (strategy.isVerified) ...[
                              const SizedBox(width: 5),
                              const Icon(Icons.verified, size: 14, color: AppTheme.accentColor),
                            ],
                          ]),
                          Text(strategy.publisherHandle, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                        ])),
                        const Icon(Icons.chevron_right, size: 16, color: AppTheme.textTertiaryColor),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Stats
                  if (strategy.backtestSummary != null) ...[
                    const Text('Backtest Performance',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
                    const SizedBox(height: 10),
                    Row(children: [
                      _statCard('Win Rate', '${strategy.backtestSummary!['winRate']}%', AppTheme.successColor),
                      const SizedBox(width: 8),
                      _statCard('Avg Return', '+${strategy.backtestSummary!['avgReturn']}%', AppTheme.accentColor),
                      const SizedBox(width: 8),
                      _statCard('Max DD', '${strategy.backtestSummary!['maxDrawdown']}%', AppTheme.errorColor),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      _statCard('Sharpe', '${strategy.backtestSummary!['sharpe']}', AppTheme.textSecondaryColor),
                      const SizedBox(width: 8),
                      _statCard('Avg Hold', '${strategy.backtestSummary!['avgHoldDays']}d', AppTheme.textSecondaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.cardColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'General advice only. Past performance ≠ future results.',
                            style: TextStyle(fontSize: 9, color: AppTheme.textTertiaryColor, height: 1.4),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                  ],

                  // Long description
                  const Text('How It Works',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
                  const SizedBox(height: 8),
                  Text(strategy.longDescription,
                      style: const TextStyle(fontSize: 14, color: AppTheme.textSecondaryColor, height: 1.7)),

                  // Rules preview
                  const SizedBox(height: 20),
                  const Text('Conditions Preview',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
                  const SizedBox(height: 8),
                  Consumer<MarketplaceService>(
                    builder: (context, marketplace, _) {
                      final isSubscribed = marketplace.isSubscribed(strategy.id);
                      if (isSubscribed) {
                        // Show full rule details
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: strategy.rules.map((rule) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(10)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(rule.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6, runSpacing: 6,
                                  children: rule.conditions.map((c) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceColor,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(c.description, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                                  )).toList(),
                                ),
                              ],
                            ),
                          )).toList(),
                        );
                      } else {
                        // Blur / tease — show condition types, hide values
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.cardColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.dividerColor),
                          ),
                          child: Column(children: [
                            const Icon(Icons.lock_outline, size: 24, color: AppTheme.textTertiaryColor),
                            const SizedBox(height: 8),
                            const Text('Subscribe to unlock full rule parameters.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6, runSpacing: 6,
                              children: strategy.rules
                                  .expand((r) => r.conditions.map((c) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceColor,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(c.shortDescription,
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                                  )))
                                  .toList(),
                            ),
                          ]),
                        );
                      }
                    },
                  ),

                  // Tags
                  if (strategy.tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: strategy.tags.map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text('#$t', style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
                      )).toList(),
                    ),
                  ],

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),

          // Subscribe button
          Consumer<MarketplaceService>(
            builder: (context, marketplace, _) {
              final isSubscribed = marketplace.isSubscribed(strategy.id);
              return Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceColor,
                  border: Border(top: BorderSide(color: AppTheme.dividerColor)),
                ),
                child: isSubscribed
                    ? Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle, size: 16, color: AppTheme.accentColor),
                            SizedBox(width: 8),
                            Text('Subscribed', style: TextStyle(fontSize: 13, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Run Scan Now'),
                          ),
                        ),
                      ])
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _handleSubscribe(context, marketplace),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          child: Text(
                            strategy.isFree
                                ? 'Subscribe for Free'
                                : 'Subscribe — ${strategy.priceLabel}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubscribe(BuildContext context, MarketplaceService marketplace) async {
    if (strategy.isFree) {
      await marketplace.subscribe(strategy.id);
      HapticFeedback.mediumImpact();
      // Inject the strategy's rules into the scan engine
      if (!context.mounted) return;
      final provider = Provider.of<AppProvider>(context, listen: false);
      for (final rule in strategy.rules) {
        await provider.saveCustomRule(rule.copyWith(isCommunityRule: true, isActive: true));
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscribed to ${strategy.title} — rules added to scanner'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Show payment flow — in production: in-app purchase / Stripe
      _showPaymentSheet(context, marketplace);
    }
  }

  void _showPaymentSheet(BuildContext context, MarketplaceService marketplace) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Text(strategy.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('${strategy.priceLabel} • Cancel anytime',
                style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  // In production: trigger in-app purchase here
                  await marketplace.subscribe(strategy.id);
                  if (!context.mounted) return;
                  final provider = Provider.of<AppProvider>(context, listen: false);
                  for (final rule in strategy.rules) {
                    await provider.saveCustomRule(rule.copyWith(isCommunityRule: true, isActive: true));
                  }
                  HapticFeedback.mediumImpact();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Subscribed to ${strategy.title} — rules added to scanner'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('Subscribe for ${strategy.priceLabel}'),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Payment processed via Apple / Google Pay. ASX Radar is a screening tool, not financial advice.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textTertiaryColor)),
        ]),
      ),
    );
  }
}