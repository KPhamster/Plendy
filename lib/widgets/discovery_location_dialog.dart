import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/colors.dart';
import '../models/discovery_location_filter.dart';
import '../services/google_maps_service.dart';
import '../utils/haptic_feedback.dart';

const double _minDiscoveryRadiusMiles = 5;
const double _maxDiscoveryRadiusMiles = 100;
const Duration _dialogAnimationDuration = Duration(milliseconds: 220);
const Color _dialogSurfaceColor = Color(0xFFFCFAF7);

VoidCallback _withDialogHaptic(VoidCallback callback) {
  return () {
    triggerHeavyHaptic();
    callback();
  };
}

ThemeData _buildDiscoveryDialogTheme(BuildContext context) {
  final ThemeData appTheme = Theme.of(context);
  final Color appPrimaryColor = appTheme.primaryColor;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: appPrimaryColor,
    colorScheme: ColorScheme.fromSeed(
      seedColor: appPrimaryColor,
      brightness: Brightness.light,
    ),
    textTheme: appTheme.textTheme,
  );
}

Widget _buildDiscoveryDialogHeader({
  required ThemeData theme,
  required String title,
  String? subtitle,
  required IconData icon,
}) {
  final String? trimmedSubtitle = subtitle?.trim();
  final bool hasSubtitle =
      trimmedSubtitle != null && trimmedSubtitle.isNotEmpty;
  return Container(
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: <Color>[
          theme.primaryColor,
          Color.lerp(theme.primaryColor, Colors.black, 0.18)!,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hasSubtitle) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  trimmedSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildDiscoveryPill(BuildContext context, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).primaryColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Values returned when the user taps Apply.
class DiscoveryLocationDialogResult {
  const DiscoveryLocationDialogResult({
    required this.sortMode,
    required this.areas,
    required this.areaMode,
    required this.radiusMiles,
  });

  final DiscoverySortMode sortMode;
  final List<DiscoveryAreaFilter> areas;
  final DiscoveryAreaMatchMode areaMode;
  final double radiusMiles;
}

class DiscoveryLocationDialog extends StatefulWidget {
  const DiscoveryLocationDialog({
    super.key,
    required this.mapsService,
    this.initialSortMode = DiscoverySortMode.random,
    this.initialAreas = const <DiscoveryAreaFilter>[],
    this.initialAreaMode = DiscoveryAreaMatchMode.strictBounds,
    this.initialRadiusMiles = 25,
    this.searchBiasLat,
    this.searchBiasLng,
  });

  final GoogleMapsService mapsService;
  final DiscoverySortMode initialSortMode;
  final List<DiscoveryAreaFilter> initialAreas;
  final DiscoveryAreaMatchMode initialAreaMode;
  final double initialRadiusMiles;
  final double? searchBiasLat;
  final double? searchBiasLng;

  @override
  State<DiscoveryLocationDialog> createState() =>
      _DiscoveryLocationDialogState();
}

class _DiscoveryLocationDialogState extends State<DiscoveryLocationDialog> {
  late DiscoverySortMode _sortMode;
  late List<DiscoveryAreaFilter> _areas;
  late DiscoveryAreaMatchMode _areaMode;
  late double _radiusMiles;

  final ScrollController _contentScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _sortMode = widget.initialSortMode;
    _areas = List<DiscoveryAreaFilter>.from(widget.initialAreas);
    _areaMode = widget.initialAreaMode;
    _radiusMiles = widget.initialRadiusMiles.clamp(
      _minDiscoveryRadiusMiles,
      _maxDiscoveryRadiusMiles,
    );
  }

  @override
  void dispose() {
    _contentScrollController.dispose();
    super.dispose();
  }

  Future<void> _openAreaPicker() async {
    final List<DiscoveryAreaFilter>? result =
        await showDialog<List<DiscoveryAreaFilter>>(
      context: context,
      builder: (BuildContext context) => _DiscoveryAreaPickerDialog(
        mapsService: widget.mapsService,
        initialAreas: _areas,
        searchBiasLat: widget.searchBiasLat,
        searchBiasLng: widget.searchBiasLng,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _areas = List<DiscoveryAreaFilter>.from(result);
    });
  }

  void _removeArea(DiscoveryAreaFilter area) {
    setState(() {
      _areas = _areas
          .where((DiscoveryAreaFilter a) => a.placeId != area.placeId)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData lightTheme = _buildDiscoveryDialogTheme(context);
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final ColorScheme colorScheme = lightTheme.colorScheme;
    final double maxDialogHeight = math.max(
      0,
      math.min(
        mediaQuery.size.height * 0.82,
        mediaQuery.size.height - mediaQuery.padding.top - 24,
      ),
    );

    return Theme(
      data: lightTheme,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: 560, maxHeight: maxDialogHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _dialogSurfaceColor,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 32,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                _buildDiscoveryDialogHeader(
                  theme: lightTheme,
                  title: 'Sort by Location',
                  icon: Icons.travel_explore_rounded,
                ),
                Flexible(
                  child: Scrollbar(
                    controller: _contentScrollController,
                    child: SingleChildScrollView(
                      controller: _contentScrollController,
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _buildSection(
                            theme: lightTheme,
                            title: 'Areas to discover',
                            subtitle:
                                'Specify areas such as cities and regions to explore.',
                            child: _buildAreaSearchSection(lightTheme),
                          ),
                          _buildSectionDivider(colorScheme),
                          _buildSection(
                            theme: lightTheme,
                            title: 'Sort order',
                            child: Column(
                              children: <Widget>[
                                _buildOptionTile(
                                  theme: lightTheme,
                                  selected:
                                      _sortMode == DiscoverySortMode.nearest,
                                  icon: Icons.near_me_rounded,
                                  title: 'Sort by nearest',
                                  subtitle: 'Find places near you.',
                                  onTap: _withDialogHaptic(() => setState(
                                        () => _sortMode =
                                            DiscoverySortMode.nearest,
                                      )),
                                ),
                                const SizedBox(height: 12),
                                _buildOptionTile(
                                  theme: lightTheme,
                                  selected:
                                      _sortMode == DiscoverySortMode.random,
                                  icon: Icons.shuffle_rounded,
                                  title: 'Random order',
                                  subtitle: 'Good for discovery.',
                                  onTap: _withDialogHaptic(() => setState(
                                        () => _sortMode =
                                            DiscoverySortMode.random,
                                      )),
                                ),
                              ],
                            ),
                          ),
                          _buildSectionDivider(colorScheme),
                          _buildSection(
                            theme: lightTheme,
                            title: 'Match rules',
                            subtitle: _areas.isEmpty
                                ? 'Add at least one area above to make location filtering active.'
                                : 'Choose whether results stay inside the selected areas or can extend beyond them.',
                            child: _buildAreaModeSection(
                              context,
                              lightTheme,
                              colorScheme,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    border: Border(
                      top: BorderSide(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: _withDialogHaptic(
                            () => Navigator.of(context).pop()),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: lightTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _withDialogHaptic(() {
                          Navigator.of(context).pop(
                            DiscoveryLocationDialogResult(
                              sortMode: _sortMode,
                              areas: List<DiscoveryAreaFilter>.from(_areas),
                              areaMode: _areaMode,
                              radiusMiles: _radiusMiles,
                            ),
                          );
                        }),
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required ThemeData theme,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final String? trimmedSubtitle = subtitle?.trim();
    final bool hasSubtitle =
        trimmedSubtitle != null && trimmedSubtitle.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.primaryBlack,
          ),
        ),
        if (hasSubtitle) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            trimmedSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _buildSectionDivider(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildOptionTile({
    required ThemeData theme,
    required bool selected,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final String? trimmedSubtitle = subtitle?.trim();
    final bool hasSubtitle =
        trimmedSubtitle != null && trimmedSubtitle.isNotEmpty;
    final Color borderColor = selected
        ? theme.primaryColor
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.65);
    final Color fillColor = Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: _dialogAnimationDuration,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? theme.primaryColor : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: selected ? Colors.white : theme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryBlack,
                      ),
                    ),
                    if (hasSubtitle) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        trimmedSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.primaryGreyDark,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? theme.primaryColor
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAreaSearchSection(ThemeData theme) {
    final String summary = _areas.isEmpty
        ? 'Tap to search and choose areas in a separate dialog.'
        : '${_areas.length} area${_areas.length == 1 ? '' : 's'} selected';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _withDialogHaptic(_openAreaPicker),
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.search_rounded,
                      color: theme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _areas.isEmpty
                              ? 'Search and select areas'
                              : 'Edit selected areas',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryBlack,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_areas.isEmpty)
          Text(
            'No areas selected yet. Discovery will stay global until you add one.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _areas
                .map(
                  (DiscoveryAreaFilter area) => InputChip(
                    label: Text(
                      area.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    labelStyle: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlack,
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: theme.primaryColor.withValues(alpha: 0.18),
                    ),
                    deleteIcon: const Icon(Icons.close_rounded, size: 18),
                    deleteIconColor: theme.primaryColor,
                    onDeleted: _withDialogHaptic(() => _removeArea(area)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildAreaModeSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildOptionTile(
          theme: theme,
          selected: _areaMode == DiscoveryAreaMatchMode.strictBounds,
          icon: Icons.crop_free_rounded,
          title: 'These areas only',
          onTap: _withDialogHaptic(() => setState(
                () => _areaMode = DiscoveryAreaMatchMode.strictBounds,
              )),
        ),
        const SizedBox(height: 12),
        _buildOptionTile(
          theme: theme,
          selected: _areaMode == DiscoveryAreaMatchMode.withinRadius,
          icon: Icons.radar_rounded,
          title: 'Within ${_radiusMiles.round()} miles of these areas',
          onTap: _withDialogHaptic(() => setState(
                () => _areaMode = DiscoveryAreaMatchMode.withinRadius,
              )),
        ),
        AnimatedSwitcher(
          duration: _dialogAnimationDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _areaMode == DiscoveryAreaMatchMode.withinRadius
              ? Padding(
                  key: const ValueKey<String>('radius-slider'),
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.primaryColor.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              'Radius',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryBlack,
                              ),
                            ),
                            const Spacer(),
                            _buildDiscoveryPill(
                              context,
                              '${_radiusMiles.round()} mi',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: theme.primaryColor,
                            inactiveTrackColor:
                                theme.primaryColor.withValues(alpha: 0.18),
                            thumbColor: theme.primaryColor,
                            overlayColor:
                                theme.primaryColor.withValues(alpha: 0.12),
                          ),
                          child: Slider(
                            min: _minDiscoveryRadiusMiles,
                            max: _maxDiscoveryRadiusMiles,
                            divisions: 19,
                            label: '${_radiusMiles.round()} mi',
                            value: _radiusMiles,
                            onChangeStart: (_) => triggerHeavyHaptic(),
                            onChanged: (double value) {
                              setState(() => _radiusMiles = value);
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              '5 mi',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '100 mi',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(
                  key: ValueKey<String>('radius-slider-hidden'),
                ),
        ),
      ],
    );
  }
}

class _DiscoveryAreaPickerDialog extends StatefulWidget {
  const _DiscoveryAreaPickerDialog({
    required this.mapsService,
    required this.initialAreas,
    this.searchBiasLat,
    this.searchBiasLng,
  });

  final GoogleMapsService mapsService;
  final List<DiscoveryAreaFilter> initialAreas;
  final double? searchBiasLat;
  final double? searchBiasLng;

  @override
  State<_DiscoveryAreaPickerDialog> createState() =>
      _DiscoveryAreaPickerDialogState();
}

class _DiscoveryAreaPickerDialogState
    extends State<_DiscoveryAreaPickerDialog> {
  late List<DiscoveryAreaFilter> _areas;

  final TextEditingController _queryController = TextEditingController();
  final ScrollController _selectedAreasScrollController = ScrollController();

  Timer? _searchDebounce;
  bool _isSearchingPlaces = false;
  bool _isAddingPlace = false;
  List<Map<String, dynamic>> _placeSuggestions = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _areas = List<DiscoveryAreaFilter>.from(widget.initialAreas);
    _queryController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _queryController.removeListener(_onQueryChanged);
    _queryController.dispose();
    _selectedAreasScrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      _runAreaSearch,
    );
  }

  Future<void> _runAreaSearch() async {
    final String query = _queryController.text.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _placeSuggestions = <Map<String, dynamic>>[];
          _isSearchingPlaces = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isSearchingPlaces = true);
    }

    try {
      final List<Map<String, dynamic>> results =
          await widget.mapsService.searchPlaces(
        query,
        latitude: widget.searchBiasLat,
        longitude: widget.searchBiasLng,
      );
      if (!mounted) return;
      setState(() {
        _placeSuggestions = results;
        _isSearchingPlaces = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _placeSuggestions = <Map<String, dynamic>>[];
          _isSearchingPlaces = false;
        });
      }
    }
  }

  Future<void> _onSelectSuggestion(Map<String, dynamic> suggestion) async {
    final String? placeId = suggestion['placeId'] as String?;
    if (placeId == null || placeId.isEmpty) return;

    final String label = (suggestion['description'] as String?) ??
        (suggestion['name'] as String?) ??
        placeId;

    if (_areas.any((DiscoveryAreaFilter area) => area.placeId == placeId)) {
      _queryController.clear();
      setState(() => _placeSuggestions = <Map<String, dynamic>>[]);
      return;
    }

    setState(() => _isAddingPlace = true);
    final DiscoveryAreaFilter? area =
        await widget.mapsService.fetchDiscoveryAreaFromPlace(placeId, label);
    if (!mounted) return;

    setState(() => _isAddingPlace = false);
    if (area == null) return;

    setState(() {
      _areas = List<DiscoveryAreaFilter>.from(_areas)..add(area);
      _queryController.clear();
      _placeSuggestions = <Map<String, dynamic>>[];
    });
  }

  void _removeArea(DiscoveryAreaFilter area) {
    setState(() {
      _areas = _areas
          .where((DiscoveryAreaFilter a) => a.placeId != area.placeId)
          .toList();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _queryController.clear();
    setState(() {
      _placeSuggestions = <Map<String, dynamic>>[];
      _isSearchingPlaces = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData lightTheme = _buildDiscoveryDialogTheme(context);
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final double maxDialogHeight = math.max(
      0,
      math.min(
        mediaQuery.size.height * 0.78,
        mediaQuery.size.height - mediaQuery.padding.top - 24,
      ),
    );

    return Theme(
      data: lightTheme,
      child: MediaQuery.removeViewInsets(
        removeBottom: true,
        context: context,
        child: Dialog(
          alignment: Alignment.center,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: 560, maxHeight: maxDialogHeight),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _dialogSurfaceColor,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 32,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  _buildDiscoveryDialogHeader(
                    theme: lightTheme,
                    title: 'Choose Areas',
                    subtitle:
                        'Search places, add the ones you want, then tap Done to return to the main dialog.',
                    icon: Icons.search_rounded,
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                      child: LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints constraints) {
                          final double searchResultsMaxHeight = math.min(
                            240,
                            constraints.maxHeight * 0.4,
                          );

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TextField(
                                controller: _queryController,
                                autofocus: true,
                                enabled: !_isAddingPlace,
                                textInputAction: TextInputAction.search,
                                onTap: triggerHeavyHaptic,
                                decoration: InputDecoration(
                                  hintText:
                                      'Search cities, neighborhoods, or regions',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  suffixIcon: _isSearchingPlaces
                                      ? const Padding(
                                          padding: EdgeInsets.all(14),
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : _queryController.text.trim().isNotEmpty
                                          ? IconButton(
                                              onPressed: _withDialogHaptic(
                                                _clearSearch,
                                              ),
                                              icon: const Icon(
                                                Icons.close_rounded,
                                              ),
                                            )
                                          : null,
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 16,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color: lightTheme
                                          .colorScheme.outlineVariant
                                          .withValues(alpha: 0.55),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color: lightTheme
                                          .colorScheme.outlineVariant
                                          .withValues(alpha: 0.55),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color: lightTheme.primaryColor,
                                      width: 1.6,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Flexible(
                                fit: FlexFit.loose,
                                child: AnimatedSwitcher(
                                  duration: _dialogAnimationDuration,
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: _buildSearchResultsPanel(
                                      lightTheme,
                                      searchResultsMaxHeight,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: <Widget>[
                                  Text(
                                    'Selected areas',
                                    style: lightTheme.textTheme.titleSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryBlack,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_areas.isNotEmpty)
                                    _buildDiscoveryPill(
                                      context,
                                      '${_areas.length} selected',
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: _areas.isEmpty
                                    ? _buildEmptyAreasState(lightTheme)
                                    : SingleChildScrollView(
                                        controller:
                                            _selectedAreasScrollController,
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: _areas
                                              .map(
                                                (DiscoveryAreaFilter area) =>
                                                    InputChip(
                                                  label: Text(
                                                    area.label,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  labelStyle: lightTheme
                                                      .textTheme.bodyMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        AppColors.primaryBlack,
                                                  ),
                                                  backgroundColor: Colors.white,
                                                  side: BorderSide(
                                                    color: lightTheme
                                                        .primaryColor
                                                        .withValues(
                                                            alpha: 0.18),
                                                  ),
                                                  deleteIcon: const Icon(
                                                    Icons.close_rounded,
                                                    size: 18,
                                                  ),
                                                  deleteIconColor:
                                                      lightTheme.primaryColor,
                                                  onDeleted: _withDialogHaptic(
                                                    () => _removeArea(area),
                                                  ),
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                              ),
                              if (_isAddingPlace) ...<Widget>[
                                const SizedBox(height: 10),
                                Row(
                                  children: <Widget>[
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Adding area...',
                                      style: lightTheme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: AppColors.primaryGreyDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      border: Border(
                        top: BorderSide(
                          color: lightTheme.colorScheme.outlineVariant
                              .withValues(alpha: 0.55),
                        ),
                      ),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(28),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            minimumSize: const Size(0, 40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _withDialogHaptic(
                            () => Navigator.of(context).pop(),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: lightTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            minimumSize: const Size(0, 40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _withDialogHaptic(() {
                            Navigator.of(context).pop(
                              List<DiscoveryAreaFilter>.from(_areas),
                            );
                          }),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultsPanel(ThemeData theme, double maxResultsHeight) {
    final String query = _queryController.text.trim();
    final Color borderColor =
        theme.colorScheme.outlineVariant.withValues(alpha: 0.55);

    if (_isSearchingPlaces) {
      return _buildPickerStateCard(
        key: const ValueKey<String>('picker-loading'),
        theme: theme,
        borderColor: borderColor,
        icon: Icons.sync_rounded,
        title: 'Searching nearby matches',
        subtitle: 'Looking for places that fit your query.',
      );
    }

    if (query.isEmpty) {
      return _buildPickerStateCard(
        key: const ValueKey<String>('picker-empty'),
        theme: theme,
        borderColor: borderColor,
        icon: Icons.travel_explore_rounded,
        title: 'Start typing to search',
        subtitle: 'Try a city, neighborhood, county, or region.',
      );
    }

    if (_placeSuggestions.isEmpty) {
      return _buildPickerStateCard(
        key: const ValueKey<String>('picker-no-results'),
        theme: theme,
        borderColor: borderColor,
        icon: Icons.map_outlined,
        title: 'No areas found yet',
        subtitle: 'Try a broader place name or a nearby city.',
      );
    }

    return Container(
      key: const ValueKey<String>('picker-results'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxResultsHeight),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: _placeSuggestions.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 62,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          itemBuilder: (BuildContext context, int index) {
            final Map<String, dynamic> suggestion = _placeSuggestions[index];
            final String placeId = (suggestion['placeId'] as String?) ?? '';
            final String title = (suggestion['description'] as String?) ??
                (suggestion['name'] as String?) ??
                '';
            final bool alreadySelected = _areas.any(
              (DiscoveryAreaFilter area) => area.placeId == placeId,
            );

            return InkWell(
              onTap: _isAddingPlace || alreadySelected
                  ? null
                  : _withDialogHaptic(
                      () => _onSelectSuggestion(suggestion),
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.place_rounded,
                        size: 20,
                        color: alreadySelected
                            ? theme.primaryColor
                            : AppColors.navyBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: alreadySelected
                              ? theme.colorScheme.onSurfaceVariant
                              : AppColors.primaryBlack,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      alreadySelected
                          ? Icons.check_circle_rounded
                          : Icons.add_circle_outline_rounded,
                      color: alreadySelected
                          ? theme.primaryColor
                          : theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPickerStateCard({
    required Key key,
    required ThemeData theme,
    required Color borderColor,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: AppColors.navyBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlack,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primaryGreyDark,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAreasState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No areas selected yet. Search above, tap a result to add it, then tap Done to bring those areas back into the main dialog.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
