import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/marketplace_strategy.dart';
import '../models/scan_rule.dart';
import '../providers/app_provider.dart';
import '../services/marketplace_service.dart';
import '../utils/theme.dart';

class PublishStrategyScreen extends StatefulWidget {
  const PublishStrategyScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.push(context, MaterialPageRoute(builder: (_) => const PublishStrategyScreen()));
  }

  @override
  State<PublishStrategyScreen> createState() => _PublishStrategyScreenState();
}

class _PublishStrategyScreenState extends State<PublishStrategyScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _longDescController = TextEditingController();
  final _tagsController = TextEditingController();
  final _handleController = TextEditingController();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController(text: '4.99');

  StrategyCategory _category = StrategyCategory.momentum;
  PricingModel _pricing = PricingModel.free;
  final List<ScanRule> _selectedRules = [];
  bool _isSubmitting = false;
  int _step = 0; // 0=details, 1=rules, 2=pricing, 3=review

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _longDescController.dispose();
    _tagsController.dispose();
    _handleController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _step0Valid =>
      _titleController.text.trim().length >= 5 &&
      _descriptionController.text.trim().length >= 20 &&
      _nameController.text.trim().isNotEmpty &&
      _handleController.text.trim().isNotEmpty;

  bool get _step1Valid => _selectedRules.isNotEmpty;

  void _nextStep() {
    if (_step == 0 && !_step0Valid) {
      _showError('Please fill in all required fields (min 5 chars for title, 20 for description).');
      return;
    }
    if (_step == 1 && !_step1Valid) {
      _showError('Select at least one rule to include in your strategy.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _step++);
  }

  void _prevStep() {
    HapticFeedback.selectionClick();
    setState(() => _step--);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.errorColor),
    );
  }

  Future<void> _publish() async {
    setState(() => _isSubmitting = true);
    try {
      final marketplace = Provider.of<MarketplaceService>(context, listen: false);
      final tags = _tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      final price = _pricing == PricingModel.subscription ? double.tryParse(_priceController.text) : null;

      final strategy = await marketplace.publishStrategy(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        longDescription: _longDescController.text.trim(),
        rules: _selectedRules,
        category: _category,
        pricing: _pricing,
        monthlyPrice: price,
        tags: tags,
        publisherName: _nameController.text.trim(),
        publisherHandle: _handleController.text.trim().startsWith('@')
            ? _handleController.text.trim()
            : '@${_handleController.text.trim()}',
      );

      if (strategy != null && mounted) {
        HapticFeedback.mediumImpact();
        _showSuccessDialog();
      }
    } catch (e) {
      _showError('Failed to publish. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.rocket_launch, color: AppTheme.accentColor),
          SizedBox(width: 10),
          Text('Strategy Published!'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Your strategy is now live in the marketplace. You\'ll earn 70% of subscription revenue from every subscriber.',
            style: TextStyle(color: AppTheme.textSecondaryColor, height: 1.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.monetization_on, color: AppTheme.accentColor, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Revenue is paid monthly to your nominated account. Minimum payout \$20.',
                  style: TextStyle(fontSize: 12, color: AppTheme.accentColor),
                ),
              ),
            ]),
          ),
        ]),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              foregroundColor: Colors.black,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Publish Strategy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: List.generate(4, (i) {
                final isActive = i == _step;
                final isDone = i < _step;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                    height: 3,
                    decoration: BoxDecoration(
                      color: isDone || isActive ? AppTheme.accentColor : AppTheme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(
                ['Strategy Details', 'Select Rules', 'Pricing', 'Review & Publish'][_step],
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor),
              ),
              Text('Step ${_step + 1} of 4', style: const TextStyle(fontSize: 12, color: AppTheme.textTertiaryColor)),
            ]),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: IndexedStack(
              index: _step,
              children: [
                _buildStep0(), // Details
                _buildStep1(), // Rules
                _buildStep2(), // Pricing
                _buildStep3(), // Review
              ],
            ),
          ),

          // Bottom nav
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceColor,
              border: Border(top: BorderSide(color: AppTheme.dividerColor)),
            ),
            child: Row(children: [
              if (_step > 0)
                OutlinedButton(
                  onPressed: _prevStep,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondaryColor,
                    side: const BorderSide(color: AppTheme.dividerColor),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Back'),
                ),
              if (_step > 0) const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : (_step == 3 ? _publish : _nextStep),
                  child: _isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Text(_step == 3 ? 'Publish Strategy' : 'Continue'),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildStep0() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _fieldLabel('Your Name *'),
        _textField(_nameController, 'e.g. Marcus Chen'),
        const SizedBox(height: 16),
        _fieldLabel('Handle *'),
        _textField(_handleController, 'e.g. @asxtrader'),
        const SizedBox(height: 16),
        _fieldLabel('Strategy Title *'),
        _textField(_titleController, 'e.g. VCP Breakout System'),
        const SizedBox(height: 16),
        _fieldLabel('Short Description *'),
        _textField(_descriptionController, 'One-sentence pitch. What does this catch and why?', maxLines: 2),
        const SizedBox(height: 16),
        _fieldLabel('Detailed Description'),
        _textField(_longDescController, 'Explain the logic, the edge, and how to use it. Subscribers will see this before paying.', maxLines: 5),
        const SizedBox(height: 16),
        _fieldLabel('Category'),
        _buildCategoryPicker(),
        const SizedBox(height: 16),
        _fieldLabel('Tags (comma-separated)'),
        _textField(_tagsController, 'e.g. momentum, ASX200, director'),
      ]),
    );
  }

  Widget _buildStep1() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final allRules = provider.rules;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(children: [
            Icon(Icons.lock_outline, size: 15, color: AppTheme.accentColor),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Rules are only revealed to subscribers. They see condition types and descriptions — not parameter values.',
                style: TextStyle(fontSize: 12, color: AppTheme.accentColor, height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (allRules.isEmpty)
          const Center(child: Text('No rules yet. Create rules first under the Scan tab.', style: TextStyle(color: AppTheme.textSecondaryColor)))
        else
          ...allRules.map((rule) {
            final selected = _selectedRules.any((r) => r.id == rule.id);
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (selected) {
                    _selectedRules.removeWhere((r) => r.id == rule.id);
                  } else {
                    _selectedRules.add(rule);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.accentColor.withValues(alpha: 0.1) : AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppTheme.accentColor.withValues(alpha: 0.4) : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.accentColor : AppTheme.surfaceColor,
                      shape: BoxShape.circle,
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 14, color: Colors.black)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(rule.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      rule.conditions.map((c) => c.shortDescription).join(' · '),
                      style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor),
                    ),
                  ])),
                ]),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Choose how to monetize your strategy.',
          style: TextStyle(color: AppTheme.textSecondaryColor, height: 1.5),
        ),
        const SizedBox(height: 20),

        _buildPricingOption(
          title: 'Free',
          subtitle: 'Anyone can subscribe at no cost. Great for building an audience.',
          icon: Icons.people_outline,
          value: PricingModel.free,
        ),
        const SizedBox(height: 12),
        _buildPricingOption(
          title: 'Paid Subscription',
          subtitle: 'Charge a monthly fee. You receive 70% of revenue.',
          icon: Icons.monetization_on_outlined,
          value: PricingModel.subscription,
        ),

        if (_pricing == PricingModel.subscription) ...[
          const SizedBox(height: 16),
          _fieldLabel('Monthly Price (AUD)'),
          _textField(_priceController, '4.99', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Revenue Example', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
              const SizedBox(height: 8),
              _revenueRow('100 subscribers', '\$${_monthlyCreatorRevenue(100)}'),
              _revenueRow('500 subscribers', '\$${_monthlyCreatorRevenue(500)}'),
              _revenueRow('1,000 subscribers', '\$${_monthlyCreatorRevenue(1000)}'),
              const SizedBox(height: 8),
              const Text('70% revenue share, paid monthly', style: TextStyle(fontSize: 10, color: AppTheme.textTertiaryColor)),
            ]),
          ),
        ],

        const SizedBox(height: 24),
        const Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 16),

        const Text('Creator Terms', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
        const SizedBox(height: 8),
        const Text(
          '• Strategies are manually reviewed before going live (24–48 hours).\n'
          '• Published rules must relate to ASX-listed securities.\n'
          '• You are responsible for the accuracy of any performance claims.\n'
          '• ASX Radar is not a financial services licensee. Your strategy is a screening tool, not financial advice.\n'
          '• Creator payouts require a valid ABN or tax file number.',
          style: TextStyle(fontSize: 12, color: AppTheme.textTertiaryColor, height: 1.7),
        ),
      ]),
    );
  }

  Widget _buildStep3() {
    final price = double.tryParse(_priceController.text) ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  _titleController.text.trim().isEmpty ? 'Untitled Strategy' : _titleController.text.trim(),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _pricing == PricingModel.free ? 'Free' : '\$${price.toStringAsFixed(2)}/mo',
                  style: const TextStyle(fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              _descriptionController.text.trim().isEmpty ? '—' : _descriptionController.text.trim(),
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor, height: 1.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _tag('${_category.emoji} ${_category.label}'),
                ..._tagsController.text
                    .split(',')
                    .map((t) => t.trim())
                    .where((t) => t.isNotEmpty)
                    .map((t) => _tag(t)),
              ],
            ),
            if (_selectedRules.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 8),
              Text(
                '${_selectedRules.length} rule${_selectedRules.length != 1 ? 's' : ''} included',
                style: const TextStyle(fontSize: 12, color: AppTheme.textTertiaryColor),
              ),
              const SizedBox(height: 4),
              ..._selectedRules.map((r) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const Icon(Icons.rule, size: 14, color: AppTheme.accentColor),
                  const SizedBox(width: 8),
                  Text(r.name, style: const TextStyle(fontSize: 13)),
                ]),
              )),
            ],
          ]),
        ),

        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.successColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.2)),
          ),
          child: const Row(children: [
            Icon(Icons.check_circle_outline, color: AppTheme.successColor, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your strategy will be reviewed within 24–48 hours before going live in the marketplace.',
                style: TextStyle(fontSize: 13, color: AppTheme.successColor, height: 1.4),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
    );
  }

  Widget _textField(TextEditingController controller, String hint, {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textTertiaryColor),
        filled: true,
        fillColor: AppTheme.cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.accentColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildCategoryPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: StrategyCategory.values.map((cat) {
        final selected = _category == cat;
        return GestureDetector(
          onTap: () => setState(() => _category = cat),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppTheme.accentColor.withValues(alpha: 0.15) : AppTheme.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppTheme.accentColor.withValues(alpha: 0.5) : Colors.transparent,
              ),
            ),
            child: Text(
              '${cat.emoji} ${cat.label}',
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppTheme.accentColor : AppTheme.textSecondaryColor,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPricingOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required PricingModel value,
  }) {
    final selected = _pricing == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _pricing = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accentColor.withValues(alpha: 0.08) : AppTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.accentColor.withValues(alpha: 0.5) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: selected ? AppTheme.accentColor.withValues(alpha: 0.15) : AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: selected ? AppTheme.accentColor : AppTheme.textSecondaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? AppTheme.accentColor : AppTheme.textPrimaryColor)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor, height: 1.4)),
          ])),
          if (selected)
            const Icon(Icons.check_circle, size: 20, color: AppTheme.accentColor),
        ]),
      ),
    );
  }

  Widget _revenueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  String _monthlyCreatorRevenue(int subscribers) {
    final price = double.tryParse(_priceController.text) ?? 0;
    return (price * subscribers * 0.70).toStringAsFixed(0);
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
    );
  }
}
