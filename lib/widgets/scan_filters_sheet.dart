import 'package:flutter/material.dart';
import '../models/scan_filters.dart';
import '../utils/theme.dart';

class ScanFiltersSheet extends StatefulWidget {
  final ScanFilters initialFilters;
  final Function(ScanFilters) onSave;
  
  const ScanFiltersSheet({
    super.key,
    required this.initialFilters,
    required this.onSave,
  });
  
  static Future<ScanFilters?> show(BuildContext context, ScanFilters currentFilters) {
    return showModalBottomSheet<ScanFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScanFiltersSheet(
        initialFilters: currentFilters,
        onSave: (filters) => Navigator.pop(context, filters),
      ),
    );
  }

  @override
  State<ScanFiltersSheet> createState() => _ScanFiltersSheetState();
}

class _ScanFiltersSheetState extends State<ScanFiltersSheet> {
  late bool _enabled;
  late TextEditingController _minPriceController;
  late TextEditingController _maxPriceController;
  late TextEditingController _minVolumeController;
  late TextEditingController _maxGapController;
  
  @override
  void initState() {
    super.initState();
    _enabled = widget.initialFilters.enabled;
    _minPriceController = TextEditingController(
      text: widget.initialFilters.minPrice?.toStringAsFixed(2) ?? '',
    );
    _maxPriceController = TextEditingController(
      text: widget.initialFilters.maxPrice?.toStringAsFixed(2) ?? '',
    );
    _minVolumeController = TextEditingController(
      text: widget.initialFilters.minDailyDollarVolume != null 
        ? (widget.initialFilters.minDailyDollarVolume! / 1000).toStringAsFixed(0) 
        : '',
    );
    _maxGapController = TextEditingController(
      text: widget.initialFilters.maxSingleDayGap?.toStringAsFixed(0) ?? '',
    );
  }
  
  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _minVolumeController.dispose();
    _maxGapController.dispose();
    super.dispose();
  }
  
  ScanFilters _buildFilters() {
    return ScanFilters(
      enabled: _enabled,
      minPrice: double.tryParse(_minPriceController.text),
      maxPrice: double.tryParse(_maxPriceController.text),
      minDailyDollarVolume: _minVolumeController.text.isNotEmpty 
        ? (double.tryParse(_minVolumeController.text) ?? 0) * 1000 
        : null,
      maxSingleDayGap: double.tryParse(_maxGapController.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.textTertiaryColor, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            
            // Title
            Row(
              children: [
                const Icon(Icons.filter_list, color: AppTheme.accentColor),
                const SizedBox(width: 12),
                const Text('Scan Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                // Enable/Disable toggle
                Switch(
                  value: _enabled,
                  activeThumbColor: AppTheme.accentColor,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Exclude stocks that don\'t meet these criteria',
              style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13),
            ),
            const SizedBox(height: 24),
            
            // Filters (greyed out if disabled)
            Opacity(
              opacity: _enabled ? 1.0 : 0.5,
              child: IgnorePointer(
                ignoring: !_enabled,
                child: Column(
                  children: [
                    // Min Price
                    _buildFilterRow(
                      icon: Icons.attach_money,
                      label: 'Minimum Price',
                      hint: 'e.g., 0.10',
                      suffix: '\$',
                      controller: _minPriceController,
                      helperText: 'Exclude penny stocks',
                    ),
                    const SizedBox(height: 16),
                    
                    // Max Price
                    _buildFilterRow(
                      icon: Icons.money_off,
                      label: 'Maximum Price',
                      hint: 'e.g., 100',
                      suffix: '\$',
                      controller: _maxPriceController,
                      helperText: 'Leave empty for no limit',
                    ),
                    const SizedBox(height: 16),
                    
                    // Min Daily $ Volume
                    _buildFilterRow(
                      icon: Icons.bar_chart,
                      label: 'Min Daily \$ Volume',
                      hint: 'e.g., 50',
                      suffix: 'K',
                      controller: _minVolumeController,
                      helperText: 'Price × Volume (in thousands)',
                    ),
                    const SizedBox(height: 16),
                    
                    // Max Single-Day Gap
                    _buildFilterRow(
                      icon: Icons.trending_up,
                      label: 'Max Single-Day Gap',
                      hint: 'e.g., 20',
                      suffix: '%',
                      controller: _maxGapController,
                      helperText: 'Exclude earnings gaps',
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Preset buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPresetChip('Default', ScanFilters.defaultFilters),
                _buildPresetChip('No Filters', ScanFilters.none),
                _buildPresetChip('Liquid Only', const ScanFilters(
                  minPrice: 1.0,
                  minDailyDollarVolume: 100000,
                  maxSingleDayGap: 15,
                  enabled: true,
                )),
                _buildPresetChip('Penny Stocks', const ScanFilters(
                  minPrice: 0.01,
                  maxPrice: 0.50,
                  enabled: true,
                )),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Save button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => widget.onSave(_buildFilters()),
                child: const Text('APPLY FILTERS'),
              ),
            ),
            
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFilterRow({
    required IconData icon,
    required String label,
    required String hint,
    required String suffix,
    required TextEditingController controller,
    String? helperText,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.textSecondaryColor),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              if (helperText != null)
                Text(helperText, style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppTheme.textTertiaryColor),
              suffixText: suffix,
              suffixStyle: const TextStyle(color: AppTheme.textSecondaryColor),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: AppTheme.backgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildPresetChip(String label, ScanFilters preset) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: AppTheme.backgroundColor,
      onPressed: () {
        setState(() {
          _enabled = preset.enabled;
          _minPriceController.text = preset.minPrice?.toStringAsFixed(2) ?? '';
          _maxPriceController.text = preset.maxPrice?.toStringAsFixed(2) ?? '';
          _minVolumeController.text = preset.minDailyDollarVolume != null 
            ? (preset.minDailyDollarVolume! / 1000).toStringAsFixed(0) 
            : '';
          _maxGapController.text = preset.maxSingleDayGap?.toStringAsFixed(0) ?? '';
        });
      },
    );
  }
}