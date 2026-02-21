import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan_rule.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';

class CreateRuleScreen extends StatefulWidget {
  final ScanRule? editRule; // If editing existing rule
  const CreateRuleScreen({super.key, this.editRule});

  @override
  State<CreateRuleScreen> createState() => _CreateRuleScreenState();
}

class _CreateRuleScreenState extends State<CreateRuleScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<RuleCondition> _conditions = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.editRule != null) {
      _nameController.text = widget.editRule!.name;
      _descriptionController.text = widget.editRule!.description;
      _conditions.addAll(widget.editRule!.conditions);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        title: Text(widget.editRule != null ? 'Edit Rule' : 'Create Rule'),
        actions: [
          TextButton(
            onPressed: _canSave() ? _saveRule : null,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor))
                : Text('SAVE', style: TextStyle(color: _canSave() ? AppTheme.accentColor : AppTheme.textTertiaryColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Rule Name
          _buildSection('Rule Name', child: TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'e.g., My Bounce Play',
              hintStyle: const TextStyle(color: AppTheme.textTertiaryColor),
              filled: true,
              fillColor: AppTheme.cardColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (_) => setState(() {}),
          )),

          const SizedBox(height: 20),

          // Description
          _buildSection('Description (optional)', child: TextField(
            controller: _descriptionController,
            style: const TextStyle(fontSize: 14),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Describe what this rule looks for...',
              hintStyle: const TextStyle(color: AppTheme.textTertiaryColor),
              filled: true,
              fillColor: AppTheme.cardColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          )),

          const SizedBox(height: 24),

          // Conditions Header
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Conditions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text('All must match (AND)', style: TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
            ],
          ),
          const SizedBox(height: 12),

          // Conditions List
          if (_conditions.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
              child: const Column(
                children: [
                  Icon(Icons.rule, size: 40, color: AppTheme.textTertiaryColor),
                  SizedBox(height: 12),
                  Text('No conditions yet', style: TextStyle(color: AppTheme.textSecondaryColor)),
                  SizedBox(height: 4),
                  Text('Add at least one condition below', style: TextStyle(fontSize: 12, color: AppTheme.textTertiaryColor)),
                ],
              ),
            )
          else
            ..._conditions.asMap().entries.map((entry) => _buildConditionCard(entry.key, entry.value)),

          const SizedBox(height: 16),

          // Add Condition Button
          OutlinedButton.icon(
            onPressed: () => _showAddConditionSheet(),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.accentColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.add, color: AppTheme.accentColor),
            label: const Text('ADD CONDITION', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
          ),

          const SizedBox(height: 32),

