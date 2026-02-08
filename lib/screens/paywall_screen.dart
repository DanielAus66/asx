import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/subscription_service.dart';
import '../utils/theme.dart';

/// Paywall screen shown when user tries to access pro features
class PaywallScreen extends StatefulWidget {
  final String? featureTitle;
  final String? featureDescription;
  final ProFeature? feature;

  const PaywallScreen({
    super.key,
    this.featureTitle,
    this.featureDescription,
    this.feature,
  });

  /// Show paywall as a modal bottom sheet
  static Future<bool?> show(
    BuildContext context, {
    String? featureTitle,
    String? featureDescription,
    ProFeature? feature,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaywallScreen(
        featureTitle: featureTitle,
        featureDescription: featureDescription,
        feature: feature,
      ),
    );
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isYearly = true;
  bool _isLoading = false;
  SubscriptionTier _selectedTier = SubscriptionTier.pro;

  String get _title {
    if (widget.featureTitle != null) return widget.featureTitle!;
    switch (widget.feature) {
      case ProFeature.fullAsxScan:
        return 'Full ASX Scan';
      case ProFeature.unlimitedRules:
      case ProFeature.customRules:
        return 'Unlock All Rules';
      case ProFeature.unlimitedWatchlist:
        return 'Unlimited Watchlist';
      case ProFeature.unlimitedBacktests:
        return 'Unlimited Backtesting';
      default:
        return 'Upgrade to Pro';
    }
  }

  String get _description {
    if (widget.featureDescription != null) return widget.featureDescription!;
    switch (widget.feature) {
      case ProFeature.fullAsxScan:
        return 'Scan all 17,000+ ASX symbols to find hidden opportunities';
      case ProFeature.unlimitedRules:
        return 'Access all pre-built rules and create your own custom rules';
      case ProFeature.customRules:
        return 'Create unlimited custom scan rules tailored to your strategy';
      case ProFeature.unlimitedWatchlist:
        return 'Track unlimited stocks in your watchlist';
      case ProFeature.unlimitedBacktests:
        return 'Run unlimited backtests to validate your strategies';
      default:
        return 'Get full access to all ASX Radar features';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textTertiaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    // Close button
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ),
                    
                    // Pro badge
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFF9500)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, color: Colors.black, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'PRO',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Title
                    Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Description
                    Text(
                      _description,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Billing toggle
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isYearly = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: !_isYearly ? AppTheme.accentColor : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Monthly',
                                  style: TextStyle(
                                    color: !_isYearly ? Colors.black : AppTheme.textSecondaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isYearly = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _isYearly ? AppTheme.accentColor : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Yearly',
                                      style: TextStyle(
                                        color: _isYearly ? Colors.black : AppTheme.textSecondaryColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (_isYearly) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'SAVE 48%',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Plan cards
                    _buildPlanCard(
                      SubscriptionService.plans[1], // Pro
                      isSelected: _selectedTier == SubscriptionTier.pro,
                      onTap: () => setState(() => _selectedTier = SubscriptionTier.pro),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    _buildPlanCard(
                      SubscriptionService.plans[2], // Pro+
                      isSelected: _selectedTier == SubscriptionTier.proPlus,
                      onTap: () => setState(() => _selectedTier = SubscriptionTier.proPlus),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Subscribe button
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _subscribe,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Text(
                                _getButtonText(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Restore purchases
                    TextButton(
                      onPressed: _restorePurchases,
                      child: const Text(
                        'Restore Purchases',
                        style: TextStyle(color: AppTheme.textSecondaryColor),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Terms
                    Text(
                      'Cancel anytime. ${_isYearly ? 'Billed annually' : 'Billed monthly'}. '
                      'Subscription auto-renews unless cancelled at least 24 hours before the end of the current period.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan, {required bool isSelected, required VoidCallback onTap}) {
    final price = _isYearly ? plan.yearlyPrice : plan.monthlyPrice;
    final period = _isYearly ? '/year' : '/month';
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Radio
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppTheme.accentColor : AppTheme.textTertiaryColor,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.accentColor,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                
                // Plan name
                Text(
                  plan.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                // Badge
                if (plan.badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      plan.badge!,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
                
                const Spacer(),
                
                // Price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      SubscriptionService.formatPrice(price),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      period,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTertiaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            if (isSelected) ...[
              const SizedBox(height: 16),
              const Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 12),
              
              // Features list
              ...plan.features.map((feature) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppTheme.successColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feature,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  String _getButtonText() {
    final plan = _selectedTier == SubscriptionTier.pro
        ? SubscriptionService.plans[1]
        : SubscriptionService.plans[2];
    final price = _isYearly ? plan.yearlyPrice : plan.monthlyPrice;
    return 'Start ${plan.name} - ${SubscriptionService.formatPrice(price)}${_isYearly ? '/yr' : '/mo'}';
  }

  Future<void> _subscribe() async {
    setState(() => _isLoading = true);
    
    final subscription = Provider.of<SubscriptionService>(context, listen: false);
    final success = await subscription.upgradeTo(_selectedTier, yearly: _isYearly);
    
    setState(() => _isLoading = false);
    
    if (success && mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome to ${_selectedTier == SubscriptionTier.pro ? 'Pro' : 'Pro+'}! 🎉'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    }
  }

  Future<void> _restorePurchases() async {
    final subscription = Provider.of<SubscriptionService>(context, listen: false);
    final restored = await subscription.restorePurchases();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(restored ? 'Purchases restored!' : 'No purchases to restore'),
          backgroundColor: restored ? AppTheme.successColor : AppTheme.textSecondaryColor,
        ),
      );
      
      if (restored) {
        Navigator.pop(context, true);
      }
    }
  }
}
