import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import 'map_screen.dart';

typedef PlayerSetupSaver =
    Future<void> Function(
      CourtSummary court,
      String position,
      List<String> playStyles,
    );

typedef PlayerSetupMapPicker =
    Future<CourtSummary?> Function(CourtSummary? selectedCourt);

class PlayerSetupScreen extends StatefulWidget {
  const PlayerSetupScreen({
    super.key,
    this.repository,
    this.profile,
    this.editing = false,
    this.saveOverride,
    this.courtsOverride,
    this.mapPickerOverride,
  }) : assert(repository != null || saveOverride != null);

  final BackcourtRepository? repository;
  final AppUserProfile? profile;
  final bool editing;
  final PlayerSetupSaver? saveOverride;
  final List<CourtSummary>? courtsOverride;
  final PlayerSetupMapPicker? mapPickerOverride;

  @override
  State<PlayerSetupScreen> createState() => _PlayerSetupScreenState();
}

class _PlayerSetupScreenState extends State<PlayerSetupScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _operatorNames = {};
  StreamSubscription<Map<String, String>>? _nameSubscription;
  List<_CourtOption> _courts = const [];
  CourtSummary? _selectedCourt;
  Position? _origin;
  String? _position;
  final Set<String> _playStyles = {};
  int _step = 0;
  bool _loadingCourts = true;
  bool _locating = false;
  bool _saving = false;
  String _query = '';

  static const _positions = [
    _Choice('guard', '가드', Icons.sports_basketball_rounded),
    _Choice('forward', '포워드', Icons.directions_run_rounded),
    _Choice('center', '센터', Icons.height_rounded),
  ];

  static const _styles = [
    _Choice('shooting', '슛', Icons.adjust_rounded),
    _Choice('drive', '돌파', Icons.bolt_rounded),
    _Choice('passing', '패스', Icons.sync_alt_rounded),
    _Choice('defense', '수비', Icons.shield_outlined),
    _Choice('rebound', '리바운드', Icons.vertical_align_top_rounded),
  ];

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _selectedCourt = profile?.homeCourt;
    _position = profile?.position;
    _playStyles.addAll(profile?.playStyles ?? const []);
    final courtsOverride = widget.courtsOverride;
    if (courtsOverride == null) {
      _loadCourts();
    } else {
      _courts = courtsOverride
          .map(
            (court) => _CourtOption(
              court: court,
              searchText: [
                court.name,
                court.address,
              ].whereType<String>().join(' ').toLowerCase(),
            ),
          )
          .toList(growable: false);
      _loadingCourts = false;
    }
    _subscribeToCourtNames();
    _restoreGrantedLocation();
  }

  @override
  void dispose() {
    _nameSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeToCourtNames() {
    final repository = widget.repository;
    if (repository == null) return;
    _nameSubscription = repository.watchOperatorCourtNames().listen((names) {
      if (!mounted) return;
      setState(() {
        _operatorNames
          ..clear()
          ..addAll(names);
      });
    });
  }

  Future<void> _loadCourts() async {
    try {
      final source = await rootBundle.loadString(
        'assets/data/korea_basketball_courts.geojson',
      );
      final geoJson = jsonDecode(source) as Map<String, dynamic>;
      final features = geoJson['features'] as List<dynamic>;
      final courts = features
          .map(
            (feature) =>
                _CourtOption.fromFeature(feature as Map<String, dynamic>),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _courts = courts;
        _loadingCourts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCourts = false);
      _show('코트 목록을 불러오지 못했어요.');
    }
  }

  Future<void> _restoreGrantedLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        await _locate(requestPermission: false);
      }
    } catch (_) {
      // Manual court search remains available when location is unavailable.
    }
  }

  Future<void> _locate({bool requestPermission = true}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _show(
          '위치 서비스가 꺼져 있어요.',
          action: SnackBarAction(
            label: '설정',
            onPressed: Geolocator.openLocationSettings,
          ),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _show(
          '설정에서 위치 권한을 허용해주세요.',
          action: SnackBarAction(
            label: '설정',
            onPressed: Geolocator.openAppSettings,
          ),
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        _show('코트 이름으로 직접 검색할 수 있어요.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() => _origin = position);
    } on TimeoutException {
      _show('현재 위치를 확인하지 못했어요.');
    } catch (_) {
      _show('위치를 가져오지 못했어요. 검색으로 골라주세요.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  List<_CourtOption> get _visibleCourts {
    final query = _query.trim().toLowerCase();
    final results = _courts.where((option) {
      if (query.isEmpty) return _origin != null;
      final operatorName = _operatorNames[option.court.id];
      return option.searchText.contains(query) ||
          (operatorName?.toLowerCase().contains(query) ?? false);
    }).toList();
    final origin = _origin;
    if (origin != null) {
      results.sort(
        (a, b) =>
            _distance(origin, a.court).compareTo(_distance(origin, b.court)),
      );
    }
    return results.take(12).toList(growable: false);
  }

  double _distance(Position origin, CourtSummary court) =>
      Geolocator.distanceBetween(
        origin.latitude,
        origin.longitude,
        court.latitude,
        court.longitude,
      );

  CourtSummary _resolvedCourt(_CourtOption option) {
    final court = option.court;
    return CourtSummary(
      id: court.id,
      name: _operatorNames[court.id] ?? court.name,
      latitude: court.latitude,
      longitude: court.longitude,
      address: court.address,
      facts: court.facts,
    );
  }

  String _distanceLabel(CourtSummary court) {
    final origin = _origin;
    if (origin == null) return court.address ?? '전국 코트';
    final meters = _distance(origin, court);
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  void _selectCourt(_CourtOption option) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedCourt = _resolvedCourt(option));
  }

  Future<void> _openCourtMap() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final override = widget.mapPickerOverride;
    final CourtSummary? selected;
    if (override != null) {
      selected = await override(_selectedCourt);
    } else {
      if (!mounted) return;
      selected = await Navigator.of(context).push<CourtSummary>(
        MaterialPageRoute(
          builder: (pickerContext) => Scaffold(
            backgroundColor: AppColors.background,
            body: MapScreen(
              repository: widget.repository,
              initialCourt: _selectedCourt,
              pickerMode: true,
              onPickerClose: () => Navigator.pop(pickerContext),
              onCourtSelected: (court) => Navigator.pop(pickerContext, court),
            ),
          ),
        ),
      );
    }
    if (!mounted || selected == null) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedCourt = selected);
  }

  void _toggleStyle(String value) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_playStyles.remove(value)) {
        if (_playStyles.length >= 3) {
          _show('최대 3개까지 고를 수 있어요.');
          return;
        }
        _playStyles.add(value);
      }
    });
  }

  void _next() {
    if (_selectedCourt == null) {
      _show('자주 가는 코트를 하나 골라주세요.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = 1);
  }

  Future<void> _save() async {
    final court = _selectedCourt;
    final position = _position;
    if (court == null) {
      setState(() => _step = 0);
      return;
    }
    if (position == null || _playStyles.isEmpty) {
      _show('포지션과 플레이 스타일을 골라주세요.');
      return;
    }
    setState(() => _saving = true);
    try {
      final override = widget.saveOverride;
      if (override != null) {
        await override(court, position, _playStyles.toList(growable: false));
      } else {
        await widget.repository!.completePlayerSetup(
          homeCourt: court,
          position: position,
          playStyles: _playStyles.toList(growable: false),
        );
      }
      HapticFeedback.mediumImpact();
      if (widget.editing && mounted) Navigator.pop(context, true);
    } catch (error) {
      _show(error is BackcourtException ? error.message : '저장하지 못했어요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _step == 0
        ? _selectedCourt != null
        : _position != null && _playStyles.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _SetupHeader(
                  step: _step,
                  editing: widget.editing,
                  onBack: _step == 1
                      ? () => setState(() => _step = 0)
                      : widget.editing
                      ? () => Navigator.pop(context)
                      : null,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(.035, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _step == 0 ? _buildCourtStep() : _buildPlayStep(),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _SetupAction(
              enabled: canContinue && !_saving,
              loading: _saving,
              label: _step == 0
                  ? '다음'
                  : widget.editing
                  ? '저장'
                  : '빽코트 시작',
              onTap: _step == 0 ? _next : _save,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourtStep() {
    final visibleCourts = _visibleCourts;
    return Column(
      key: const ValueKey('setup-court-step'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(22, 30, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MY COURT',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              SizedBox(height: 11),
              Text(
                '자주 가는 코트를\n골라주세요.',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 34,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.8,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('setup-court-search'),
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: '코트 이름이나 동네 검색',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              SizedBox(width: 9),
              SizedBox.square(
                dimension: 56,
                child: IconButton.filled(
                  key: const ValueKey('setup-nearby-courts'),
                  onPressed: _locating ? null : _locate,
                  style: IconButton.styleFrom(
                    backgroundColor: _origin == null
                        ? AppColors.surfaceHigh
                        : AppColors.accent,
                    foregroundColor: _origin == null
                        ? AppColors.text
                        : AppColors.onAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  icon: _locating
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.my_location_rounded),
                ),
              ),
              SizedBox(width: 9),
              _SetupMapButton(onTap: _openCourtMap),
            ],
          ),
        ),
        if (_selectedCourt case final selected?)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
            child: _SelectedCourtCard(court: selected),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
          child: Text(
            _query.trim().isNotEmpty
                ? '검색 결과'
                : _origin != null
                ? '가까운 코트'
                : '위치 버튼을 누르거나 검색하세요',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: _loadingCourts
              ? Center(
                  child: CircularProgressIndicator(
                    color: AppColors.accent,
                    strokeWidth: 2.5,
                  ),
                )
              : visibleCourts.isEmpty
              ? _CourtEmpty(querying: _query.trim().isNotEmpty)
              : ListView.separated(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 130),
                  itemCount: visibleCourts.length,
                  separatorBuilder: (_, _) => SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final option = visibleCourts[index];
                    final court = _resolvedCourt(option);
                    return _CourtChoiceRow(
                      court: court,
                      distance: _distanceLabel(court),
                      selected: _selectedCourt?.id == court.id,
                      onTap: () => _selectCourt(option),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPlayStep() {
    return ListView(
      key: const ValueKey('setup-play-step'),
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 140),
      children: [
        Text(
          'MY PLAY',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
        SizedBox(height: 11),
        Text(
          '포지션과 스타일',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.8,
          ),
        ),
        SizedBox(height: 35),
        const _SetupLabel(title: '포지션'),
        SizedBox(height: 11),
        Row(
          children: _positions
              .map((choice) {
                final selected = _position == choice.value;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: choice == _positions.last ? 0 : 9,
                    ),
                    child: _PositionCard(
                      choice: choice,
                      selected: selected,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _position = choice.value);
                      },
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
        SizedBox(height: 31),
        Row(
          children: [
            Expanded(child: _SetupLabel(title: '플레이 스타일')),
            Text(
              '${_playStyles.length}/3',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        SizedBox(height: 11),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: _styles
              .map(
                (choice) => _StyleChip(
                  choice: choice,
                  selected: _playStyles.contains(choice.value),
                  onTap: () => _toggleStyle(choice.value),
                ),
              )
              .toList(growable: false),
        ),
        SizedBox(height: 35),
        if (_selectedCourt case final court?)
          _SetupSummary(
            court: court,
            position: _positions
                .where((choice) => choice.value == _position)
                .firstOrNull
                ?.label,
            styles: _styles
                .where((choice) => _playStyles.contains(choice.value))
                .map((choice) => choice.label)
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _CourtOption {
  const _CourtOption({required this.court, required this.searchText});

  factory _CourtOption.fromFeature(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;
    final properties = feature['properties'] as Map<String, dynamic>;
    String? read(String key) {
      final value = properties[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final osmType = read('osm_type') ?? 'feature';
    final osmId = (properties['osm_id'] as num?)?.toInt() ?? feature['id'];
    final administrativeName = read('administrative_name');
    final sourceName = read('name');
    final generic =
        sourceName == null ||
        sourceName == '이름 없는 농구 코트' ||
        sourceName == '농구코트';
    final name = generic && administrativeName != null
        ? '$administrativeName 농구장'
        : sourceName ?? '지역 농구장';
    final address = read('address') ?? administrativeName;
    final facts = <String>[
      if (read('indoor') == 'yes')
        '실내'
      else if (read('covered') == 'yes')
        '지붕 있음'
      else
        '야외',
      if (read('lit') == 'yes') '조명 있음',
      if (read('fee') == 'no') '무료',
    ];
    final court = CourtSummary(
      id: 'osm_${osmType}_$osmId',
      name: name,
      latitude: (coordinates[1] as num).toDouble(),
      longitude: (coordinates[0] as num).toDouble(),
      address: address,
      facts: facts,
    );
    return _CourtOption(
      court: court,
      searchText: [
        name,
        address,
        read('operator'),
      ].whereType<String>().join(' ').toLowerCase(),
    );
  }

  final CourtSummary court;
  final String searchText;
}

class _Choice {
  const _Choice(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}

class _SetupMapButton extends StatelessWidget {
  const _SetupMapButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        key: const ValueKey('setup-court-map'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: SizedBox(
          width: 72,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, color: AppColors.accent, size: 20),
              SizedBox(height: 2),
              Text(
                '지도',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupHeader extends StatelessWidget {
  const _SetupHeader({
    required this.step,
    required this.editing,
    required this.onBack,
  });

  final int step;
  final bool editing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 15, 22, 0),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              key: const ValueKey('setup-back'),
              onPressed: onBack,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.text.withValues(alpha: .06),
              ),
              icon: Icon(
                step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded,
              ),
            ),
            SizedBox(width: 9),
          ] else
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset('icon.png', width: 38, height: 38),
            ),
          SizedBox(width: 10),
          Text(
            '빽코트',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.text.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.text.withValues(alpha: .08)),
            ),
            child: Text(
              editing ? 'MY PLAY' : 'SETUP  ·  0${step + 2}/03',
              style: TextStyle(
                color: AppColors.soft,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedCourtCard extends StatelessWidget {
  const _SelectedCourtCard({required this.court});

  final CourtSummary court;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: AppColors.accent.withValues(alpha: .42)),
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.sports_basketball_rounded,
              color: AppColors.onAccent,
              size: 20,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '내 코트',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  court.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle_rounded, color: AppColors.accent),
        ],
      ),
    );
  }
}

class _CourtChoiceRow extends StatelessWidget {
  const _CourtChoiceRow({
    required this.court,
    required this.distance,
    required this.selected,
    required this.onTap,
  });

  final CourtSummary court;
  final String distance;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: .08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: .55)
                  : AppColors.text.withValues(alpha: .07),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.place_outlined,
                color: selected ? AppColors.accent : AppColors.soft,
                size: 21,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      court.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (court.address?.isNotEmpty == true) ...[
                      SizedBox(height: 4),
                      Text(
                        court.address!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 10),
              Text(
                distance,
                style: TextStyle(
                  color: selected ? AppColors.accent : AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final _Choice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('setup-position-${choice.value}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          height: 104,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : AppColors.text.withValues(alpha: .08),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                choice.icon,
                color: selected ? AppColors.onAccent : AppColors.soft,
                size: 25,
              ),
              SizedBox(height: 9),
              Text(
                choice.label,
                style: TextStyle(
                  color: selected ? AppColors.onAccent : AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  const _StyleChip({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final _Choice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('setup-style-${choice.value}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: .14)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : AppColors.text.withValues(alpha: .08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                choice.icon,
                color: selected ? AppColors.accent : AppColors.muted,
                size: 17,
              ),
              SizedBox(width: 7),
              Text(
                choice.label,
                style: TextStyle(
                  color: selected ? AppColors.text : AppColors.soft,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupSummary extends StatelessWidget {
  const _SetupSummary({
    required this.court,
    required this.position,
    required this.styles,
  });

  final CourtSummary court;
  final String? position;
  final List<String> styles;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: AppColors.accent.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Container(
            width: 47,
            height: 47,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.sports_basketball_rounded,
              color: AppColors.onAccent,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  court.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  [?position, ...styles].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupLabel extends StatelessWidget {
  const _SetupLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      color: AppColors.text,
      fontSize: 14,
      fontWeight: FontWeight.w900,
    ),
  );
}

class _CourtEmpty extends StatelessWidget {
  const _CourtEmpty({required this.querying});

  final bool querying;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Text(
          querying ? '검색 결과가 없어요.' : '',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SetupAction extends StatelessWidget {
  const _SetupAction({
    required this.enabled,
    required this.loading,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final bool loading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        32,
        22,
        MediaQuery.paddingOf(context).bottom + 14,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            AppColors.background,
            AppColors.background,
          ],
          stops: [0, .42, 1],
        ),
      ),
      child: SizedBox(
        height: 58,
        child: FilledButton(
          key: const ValueKey('setup-continue'),
          onPressed: enabled ? onTap : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.onAccent,
            disabledBackgroundColor: AppColors.surfaceHigh,
            disabledForegroundColor: AppColors.muted,
          ),
          child: loading
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    color: AppColors.onAccent,
                    strokeWidth: 2.2,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 19),
                  ],
                ),
        ),
      ),
    );
  }
}