          // Preview
          if (_conditions.isNotEmpty) ...[
            const Text('Preview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_nameController.text.isEmpty ? 'Untitled Rule' : _nameController.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  if (_descriptionController.text.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_descriptionController.text, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _conditions.map((c) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                      child: Text(c.description, style: const TextStyle(fontSize: 11, color: AppTheme.accentColor)),
                    )).toList(),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection(String title, {required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildConditionCard(int index, RuleCondition condition) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AppTheme.accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text('${index + 1}', style: const TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_getConditionTypeName(condition.type), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(condition.description, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18, color: AppTheme.textSecondaryColor),
            onPressed: () => _showEditConditionSheet(index, condition),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
            onPressed: () => setState(() => _conditions.removeAt(index)),
          ),
        ],
      ),
    );
  }

  String _getConditionTypeName(RuleConditionType type) {
    switch (type) {
      case RuleConditionType.rsiBelow: return 'RSI Below';
      case RuleConditionType.rsiAbove: return 'RSI Above';
      case RuleConditionType.priceAboveSma: return 'Price Above SMA';
      case RuleConditionType.priceBelowSma: return 'Price Below SMA';
      case RuleConditionType.priceAboveEma: return 'Price Above EMA';
      case RuleConditionType.priceBelowEma: return 'Price Below EMA';
      case RuleConditionType.macdCrossover: return 'MACD Crossover';
      case RuleConditionType.macdCrossunder: return 'MACD Crossunder';
      case RuleConditionType.volumeSpike: return 'Volume Spike';
      case RuleConditionType.priceNear52WeekLow: return 'Near 52-Week Low';
      case RuleConditionType.priceNear52WeekHigh: return 'Near 52-Week High';
      case RuleConditionType.bollingerBreakout: return 'Bollinger Breakout';
      case RuleConditionType.priceChangeAbove: return 'Price Change Above';
      case RuleConditionType.priceChangeBelow: return 'Price Change Below';
      case RuleConditionType.momentum6Month: return '6-Month Momentum';
      case RuleConditionType.momentum12Month: return '12-Month Momentum';
      case RuleConditionType.nearAllTimeHigh: return 'Near 52-Week HIGH';
      case RuleConditionType.breakoutNDayHigh: return 'N-Day Breakout';
      case RuleConditionType.breakoutHeld: return 'Breakout Held';
      case RuleConditionType.vcpSetup: return 'VCP Setup';
      case RuleConditionType.bollingerSqueeze: return 'Bollinger Squeeze';
      case RuleConditionType.stealthAccumulation: return 'Stealth Accumulation';
      case RuleConditionType.obvDivergence: return 'OBV Divergence';
      case RuleConditionType.oversoldBounce: return 'Oversold Bounce';
      case RuleConditionType.earningsSurprise: return 'Earnings Surprise';
      case RuleConditionType.insiderBuying: return 'Insider Buying';
      // Event-based rules
      case RuleConditionType.event52WeekHighCrossover: return '⚡ 52W High Crossover';
      case RuleConditionType.eventVolumeBreakout: return '⚡ Volume Breakout Event';
      case RuleConditionType.eventMomentumCrossover: return '⚡ 6M Momentum Crossover';
      // State filter rules
      case RuleConditionType.stateMomentumPositive: return '📊 6M Momentum Positive';
      case RuleConditionType.stateVolumeExpanding: return '📊 Volume Expanding';
      case RuleConditionType.stateAboveSma50: return '📊 Above SMA50';
      case RuleConditionType.stateUptrend: return '📊 In Uptrend';
      case RuleConditionType.stateNear52WeekHigh: return '📊 Near 52W High';
      // Fundamental conditions (Phase 2)
      case RuleConditionType.announcementWithinDays: return '📄 Announcement Within Days';
      case RuleConditionType.earningsWithinDays: return '📊 Earnings Within Days';
      case RuleConditionType.directorTradeWithinDays: return '👤 Director Trade Within Days';
      case RuleConditionType.capitalRaiseWithinDays: return '💰 Capital Raise Within Days';
      case RuleConditionType.marketSensitiveWithinDays: return '⚡ Price Sensitive Within Days';
      case RuleConditionType.shortInterestAbove: return '🩳 Short Interest Above';
      case RuleConditionType.shortInterestBelow: return '🩳 Short Interest Below';
      case RuleConditionType.shortInterestRising: return '🩳 Short Interest Rising';
      case RuleConditionType.daysToCoverAbove: return '🩳 Days to Cover Above';
      case RuleConditionType.isNotHalted: return '▶️ Not Halted';
      case RuleConditionType.resumedFromHalt: return '⏯️ Resumed From Halt';
    }
  }

  void _showAddConditionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConditionBuilderSheet(
        onSave: (condition) {
          setState(() => _conditions.add(condition));
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showEditConditionSheet(int index, RuleCondition condition) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConditionBuilderSheet(
        initialCondition: condition,
        onSave: (updated) {
          setState(() => _conditions[index] = updated);
          Navigator.pop(context);
        },
      ),
    );
  }

  bool _canSave() {
    return _nameController.text.trim().isNotEmpty && _conditions.isNotEmpty && !_isSaving;
  }

  Future<void> _saveRule() async {
    if (!_canSave()) return;

    setState(() => _isSaving = true);

    final provider = Provider.of<AppProvider>(context, listen: false);
    
    final rule = ScanRule(
      id: widget.editRule?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty 
          ? _conditions.map((c) => c.description).join(' + ')
          : _descriptionController.text.trim(),
      conditions: _conditions,
      isActive: true,
      isCommunityRule: false,
      createdAt: widget.editRule?.createdAt ?? DateTime.now(),
    );

    await provider.saveCustomRule(rule, isNew: widget.editRule == null);

    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.editRule != null ? 'Rule updated!' : 'Rule created!'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONDITION BUILDER SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ConditionBuilderSheet extends StatefulWidget {
  final RuleCondition? initialCondition;
  final Function(RuleCondition) onSave;

  const _ConditionBuilderSheet({this.initialCondition, required this.onSave});

  @override
  State<_ConditionBuilderSheet> createState() => _ConditionBuilderSheetState();
}

class _ConditionBuilderSheetState extends State<_ConditionBuilderSheet> {
  RuleConditionType? _selectedType;
  double _value = 0;
  late TextEditingController _valueController;

  // ── All available conditions grouped by category ──────────────────────────
  static const Map<String, List<RuleConditionType>> _categories = {
    '⚡ Events (Backtest Only)': [
      RuleConditionType.event52WeekHighCrossover,
      RuleConditionType.eventVolumeBreakout,
      RuleConditionType.eventMomentumCrossover,
    ],
    '📊 State Filters': [
      RuleConditionType.stateNear52WeekHigh,
      RuleConditionType.stateMomentumPositive,
      RuleConditionType.stateVolumeExpanding,
      RuleConditionType.stateAboveSma50,
      RuleConditionType.stateUptrend,
    ],
    'RSI': [
      RuleConditionType.rsiBelow,
      RuleConditionType.rsiAbove,
    ],
    'Moving Averages': [
      RuleConditionType.priceAboveSma,
      RuleConditionType.priceBelowSma,
      RuleConditionType.priceAboveEma,
      RuleConditionType.priceBelowEma,
    ],
    'MACD': [
      RuleConditionType.macdCrossover,
      RuleConditionType.macdCrossunder,
    ],
    'Volume': [
      RuleConditionType.volumeSpike,
      RuleConditionType.stealthAccumulation,
      RuleConditionType.obvDivergence,
    ],
    '52-Week Range': [
      RuleConditionType.priceNear52WeekLow,
      RuleConditionType.priceNear52WeekHigh,
      RuleConditionType.nearAllTimeHigh,
    ],
    'Price Change': [
      RuleConditionType.priceChangeAbove,
      RuleConditionType.priceChangeBelow,
      RuleConditionType.oversoldBounce,
    ],
    'Momentum': [
      RuleConditionType.momentum6Month,
      RuleConditionType.momentum12Month,
    ],
    'Breakout': [
      RuleConditionType.breakoutNDayHigh,
      RuleConditionType.breakoutHeld,
    ],
    'Volatility': [
      RuleConditionType.vcpSetup,
      RuleConditionType.bollingerSqueeze,
      RuleConditionType.bollingerBreakout,
    ],
    'Earnings & Insiders': [
      RuleConditionType.earningsSurprise,
      RuleConditionType.insiderBuying,
    ],
    '📄 ASX Announcements': [
      RuleConditionType.announcementWithinDays,
      RuleConditionType.earningsWithinDays,
      RuleConditionType.capitalRaiseWithinDays,
      RuleConditionType.marketSensitiveWithinDays,
    ],
    '👤 Director Activity': [
      RuleConditionType.directorTradeWithinDays,
    ],
    '🩳 Short Interest': [
      RuleConditionType.shortInterestAbove,
      RuleConditionType.shortInterestBelow,
      RuleConditionType.shortInterestRising,
      RuleConditionType.daysToCoverAbove,
    ],
    '▶️ Trading Status': [
      RuleConditionType.isNotHalted,
      RuleConditionType.resumedFromHalt,
    ],
  };

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialCondition?.type;
    _value = widget.initialCondition?.value ?? 0;
    _valueController = TextEditingController(text: _value == 0 ? '' : _formatRaw(_value));
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _selectType(RuleConditionType type) {
    final defaultVal = _getDefaultValue(type);
    setState(() {
      _selectedType = type;
      _value = defaultVal;
      _valueController.text = _needsValue(type) ? _formatRaw(defaultVal) : '';
    });
  }

  void _applyPreset(double v) {
    setState(() {
      _value = v;
      _valueController.text = _formatRaw(v);
    });
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.80,
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
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.textTertiaryColor, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Text(
                      widget.initialCondition != null ? 'Edit Condition' : 'Add Condition',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _canSave() ? _save : null,
                      child: Text('DONE',
                        style: TextStyle(
                          color: _canSave() ? AppTheme.accentColor : AppTheme.textTertiaryColor,
                          fontWeight: FontWeight.w600,
                        )),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Category + type chips
                    const Text('Condition Type',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
                    const SizedBox(height: 10),
                    ..._categories.entries.map((cat) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 6),
                          child: Text(cat.key,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor, letterSpacing: 0.3)),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: cat.value.map((type) {
                            final selected = _selectedType == type;
                            return GestureDetector(
                              onTap: () => _selectType(type),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected ? AppTheme.accentColor : AppTheme.cardColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _getTypeName(type),
                                  style: TextStyle(
                                    color: selected ? Colors.black : AppTheme.textPrimaryColor,
                                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    )),

                    // ── Value input ────────────────────────────────────────
                    if (_selectedType != null && _needsValue(_selectedType!)) ...[
                      const SizedBox(height: 24),
                      const Divider(color: AppTheme.dividerColor),
                      const SizedBox(height: 16),
                      Text(_getValueLabel(_selectedType!),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
                      const SizedBox(height: 10),

                      // Text field for direct entry
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _valueController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppTheme.cardColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              suffixText: _getValueSuffix(_selectedType!),
                              suffixStyle: const TextStyle(color: AppTheme.textSecondaryColor),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            onChanged: (v) {
                              final parsed = double.tryParse(v);
                              if (parsed != null) setState(() => _value = parsed);
                            },
                          ),
                        ),
                      ]),

                      // Quick presets
                      if (_getPresets(_selectedType!).isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _getPresets(_selectedType!).map((preset) {
                            final isSelected = _value == preset;
                            return GestureDetector(
                              onTap: () => _applyPreset(preset),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.accentColor.withValues(alpha: 0.2)
                                      : AppTheme.cardColor,
                                  borderRadius: BorderRadius.circular(6),
                                  border: isSelected
                                      ? Border.all(color: AppTheme.accentColor.withValues(alpha: 0.5))
                                      : null,
                                ),
                                child: Text(
                                  _formatValue(_selectedType!, preset),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    color: isSelected ? AppTheme.accentColor : AppTheme.textSecondaryColor,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],

                    // ── Preview ────────────────────────────────────────────
                    if (_selectedType != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle, color: AppTheme.accentColor, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              RuleCondition(type: _selectedType!, value: _value).description,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _canSave() {
    if (_selectedType == null) return false;
    if (_needsValue(_selectedType!) && _valueController.text.isEmpty) return false;
    return true;
  }

  String _getTypeName(RuleConditionType type) {
    switch (type) {
      case RuleConditionType.rsiBelow:                    return 'RSI Below';
      case RuleConditionType.rsiAbove:                    return 'RSI Above';
      case RuleConditionType.priceAboveSma:               return 'Above SMA';
      case RuleConditionType.priceBelowSma:               return 'Below SMA';
      case RuleConditionType.priceAboveEma:               return 'Above EMA';
      case RuleConditionType.priceBelowEma:               return 'Below EMA';
      case RuleConditionType.macdCrossover:               return 'Bullish Cross';
      case RuleConditionType.macdCrossunder:              return 'Bearish Cross';
      case RuleConditionType.volumeSpike:                 return 'Volume Spike';
      case RuleConditionType.priceNear52WeekLow:          return 'Near 52W Low';
      case RuleConditionType.priceNear52WeekHigh:         return 'Near 52W High';
      case RuleConditionType.bollingerBreakout:           return 'BB Breakout';
      case RuleConditionType.priceChangeAbove:            return 'Day Change >';
      case RuleConditionType.priceChangeBelow:            return 'Day Change <';
      case RuleConditionType.momentum6Month:              return '6M Return >';
      case RuleConditionType.momentum12Month:             return '12M Return >';
      case RuleConditionType.nearAllTimeHigh:             return 'Near 52W High';
      case RuleConditionType.breakoutNDayHigh:            return 'N-Day Breakout';
      case RuleConditionType.breakoutHeld:                return 'Breakout Held';
      case RuleConditionType.vcpSetup:                    return 'VCP Setup';
      case RuleConditionType.bollingerSqueeze:            return 'BB Squeeze';
      case RuleConditionType.stealthAccumulation:         return 'Stealth Accum';
      case RuleConditionType.obvDivergence:               return 'OBV Divergence';
      case RuleConditionType.oversoldBounce:              return 'Oversold Bounce';
      case RuleConditionType.earningsSurprise:            return 'EPS Beat';
      case RuleConditionType.insiderBuying:               return 'Director Buy';
      case RuleConditionType.event52WeekHighCrossover:    return '52W Crossover';
      case RuleConditionType.eventVolumeBreakout:         return 'Vol Breakout';
      case RuleConditionType.eventMomentumCrossover:      return '6M Crossover';
      case RuleConditionType.stateMomentumPositive:       return '6M Mom > 0';
      case RuleConditionType.stateVolumeExpanding:        return 'Vol Expanding';
      case RuleConditionType.stateAboveSma50:             return 'Above SMA50';
      case RuleConditionType.stateUptrend:                return 'Uptrend (20d)';
      case RuleConditionType.stateNear52WeekHigh:         return 'Near 52W High';
      case RuleConditionType.announcementWithinDays:      return 'Announcement';
      case RuleConditionType.earningsWithinDays:          return 'Earnings Ann';
      case RuleConditionType.directorTradeWithinDays:     return 'Director Trade';
      case RuleConditionType.capitalRaiseWithinDays:      return 'Capital Raise';
      case RuleConditionType.marketSensitiveWithinDays:   return 'Price Sensitive';
      case RuleConditionType.shortInterestAbove:          return 'Short % Above';
      case RuleConditionType.shortInterestBelow:          return 'Short % Below';
      case RuleConditionType.shortInterestRising:         return 'SI Rising';
      case RuleConditionType.daysToCoverAbove:            return 'DTC Above';
      case RuleConditionType.isNotHalted:                 return 'Not Halted';
      case RuleConditionType.resumedFromHalt:             return 'Resumed';
    }
  }

  bool _needsValue(RuleConditionType type) {
    const noValue = {
      RuleConditionType.macdCrossover,
      RuleConditionType.macdCrossunder,
      RuleConditionType.bollingerBreakout,
      RuleConditionType.vcpSetup,
      RuleConditionType.obvDivergence,
      RuleConditionType.insiderBuying,
      RuleConditionType.stateVolumeExpanding,
      RuleConditionType.stateAboveSma50,
      RuleConditionType.stateUptrend,
      RuleConditionType.isNotHalted,
      RuleConditionType.shortInterestRising,
    };
    return !noValue.contains(type);
  }

  double _getDefaultValue(RuleConditionType type) {
    switch (type) {
      case RuleConditionType.rsiBelow:                    return 30;
      case RuleConditionType.rsiAbove:                    return 70;
      case RuleConditionType.priceAboveSma:
      case RuleConditionType.priceBelowSma:
      case RuleConditionType.priceAboveEma:
      case RuleConditionType.priceBelowEma:               return 20;
      case RuleConditionType.volumeSpike:
      case RuleConditionType.stealthAccumulation:         return 2;
      case RuleConditionType.priceNear52WeekLow:
      case RuleConditionType.priceNear52WeekHigh:
      case RuleConditionType.nearAllTimeHigh:             return 5;
      case RuleConditionType.priceChangeAbove:            return 5;
      case RuleConditionType.priceChangeBelow:            return -5;
      case RuleConditionType.momentum6Month:
      case RuleConditionType.momentum12Month:             return 20;
      case RuleConditionType.breakoutNDayHigh:            return 50;
      case RuleConditionType.breakoutHeld:                return 5;
      case RuleConditionType.bollingerSqueeze:            return 5;
      case RuleConditionType.oversoldBounce:              return 10;
      case RuleConditionType.earningsSurprise:            return 5;
      case RuleConditionType.event52WeekHighCrossover:    return 97;
      case RuleConditionType.eventVolumeBreakout:         return 1.5;
      case RuleConditionType.eventMomentumCrossover:      return 10;
      case RuleConditionType.stateMomentumPositive:       return 5;
      case RuleConditionType.stateNear52WeekHigh:         return 95;
      case RuleConditionType.announcementWithinDays:      return 7;
      case RuleConditionType.earningsWithinDays:          return 14;
      case RuleConditionType.directorTradeWithinDays:     return 30;
      case RuleConditionType.capitalRaiseWithinDays:      return 14;
      case RuleConditionType.marketSensitiveWithinDays:   return 7;
      case RuleConditionType.shortInterestAbove:          return 5;
      case RuleConditionType.shortInterestBelow:          return 3;
      case RuleConditionType.daysToCoverAbove:            return 5;
      case RuleConditionType.resumedFromHalt:             return 3;
      default:                                            return 0;
    }
  }

  String _getValueLabel(RuleConditionType type) {
    switch (type) {
      case RuleConditionType.rsiBelow:
      case RuleConditionType.rsiAbove:                    return 'RSI Level (0–100)';
      case RuleConditionType.priceAboveSma:
      case RuleConditionType.priceBelowSma:
      case RuleConditionType.priceAboveEma:
      case RuleConditionType.priceBelowEma:
      case RuleConditionType.breakoutNDayHigh:            return 'Period (days)';
      case RuleConditionType.volumeSpike:
      case RuleConditionType.stealthAccumulation:         return 'Volume Multiplier (×avg)';
      case RuleConditionType.priceNear52WeekLow:
      case RuleConditionType.priceNear52WeekHigh:
      case RuleConditionType.nearAllTimeHigh:             return 'Within % of range';
      case RuleConditionType.bollingerSqueeze:            return 'BB Width % threshold';
      case RuleConditionType.priceChangeAbove:
      case RuleConditionType.priceChangeBelow:            return 'Day change %';
      case RuleConditionType.momentum6Month:              return '6-month return threshold (%)';
      case RuleConditionType.momentum12Month:             return '12-month return threshold (%)';
      case RuleConditionType.breakoutHeld:                return 'Days held above breakout';
      case RuleConditionType.oversoldBounce:              return 'Drop % in prior 3 days';
      case RuleConditionType.earningsSurprise:            return 'EPS beat threshold (%)';
      case RuleConditionType.event52WeekHighCrossover:    return '% of 52W high (e.g. 97 = within 3%)';
      case RuleConditionType.eventVolumeBreakout:         return 'Volume multiplier trigger';
      case RuleConditionType.eventMomentumCrossover:      return '6M return crossing above (%)';
      case RuleConditionType.stateMomentumPositive:       return '6M return must exceed (%)';
      case RuleConditionType.stateNear52WeekHigh:         return '% of 52W high (e.g. 95 = within 5%)';
      case RuleConditionType.announcementWithinDays:      return 'Any announcement within N days';
      case RuleConditionType.earningsWithinDays:          return 'Earnings announcement within N days';
      case RuleConditionType.directorTradeWithinDays:     return 'Director on-market trade within N days';
      case RuleConditionType.capitalRaiseWithinDays:      return 'Capital raise within N days';
      case RuleConditionType.marketSensitiveWithinDays:   return 'Price-sensitive announcement within N days';
      case RuleConditionType.shortInterestAbove:          return 'Short interest % of float above';
      case RuleConditionType.shortInterestBelow:          return 'Short interest % of float below';
      case RuleConditionType.daysToCoverAbove:            return 'Days to cover (DTC) above';
      case RuleConditionType.resumedFromHalt:             return 'Resumed from halt within N days';
      default:                                            return 'Value';
    }
  }

  String _getValueSuffix(RuleConditionType type) {
    switch (type) {
      case RuleConditionType.volumeSpike:
      case RuleConditionType.stealthAccumulation:
      case RuleConditionType.eventVolumeBreakout:         return '×';
      case RuleConditionType.priceNear52WeekLow:
      case RuleConditionType.priceNear52WeekHigh:
      case RuleConditionType.nearAllTimeHigh:
      case RuleConditionType.bollingerSqueeze:
      case RuleConditionType.priceChangeAbove:
      case RuleConditionType.priceChangeBelow:
      case RuleConditionType.momentum6Month:
      case RuleConditionType.momentum12Month:
      case RuleConditionType.oversoldBounce:
      case RuleConditionType.earningsSurprise:
      case RuleConditionType.event52WeekHighCrossover:
      case RuleConditionType.eventMomentumCrossover:
      case RuleConditionType.stateMomentumPositive:
      case RuleConditionType.stateNear52WeekHigh:
      case RuleConditionType.shortInterestAbove:
      case RuleConditionType.shortInterestBelow:          return '%';
      case RuleConditionType.announcementWithinDays:
      case RuleConditionType.earningsWithinDays:
      case RuleConditionType.directorTradeWithinDays:
      case RuleConditionType.capitalRaiseWithinDays:
      case RuleConditionType.marketSensitiveWithinDays:
      case RuleConditionType.breakoutNDayHigh:
      case RuleConditionType.breakoutHeld:
      case RuleConditionType.priceAboveSma:
      case RuleConditionType.priceBelowSma:
      case RuleConditionType.priceAboveEma:
      case RuleConditionType.priceBelowEma:
      case RuleConditionType.daysToCoverAbove:
      case RuleConditionType.resumedFromHalt:             return 'd';
      default:                                            return '';
    }
  }

  String _formatRaw(double v) {
    // Returns a clean string for text field initialisation
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  String _formatValue(RuleConditionType type, double value) {
    final suffix = _getValueSuffix(type);
    final raw = _formatRaw(value);
    return '$raw$suffix';
  }

  List<double> _getPresets(RuleConditionType type) {
    switch (type) {
      case RuleConditionType.rsiBelow:                    return [20, 30, 40];
      case RuleConditionType.rsiAbove:                    return [60, 70, 80];
      case RuleConditionType.priceAboveSma:
      case RuleConditionType.priceBelowSma:
      case RuleConditionType.priceAboveEma:
      case RuleConditionType.priceBelowEma:               return [10, 20, 50, 200];
      case RuleConditionType.volumeSpike:
      case RuleConditionType.stealthAccumulation:         return [1.5, 2, 3, 5];
      case RuleConditionType.priceNear52WeekLow:
      case RuleConditionType.priceNear52WeekHigh:
      case RuleConditionType.nearAllTimeHigh:
      case RuleConditionType.bollingerSqueeze:            return [3, 5, 10, 15];
      case RuleConditionType.priceChangeAbove:            return [2, 5, 10];
      case RuleConditionType.priceChangeBelow:            return [-2, -5, -10];
      case RuleConditionType.momentum6Month:
      case RuleConditionType.momentum12Month:             return [10, 20, 30, 50];
      case RuleConditionType.breakoutNDayHigh:            return [20, 50, 100];
      case RuleConditionType.breakoutHeld:                return [3, 5, 10];
      case RuleConditionType.oversoldBounce:              return [10, 15, 20];
      case RuleConditionType.earningsSurprise:            return [5, 10, 20];
      case RuleConditionType.eventVolumeBreakout:         return [1.5, 2, 3];
      case RuleConditionType.eventMomentumCrossover:
      case RuleConditionType.stateMomentumPositive:       return [0, 5, 10, 20];
      case RuleConditionType.stateNear52WeekHigh:
      case RuleConditionType.event52WeekHighCrossover:    return [90, 95, 97];
      case RuleConditionType.announcementWithinDays:
      case RuleConditionType.marketSensitiveWithinDays:   return [3, 7, 14, 30];
      case RuleConditionType.earningsWithinDays:          return [7, 14, 30, 60];
      case RuleConditionType.directorTradeWithinDays:     return [7, 14, 30, 60, 90];
      case RuleConditionType.capitalRaiseWithinDays:      return [7, 14, 30];
      case RuleConditionType.shortInterestAbove:          return [3, 5, 10, 15];
      case RuleConditionType.shortInterestBelow:          return [1, 2, 3, 5];
      case RuleConditionType.daysToCoverAbove:            return [3, 5, 10];
      case RuleConditionType.resumedFromHalt:             return [1, 3, 7];
      default:                                            return [];
    }
  }

  void _save() {
    if (_selectedType == null) return;
    final parsed = double.tryParse(_valueController.text) ?? _value;
    widget.onSave(RuleCondition(type: _selectedType!, value: _needsValue(_selectedType!) ? parsed : 0));
  }
}