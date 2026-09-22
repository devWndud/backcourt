import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/court_ranking_card.dart';
import '../widgets/media_gallery.dart';
import 'notifications_sheet.dart';
import 'review_sheet.dart';

typedef UserLocationLoader = Future<LatLng> Function();
typedef MapControllerReady = void Function(MapLibreMapController controller);

enum _CourtFilter { nearby }

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.useRealMap = true,
    this.active = true,
    this.userLocationLoader,
    this.onMapControllerReady,
    this.repository,
    this.initialCourt,
    this.onCourtSelected,
    this.pickerMode = false,
    this.onPickerClose,
    this.onNotificationOpen,
  });

  final bool useRealMap;
  final bool active;
  final UserLocationLoader? userLocationLoader;
  final MapControllerReady? onMapControllerReady;
  final BackcourtRepository? repository;
  final CourtSummary? initialCourt;
  final ValueChanged<CourtSummary>? onCourtSelected;
  final bool pickerMode;
  final VoidCallback? onPickerClose;
  final ValueChanged<AppNotificationRecord>? onNotificationOpen;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _nameRequestsKey = 'court_name_change_requests_v1';
  static const _clusterStageMaxZooms = <double>[7.5, 9, 10.5];
  static const _clusterCellSizes = <double>[1.2, .7, .35];
  static const _initialZoom =
      int.fromEnvironment('BACKCOURT_INITIAL_ZOOM_X10', defaultValue: 139) / 10;
  static const _initialCamera = CameraPosition(
    target: LatLng(37.5240, 126.9349),
    zoom: _initialZoom,
  );
  static String get _styleUrl => AppColors.isLight
      ? 'https://tiles.openfreemap.org/styles/positron'
      : 'https://tiles.openfreemap.org/styles/dark';

  LatLng get _initialTarget => initialCourtPosition(widget.initialCourt);

  CameraPosition get _startingCamera => CameraPosition(
    target: _initialTarget,
    zoom: widget.initialCourt == null ? _initialCamera.zoom : 15.2,
  );

  static LatLng initialCourtPosition(CourtSummary? court) => court == null
      ? _initialCamera.target
      : LatLng(court.latitude, court.longitude);

  int? _selectedCourt;
  bool _mapReady = false;
  bool _locating = false;
  int _osmCourtCount = 0;
  LatLng? _currentLocation;
  _OsmCourt? _selectedOsmCourt;
  Circle? _selectedCourtCircle;
  Circle? _userLocationCircle;
  List<Circle> _displayedCourtCircles = const [];
  List<Symbol> _displayedClusterLabels = const [];
  List<_CourtHitTarget> _courtHitTargets = const [];
  int? _markerStage;
  bool _refreshingMarkers = false;
  bool _cameraMoving = false;
  int? _pendingMarkerStage;
  bool _pendingMarkerForce = false;
  MapLibreMapController? _mapController;
  final Map<String, _OsmCourt> _osmCourts = {};
  final TextEditingController _searchController = TextEditingController();
  final DraggableScrollableController _courtSheetController =
      DraggableScrollableController();
  final Set<_CourtFilter> _activeFilters = {};
  final Map<String, String> _databaseCourtNames = {};
  final Map<String, CourtOverride> _courtOverrides = {};
  final Map<String, _LiveMarkerSummary> _liveCourtSummaries = {};
  StreamSubscription<Map<String, CourtOverride>>? _courtNameSubscription;
  StreamSubscription<List<LiveCourtStatus>>? _liveCourtSubscription;
  Completer<void>? _initialCourtNamesReady;
  SharedPreferencesAsync? _preferences;
  Timer? _searchDebounce;
  String _searchQuery = '';

  static const _courts = [
    ('한강 시민공원 농구장', '240m', '4.8', '여의도 · 야외 · 무료', LatLng(37.5272, 126.9347)),
    ('여의도공원 농구코트', '680m', '4.6', '여의도 · 야외 · 무료', LatLng(37.5260, 126.9228)),
    ('샛강 다목적 코트', '1.1km', '4.3', '영등포 · 야외 · 무료', LatLng(37.5188, 126.9288)),
  ];

  @override
  void initState() {
    super.initState();
    _subscribeToCourtNames();
    _subscribeToLiveCourts();
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _setMapRendering(widget.active);
    }
    if (oldWidget.repository != widget.repository) {
      _subscribeToCourtNames();
      _subscribeToLiveCourts();
    }
    if (oldWidget.initialCourt?.id != widget.initialCourt?.id &&
        widget.initialCourt != null) {
      unawaited(
        _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(_initialTarget, 15.2),
            ) ??
            Future<void>.value(),
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    unawaited(_courtNameSubscription?.cancel());
    unawaited(_liveCourtSubscription?.cancel());
    _searchController.dispose();
    _courtSheetController.dispose();
    _mapController?.onCircleTapped.remove(_onCircleTapped);
    _mapController?.onSymbolTapped.remove(_onSymbolTapped);
    super.dispose();
  }

  void _subscribeToCourtNames() {
    unawaited(_courtNameSubscription?.cancel());
    _courtNameSubscription = null;
    _databaseCourtNames.clear();
    final repository = widget.repository;
    if (repository == null) {
      _initialCourtNamesReady = null;
      return;
    }
    final ready = _initialCourtNamesReady = Completer<void>();
    _courtNameSubscription = repository.watchCourtOverrides().listen(
      (overrides) {
        _courtOverrides
          ..clear()
          ..addAll(overrides);
        _databaseCourtNames
          ..clear()
          ..addEntries(
            overrides.entries
                .where((entry) => entry.value.name.isNotEmpty)
                .map((entry) => MapEntry(entry.key, entry.value.name)),
          );
        _applyCourtOverridesToIndex();
        if (!ready.isCompleted) ready.complete();
        if (!mounted) return;
        setState(() {});
        final selected = _selectedOsmCourt;
        if (selected != null) _notifyOsmCourtSelected(selected);
        _refreshFilteredMarkers();
      },
      onError: (_) {
        if (!ready.isCompleted) ready.complete();
      },
    );
  }

  void _subscribeToLiveCourts() {
    unawaited(_liveCourtSubscription?.cancel());
    _liveCourtSubscription = null;
    _liveCourtSummaries.clear();
    final repository = widget.repository;
    if (repository == null) return;
    _liveCourtSubscription = repository.watchLiveCourtStatuses().listen((
      statuses,
    ) {
      final grouped = <String, List<LiveCourtStatus>>{};
      for (final status in statuses.where((status) => status.isActive)) {
        grouped.putIfAbsent(status.courtId, () => []).add(status);
      }
      _liveCourtSummaries
        ..clear()
        ..addEntries(
          grouped.entries.map(
            (entry) => MapEntry(
              entry.key,
              _LiveMarkerSummary.fromStatuses(entry.value),
            ),
          ),
        );
      if (!mounted) return;
      setState(() {});
      final zoom = _mapController?.cameraPosition?.zoom;
      if (_mapReady && zoom != null) {
        unawaited(_refreshCourtMarkers(zoom, force: true));
      }
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    widget.onMapControllerReady?.call(controller);
    controller.onCircleTapped.add(_onCircleTapped);
    controller.onSymbolTapped.add(_onSymbolTapped);
    if (!widget.active) {
      _setMapRendering(false);
    }
  }

  Future<void> _onStyleLoaded() async {
    final controller = _mapController;
    if (controller == null) return;
    _selectedCourtCircle = null;
    _userLocationCircle = null;
    _displayedCourtCircles = const [];
    _displayedClusterLabels = const [];
    _courtHitTargets = const [];
    _markerStage = null;

    await controller.addFill(
      FillOptions(
        geometry: [_circlePolygon(_initialTarget, 100)],
        fillColor: '#FF633F',
        fillOpacity: .12,
        fillOutlineColor: '#FF633F',
      ),
    );

    final rawGeoJson = await rootBundle.loadString(
      'assets/data/korea_basketball_courts.geojson',
    );
    final geoJson = jsonDecode(rawGeoJson) as Map<String, dynamic>;
    _indexOsmCourts(geoJson);
    _applyCourtOverridesToIndex();

    final courtNamesReady = _initialCourtNamesReady;
    if (courtNamesReady != null && !courtNamesReady.isCompleted) {
      try {
        await courtNamesReady.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Keep the bundled catalog responsive when Firestore is unavailable.
      }
    }

    await _refreshCourtMarkers(
      _mapController?.cameraPosition?.zoom ?? _startingCamera.zoom,
      force: true,
    );
    final currentLocation = _currentLocation;
    if (currentLocation != null) {
      await _renderUserLocation(currentLocation);
    }
    if (mounted) {
      setState(() => _mapReady = true);
    }
  }

  void _indexOsmCourts(Map<String, dynamic> geoJson) {
    _osmCourts.clear();
    final features = geoJson['features'] as List<dynamic>;
    for (final rawFeature in features) {
      final feature = rawFeature as Map<String, dynamic>;
      final court = _OsmCourt.fromFeature(feature);
      _osmCourts[court.featureId] = court;
    }
    _osmCourtCount = _osmCourts.length;
  }

  void _applyCourtOverridesToIndex() {
    _osmCourts.removeWhere((id, _) => id.startsWith('reported_'));
    for (final override in _courtOverrides.values) {
      if (!override.isCustom || override.isHidden) continue;
      final latitude = override.latitude;
      final longitude = override.longitude;
      if (latitude == null || longitude == null) continue;
      _osmCourts[override.id] = _OsmCourt(
        featureId: override.id,
        name: override.name.isEmpty ? '제보된 농구장' : override.name,
        position: LatLng(latitude, longitude),
        detail: '운영자 확인',
        facts: const ['제보 등록'],
        address: override.address,
      );
    }
    _osmCourtCount = _osmCourts.values
        .where(
          (court) => !(_courtOverrides[court.featureId]?.isHidden ?? false),
        )
        .length;
  }

  String _displayNameFor(_OsmCourt court) =>
      _databaseCourtNames[court.featureId] ?? court.name;

  List<_OsmCourt> _matchingCourts() {
    final query = _searchQuery.trim().toLowerCase();
    final origin = _currentLocation;
    return _osmCourts.values
        .where((court) {
          if (_courtOverrides[court.featureId]?.isHidden == true) return false;
          final databaseName = _databaseCourtNames[court.featureId];
          if (query.isNotEmpty &&
              !court.searchText.contains(query) &&
              !(databaseName?.toLowerCase().contains(query) ?? false)) {
            return false;
          }
          if (_activeFilters.contains(_CourtFilter.nearby)) {
            if (origin == null) return false;
            final meters = Geolocator.distanceBetween(
              origin.latitude,
              origin.longitude,
              court.position.latitude,
              court.position.longitude,
            );
            if (meters > 5000) return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = value;
      _selectedCourt = null;
      _selectedOsmCourt = null;
    });
    unawaited(_restoreSelectedCircle());
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) _refreshFilteredMarkers();
    });
  }

  Future<void> _submitSearch(String _) async {
    FocusScope.of(context).unfocus();
    final matches = _matchingCourts();
    if (matches.isEmpty) {
      _showLocationMessage('조건에 맞는 코트를 찾지 못했어요.');
      return;
    }
    final court = matches.first;
    setState(() {
      _selectedCourt = null;
      _selectedOsmCourt = court;
    });
    _notifyOsmCourtSelected(court);
    _collapseCourtSheet();
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(court.position, 14.5),
    );
  }

  Future<void> _toggleFilter(_CourtFilter filter) async {
    final enabling = !_activeFilters.contains(filter);
    if (filter == _CourtFilter.nearby && enabling && _currentLocation == null) {
      await _moveToMyLocation();
      if (_currentLocation == null) return;
    }
    if (!mounted) return;
    setState(() {
      if (enabling) {
        _activeFilters.add(filter);
      } else {
        _activeFilters.remove(filter);
      }
      _selectedCourt = null;
      _selectedOsmCourt = null;
    });
    await _restoreSelectedCircle();
    _refreshFilteredMarkers();
  }

  Future<void> _openNewCourtReport() async {
    final repository = widget.repository;
    if (repository == null) {
      _showLocationMessage('로그인 후 코트를 제보할 수 있어요.');
      return;
    }
    if (_currentLocation == null) await _moveToMyLocation();
    final location = _currentLocation;
    if (!mounted || location == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NewCourtReportSheet(
        onSubmit: (name, reason) => repository.submitNewCourtReport(
          name: name,
          reason: reason,
          latitude: location.latitude,
          longitude: location.longitude,
        ),
      ),
    );
    if (saved == true && mounted) {
      _showLocationMessage('새 코트 제보를 보냈어요.');
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _refreshFilteredMarkers() {
    final zoom = _mapController?.cameraPosition?.zoom;
    if (_mapReady && zoom != null) {
      unawaited(_refreshCourtMarkers(zoom, force: true));
    }
  }

  Future<void> _restoreSelectedCircle() async {
    final selectedCircle = _selectedCourtCircle;
    _selectedCourtCircle = null;
    if (selectedCircle != null) {
      await _mapController?.updateCircle(
        selectedCircle,
        _courtCircleStyle(selectedCircle.data?['feature_id'] as String?),
      );
    }
  }

  void _collapseCourtSheet() {
    final collapsedExtent = _sheetLayout(context).collapsedExtent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_courtSheetController.isAttached) {
        unawaited(
          _courtSheetController.animateTo(
            collapsedExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  void _expandCourtSheet() {
    if (!_courtSheetController.isAttached) return;
    unawaited(
      _courtSheetController.animateTo(
        _sheetLayout(context).expandedExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _closeCourtSheet() async {
    await _restoreSelectedCircle();
    if (!mounted) return;
    setState(() {
      _selectedCourt = null;
      _selectedOsmCourt = null;
    });
  }

  Future<void> _openNameChangeRequest(_CourtSheetData court) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CourtNameRequestSheet(
        currentName: court.name,
        onSubmit: (type, requestedName, reason) => _saveCourtReport(
          court: court,
          type: type,
          requestedName: requestedName,
          reason: reason,
        ),
      ),
    );
    if (saved == true && mounted) {
      _showLocationMessage(
        widget.repository == null
            ? '코트 정보 제보를 기기에 저장했어요.'
            : '코트 정보 제보를 운영자에게 전송했어요.',
      );
    }
  }

  Future<void> _saveCourtReport({
    required _CourtSheetData court,
    required CourtReportType type,
    required String? requestedName,
    required String reason,
  }) async {
    final repository = widget.repository;
    if (repository != null) {
      await repository.submitCourtReport(
        court: court.toSummary(),
        type: type,
        requestedName: requestedName,
        reason: reason,
      );
      return;
    }
    List<dynamic> requests = [];
    final preferences = _preferences ??= SharedPreferencesAsync();
    try {
      final raw = await preferences.getString(_nameRequestsKey);
      if (raw != null) requests = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      requests = [];
    }
    requests.add({
      'court_id': court.id,
      'current_name': court.name,
      'report_type': type.value,
      'requested_name': requestedName,
      'reason': reason,
      'latitude': court.coordinates.latitude,
      'longitude': court.coordinates.longitude,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await preferences.setString(_nameRequestsKey, jsonEncode(requests));
  }

  void _onCameraIdle() {
    _cameraMoving = false;
    final zoom = _mapController?.cameraPosition?.zoom;
    if (!_mapReady || zoom == null) return;
    unawaited(_refreshCourtMarkers(zoom, force: true));
  }

  void _onCameraMove(CameraPosition position) {
    _cameraMoving = true;
    if (_courtHitTargets.isNotEmpty && mounted) {
      setState(() => _courtHitTargets = const []);
    }
    if (!_mapReady || _markerStageForZoom(position.zoom) == _markerStage) {
      return;
    }
    unawaited(_refreshCourtMarkers(position.zoom));
  }

  int _markerStageForZoom(double zoom) {
    for (var index = 0; index < _clusterStageMaxZooms.length; index++) {
      if (zoom < _clusterStageMaxZooms[index]) return index;
    }
    return _clusterStageMaxZooms.length;
  }

  Future<void> _refreshCourtMarkers(double zoom, {bool force = false}) async {
    final requestedStage = _markerStageForZoom(zoom);
    if (!force && requestedStage == _markerStage) return;
    _pendingMarkerStage = requestedStage;
    _pendingMarkerForce = _pendingMarkerForce || force;
    if (_refreshingMarkers) return;

    _refreshingMarkers = true;
    try {
      while (_pendingMarkerStage != null) {
        final stage = _pendingMarkerStage!;
        final shouldForce = _pendingMarkerForce;
        _pendingMarkerStage = null;
        _pendingMarkerForce = false;
        if (shouldForce || stage != _markerStage) {
          await _replaceCourtMarkers(stage);
        }
      }
    } finally {
      _refreshingMarkers = false;
    }
  }

  Future<void> _replaceCourtMarkers(int stage) async {
    final controller = _mapController;
    if (controller == null) return;

    final matchingCourts = _matchingCourts();
    final allMarkers = stage == _clusterCellSizes.length
        ? [
            for (final court in matchingCourts)
              _CourtMarker(
                position: court.position,
                count: 1,
                courtId: court.featureId,
              ),
          ]
        : _clusterCourts(
            courts: matchingCourts,
            cellSize: _clusterCellSizes[stage],
            targetZoom: _clusterStageMaxZooms[stage] + .35,
          );
    final visibleBounds = await controller.getVisibleRegion();
    final markers = allMarkers
        .where((marker) => _isNearVisibleRegion(marker.position, visibleBounds))
        .toList(growable: false);

    final previousMarkers = _displayedCourtCircles;
    final previousLabels = _displayedClusterLabels;
    if (previousLabels.isNotEmpty) {
      await controller.removeSymbols(previousLabels);
    }
    if (previousMarkers.isNotEmpty) {
      await controller.removeCircles(previousMarkers);
    }
    _displayedCourtCircles = const [];
    _displayedClusterLabels = const [];
    if (_courtHitTargets.isNotEmpty && mounted) {
      setState(() => _courtHitTargets = const []);
    }
    _selectedCourtCircle = null;

    if (markers.isNotEmpty) {
      _displayedCourtCircles = await controller.addCircles(
        [
          for (final marker in markers)
            CircleOptions(
              geometry: marker.position,
              circleRadius: marker.courtId == _selectedOsmCourt?.featureId
                  ? 12
                  : marker.courtId == null
                  ? _clusterRadius(marker.count)
                  : 8,
              circleColor:
                  marker.courtId != null &&
                      _liveCourtSummaries.containsKey(marker.courtId)
                  ? '#BAF86A'
                  : '#FF633F',
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: marker.courtId == _selectedOsmCourt?.featureId
                  ? 3
                  : marker.courtId == null
                  ? 2.5
                  : 2,
            ),
        ],
        [
          for (final marker in markers)
            if (marker.courtId != null)
              {'kind': 'court', 'feature_id': marker.courtId!}
            else
              {
                'kind': 'cluster',
                'count': marker.count,
                'target_zoom': marker.targetZoom,
              },
        ],
      );
      final selectedId = _selectedOsmCourt?.featureId;
      if (selectedId != null) {
        for (final circle in _displayedCourtCircles) {
          if (circle.data?['feature_id'] == selectedId) {
            _selectedCourtCircle = circle;
            break;
          }
        }
      }
    }
    final clusters = markers.where((marker) => marker.courtId == null).toList();
    if (clusters.isNotEmpty) {
      _displayedClusterLabels = await controller.addSymbols(
        [
          for (final cluster in clusters)
            SymbolOptions(
              geometry: cluster.position,
              textField: '${cluster.count}',
              textSize: 12,
              textColor: '#FFFFFF',
              textHaloColor: '#FF633F',
              textHaloWidth: 1,
            ),
        ],
        [
          for (final cluster in clusters)
            {
              'kind': 'cluster',
              'count': cluster.count,
              'target_zoom': cluster.targetZoom,
            },
        ],
      );
    }
    _markerStage = stage;
    if (stage == _clusterCellSizes.length && !_cameraMoving) {
      await _updateCourtHitTargets();
    }
  }

  Future<void> _updateCourtHitTargets() async {
    final controller = _mapController;
    if (controller == null) return;
    final courts = _displayedCourtCircles
        .where((circle) => circle.data?['kind'] == 'court')
        .toList(growable: false);
    if (courts.isEmpty) return;
    final screenPositions = await controller.toScreenLocationBatch([
      for (final court in courts) court.options.geometry!,
    ]);
    if (!mounted || _cameraMoving) return;
    final mapSize = MediaQuery.sizeOf(context);
    final targets = <_CourtHitTarget>[];
    for (var index = 0; index < courts.length; index++) {
      final point = screenPositions[index];
      if (point.x < -24 ||
          point.x > mapSize.width + 24 ||
          point.y < -24 ||
          point.y > mapSize.height + 24) {
        continue;
      }
      targets.add(
        _CourtHitTarget(
          circle: courts[index],
          position: Offset(point.x.toDouble(), point.y.toDouble()),
        ),
      );
    }
    setState(() => _courtHitTargets = targets);
  }

  bool _isNearVisibleRegion(LatLng position, LatLngBounds bounds) {
    final latitudePadding =
        (bounds.northeast.latitude - bounds.southwest.latitude) * .5;
    final longitudePadding =
        (bounds.northeast.longitude - bounds.southwest.longitude).abs() * .5;
    return position.latitude >= bounds.southwest.latitude - latitudePadding &&
        position.latitude <= bounds.northeast.latitude + latitudePadding &&
        position.longitude >= bounds.southwest.longitude - longitudePadding &&
        position.longitude <= bounds.northeast.longitude + longitudePadding;
  }

  List<_CourtMarker> _clusterCourts({
    required Iterable<_OsmCourt> courts,
    required double cellSize,
    required double targetZoom,
  }) {
    final groups = <String, _ClusterAccumulator>{};
    for (final court in courts) {
      final column = (court.position.longitude / cellSize).floor();
      final row = (court.position.latitude / cellSize).floor();
      groups
          .putIfAbsent('$column:$row', _ClusterAccumulator.new)
          .add(court.position);
    }
    return [
      for (final group in groups.values)
        _CourtMarker(
          position: group.center,
          count: group.count,
          targetZoom: targetZoom,
        ),
    ];
  }

  double _clusterRadius(int count) {
    return (9 + math.log(count + 1) * 2.8).clamp(10, 27).toDouble();
  }

  List<LatLng> _circlePolygon(LatLng center, double radiusMeters) {
    const earthRadius = 6378137.0;
    final latitudeRadians = center.latitude * math.pi / 180;
    return [
      for (var step = 0; step <= 48; step++)
        LatLng(
          center.latitude +
              (radiusMeters / earthRadius) *
                  math.sin(step * 2 * math.pi / 48) *
                  180 /
                  math.pi,
          center.longitude +
              (radiusMeters / earthRadius) *
                  math.cos(step * 2 * math.pi / 48) *
                  180 /
                  math.pi /
                  math.cos(latitudeRadians),
        ),
    ];
  }

  Future<void> _onCircleTapped(Circle circle) async {
    final controller = _mapController;
    if (controller == null) return;
    if (circle.data?['kind'] == 'cluster') {
      await _openCluster(circle.options.geometry, circle.data);
      return;
    }
    if (circle.data?['kind'] != 'court') return;
    final court = _osmCourts[circle.data?['feature_id']];
    if (court == null || !mounted) return;

    final previous = _selectedCourtCircle;
    if (previous != null && previous != circle) {
      await controller.updateCircle(
        previous,
        _courtCircleStyle(previous.data?['feature_id'] as String?),
      );
    }
    await controller.updateCircle(
      circle,
      const CircleOptions(
        circleRadius: 12,
        circleColor: '#FF633F',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
    );
    _selectedCourtCircle = circle;
    setState(() {
      _selectedCourt = null;
      _selectedOsmCourt = court;
    });
    _notifyOsmCourtSelected(court);
    _collapseCourtSheet();
  }

  Future<void> _onMapTapped(math.Point<double> tapPoint, LatLng _) async {
    if (_markerStage != _clusterCellSizes.length) return;
    final controller = _mapController;
    if (controller == null) return;

    final courts = _displayedCourtCircles
        .where((circle) => circle.data?['kind'] == 'court')
        .toList(growable: false);
    if (courts.isEmpty) return;
    final positions = await controller.toScreenLocationBatch([
      for (final court in courts) court.options.geometry!,
    ]);

    Circle? nearestCourt;
    var nearestDistance = double.infinity;
    for (var index = 0; index < courts.length; index++) {
      final markerPoint = positions[index];
      final distance = math.sqrt(
        math.pow(markerPoint.x - tapPoint.x, 2) +
            math.pow(markerPoint.y - tapPoint.y, 2),
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestCourt = courts[index];
      }
    }
    if (nearestCourt != null &&
        nearestCourt != _selectedCourtCircle &&
        nearestDistance <= 32) {
      await _onCircleTapped(nearestCourt);
    }
  }

  Future<void> _onSymbolTapped(Symbol symbol) async {
    if (symbol.data?['kind'] == 'cluster') {
      await _openCluster(symbol.options.geometry, symbol.data);
      return;
    }
  }

  Future<void> _openCluster(
    LatLng? position,
    Map<String, dynamic>? data,
  ) async {
    final targetZoom = data?['target_zoom'];
    if (targetZoom is! num || position == null) return;
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, targetZoom.toDouble()),
    );
  }

  CircleOptions _courtCircleStyle(String? courtId) => CircleOptions(
    circleRadius: 8,
    circleColor: _liveCourtSummaries.containsKey(courtId)
        ? '#BAF86A'
        : '#FF633F',
    circleStrokeColor: '#FFFFFF',
    circleStrokeWidth: 2,
  );

  Future<void> _setMapRendering(bool active) async {
    final controller = _mapController;
    if (controller == null) return;
    if (active) {
      await controller.resumeMap();
    } else {
      await controller.pauseMap();
    }
  }

  void _selectCourt(int index, {bool moveCamera = true}) {
    setState(() {
      _selectedCourt = index;
      _selectedOsmCourt = null;
    });
    final sample = _courts[index];
    if (!widget.pickerMode) {
      widget.onCourtSelected?.call(
        CourtSummary(
          id: 'sample-$index',
          name: sample.$1,
          latitude: sample.$5.latitude,
          longitude: sample.$5.longitude,
          facts: const ['야외', '무료'],
        ),
      );
    }
    final controller = _mapController;
    final selectedCircle = _selectedCourtCircle;
    if (controller != null && selectedCircle != null) {
      controller.updateCircle(
        selectedCircle,
        _courtCircleStyle(selectedCircle.data?['feature_id'] as String?),
      );
      _selectedCourtCircle = null;
    }
    if (moveCamera) {
      controller?.animateCamera(
        CameraUpdate.newLatLngZoom(_courts[index].$5, 15.2),
      );
    }
    _collapseCourtSheet();
  }

  void _notifyOsmCourtSelected(_OsmCourt court) {
    if (widget.pickerMode) return;
    widget.onCourtSelected?.call(
      CourtSummary(
        id: court.featureId,
        name: _displayNameFor(court),
        latitude: court.position.latitude,
        longitude: court.position.longitude,
        address: court.address,
        facts: court.facts,
      ),
    );
  }

  Future<void> _openReview(_CourtSheetData court) async {
    final repository = widget.repository;
    if (repository == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ReviewComposerSheet(repository: repository, court: court.toSummary()),
    );
    if (saved == true) _showLocationMessage('리뷰를 등록했어요.');
  }

  Future<void> _addReviewPhotos(ReviewRecord review) async {
    final repository = widget.repository;
    if (repository == null) return;
    final images = await ImagePicker().pickMultiImage(
      imageQuality: 88,
      maxWidth: 2160,
      maxHeight: 2160,
      limit: 6,
    );
    if (images.isEmpty) return;
    try {
      await repository.addReviewMedia(review: review, images: images);
      _showLocationMessage('리뷰에 사진을 추가했어요.');
    } catch (error) {
      _showLocationMessage(
        error is BackcourtException ? error.message : '사진을 추가하지 못했어요.',
      );
    }
  }

  Future<void> _moveToMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);

    try {
      final target = widget.userLocationLoader == null
          ? await _loadDeviceLocation()
          : await widget.userLocationLoader!();
      if (target == null) return;
      if (!mounted) return;
      setState(() => _currentLocation = target);
      if (_mapReady) {
        await _renderUserLocation(target);
      }
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(target, 15.5),
      );
    } on TimeoutException {
      _showLocationMessage('현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해주세요.');
    } catch (_) {
      _showLocationMessage('위치를 가져오는 중 문제가 발생했어요.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<LatLng?> _loadDeviceLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showLocationMessage(
        '위치 서비스가 꺼져 있어요.',
        actionLabel: '설정',
        onAction: Geolocator.openLocationSettings,
      );
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      _showLocationMessage(
        '설정에서 빽코트의 위치 권한을 허용해주세요.',
        actionLabel: '설정',
        onAction: Geolocator.openAppSettings,
      );
      return null;
    }
    if (permission == LocationPermission.denied) {
      _showLocationMessage('내 위치로 이동하려면 위치 권한이 필요해요.');
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return LatLng(position.latitude, position.longitude);
  }

  Future<void> _renderUserLocation(LatLng location) async {
    final controller = _mapController;
    if (controller == null) return;
    final currentCircle = _userLocationCircle;
    if (currentCircle != null) {
      await controller.updateCircle(
        currentCircle,
        CircleOptions(geometry: location),
      );
      return;
    }
    _userLocationCircle = await controller.addCircle(
      CircleOptions(
        geometry: location,
        circleRadius: 9,
        circleColor: '#258CFF',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
      const {'kind': 'user_location'},
    );
  }

  void _showLocationMessage(
    String message, {
    String? actionLabel,
    Future<bool> Function()? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(label: actionLabel, onPressed: () => onAction()),
        ),
      );
  }

  String _distanceTo(LatLng destination) {
    final origin = _currentLocation ?? _initialTarget;
    final meters = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  _CourtSheetLayout _sheetLayout(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomClearance = math.max(8.0, mediaQuery.padding.bottom);
    final fullHeight = math.max(1.0, mediaQuery.size.height);
    final visibleHeight = math.max(1.0, fullHeight - bottomClearance);
    final collapsedVisibleHeight = visibleHeight * .14;
    final expandedVisibleHeight = visibleHeight * .46;
    return _CourtSheetLayout(
      bottomClearance: bottomClearance,
      collapsedVisibleHeight: collapsedVisibleHeight,
      collapsedExtent: (collapsedVisibleHeight + bottomClearance) / fullHeight,
      expandedExtent: (expandedVisibleHeight + bottomClearance) / fullHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final osmCourt = _selectedOsmCourt;
    final sampleIndex = _selectedCourt;
    final selectedCourt = osmCourt != null
        ? _CourtSheetData(
            id: osmCourt.featureId,
            name: _displayNameFor(osmCourt),
            distance: _distanceTo(osmCourt.position),
            summary: osmCourt.detail,
            facts: osmCourt.facts,
            address: osmCourt.address,
            operatorName: osmCourt.operatorName,
            coordinates: osmCourt.position,
          )
        : sampleIndex != null
        ? _CourtSheetData(
            id: 'sample-$sampleIndex',
            name: _courts[sampleIndex].$1,
            distance: _courts[sampleIndex].$2,
            summary: _courts[sampleIndex].$4,
            facts: const ['야외', '무료'],
            coordinates: _courts[sampleIndex].$5,
          )
        : null;
    final filtersApplied =
        _searchQuery.trim().isNotEmpty || _activeFilters.isNotEmpty;
    final matchingCourtCount = widget.useRealMap
        ? _matchingCourts().length
        : _courts.length;
    final sheetLayout = _sheetLayout(context);
    final bottomNavClearance = sheetLayout.bottomClearance;
    final floatingControlsBottom = selectedCourt == null
        ? bottomNavClearance + 12
        : widget.pickerMode
        ? bottomNavClearance + 112
        : bottomNavClearance + sheetLayout.collapsedVisibleHeight + 12;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.useRealMap)
          MapLibreMap(
            key: ValueKey(_styleUrl),
            initialCameraPosition: _startingCamera,
            styleString: _styleUrl,
            minMaxZoomPreference: const MinMaxZoomPreference(6, 19),
            trackCameraPosition: true,
            featureTapsTriggersMapClick: true,
            compassEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            logoEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
            // 저작권 문구는 별도 표시하므로 기본 정보 버튼은 하단 내비게이션
            // 뒤로 완전히 넣어 화면 가장자리에 파란 테두리가 보이지 않게 한다.
            attributionButtonMargins: const math.Point<double>(20, 0),
            annotationOrder: const [
              AnnotationType.fill,
              AnnotationType.circle,
              AnnotationType.symbol,
            ],
            annotationConsumeTapEvents: const [
              AnnotationType.circle,
              AnnotationType.symbol,
            ],
            foregroundLoadColor: AppColors.background,
            onMapCreated: _onMapCreated,
            onMapClick: _onMapTapped,
            onStyleLoadedCallback: _onStyleLoaded,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
          )
        else ...[
          ColoredBox(color: AppColors.background),
          CustomPaint(painter: _MapPreviewPainter(light: AppColors.isLight)),
          _MapMarker(
            leftFactor: .55,
            topFactor: .35,
            selected: sampleIndex == 0,
            label: '한강',
            onTap: () => _selectCourt(0),
          ),
          _MapMarker(
            leftFactor: .22,
            topFactor: .47,
            selected: sampleIndex == 1,
            label: '여의도',
            onTap: () => _selectCourt(1),
          ),
          _MapMarker(
            leftFactor: .70,
            topFactor: .56,
            selected: sampleIndex == 2,
            label: '샛강',
            onTap: () => _selectCourt(2),
          ),
        ],
        if (widget.useRealMap && !_mapReady)
          const IgnorePointer(
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 2.5,
              ),
            ),
          ),
        if (widget.useRealMap)
          for (final target in _courtHitTargets)
            _CourtMarkerOverlay(
              key: ValueKey('court-hit-${target.circle.id}'),
              target: target,
              live: _liveCourtSummaries[target.courtId],
              selected: target.circle == _selectedCourtCircle,
              onTap: () => _onCircleTapped(target.circle),
            ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    if (widget.pickerMode) ...[
                      IconButton(
                        key: const ValueKey('map-picker-back'),
                        onPressed: widget.onPickerClose,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surface.withValues(
                            alpha: .92,
                          ),
                          foregroundColor: AppColors.text,
                        ),
                        icon: Icon(Icons.arrow_back_rounded),
                      ),
                      SizedBox(width: 10),
                      Text(
                        '홈코트 선택',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.6,
                        ),
                      ),
                    ] else
                      const NmLogo(),
                    const Spacer(),
                    if (!widget.pickerMode)
                      NotificationBell(
                        repository: widget.repository,
                        onOpen: widget.onNotificationOpen,
                      ),
                  ],
                ),
                SizedBox(height: 16),
                TextField(
                  key: const ValueKey('court-search-field'),
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearchChanged,
                  onSubmitted: _submitSearch,
                  decoration: InputDecoration(
                    hintText: '코트 이름, 주소, 운영자로 검색',
                    prefixIcon: Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('clear-court-search'),
                            tooltip: '검색어 지우기',
                            onPressed: _clearSearch,
                            icon: Icon(
                              Icons.close_rounded,
                              color: AppColors.text,
                            ),
                          ),
                  ),
                ),
                SizedBox(height: 12),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FilterChip(
                        key: const ValueKey('filter-nearby'),
                        label: '내 주변 5km',
                        selected: _activeFilters.contains(_CourtFilter.nearby),
                        onTap: () => _toggleFilter(_CourtFilter.nearby),
                      ),
                      SizedBox(width: 8),
                      _FilterChip(
                        key: const ValueKey('report-new-court'),
                        label: '코트 제보',
                        selected: false,
                        onTap: _openNewCourtReport,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.useRealMap) ...[
          Positioned(
            left: 18,
            bottom: selectedCourt == null
                ? bottomNavClearance + 42
                : floatingControlsBottom,
            child: _CourtCountBadge(
              courtCount: _osmCourtCount,
              matchingCourtCount: matchingCourtCount,
              filtered: filtersApplied,
            ),
          ),
          Positioned(
            left: 18,
            bottom: widget.pickerMode && selectedCourt != null
                ? bottomNavClearance + 106
                : bottomNavClearance + 3,
            child: const _MapCredits(),
          ),
        ],
        Positioned(
          right: 18,
          bottom: floatingControlsBottom,
          child: _LocationButton(
            loading: _locating && _currentLocation == null,
            active: _currentLocation != null,
            onTap: _moveToMyLocation,
          ),
        ),
        if (selectedCourt != null && widget.pickerMode)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomNavClearance + 10,
            child: _MapCourtPickerCard(
              court: selectedCourt,
              onConfirm: () =>
                  widget.onCourtSelected?.call(selectedCourt.toSummary()),
            ),
          ),
        if (selectedCourt != null && !widget.pickerMode)
          Positioned.fill(
            bottom: 0,
            child: DraggableScrollableSheet(
              key: const ValueKey('selected-court-sheet'),
              controller: _courtSheetController,
              initialChildSize: sheetLayout.collapsedExtent,
              minChildSize: sheetLayout.collapsedExtent,
              maxChildSize: sheetLayout.expandedExtent,
              snap: true,
              snapSizes: [
                sheetLayout.collapsedExtent,
                sheetLayout.expandedExtent,
              ],
              builder: (context, scrollController) => _CourtDetailSheet(
                court: selectedCourt,
                scrollController: scrollController,
                bottomContentInset: bottomNavClearance,
                onExpand: _expandCourtSheet,
                onClose: _closeCourtSheet,
                onRequestNameChange: () =>
                    _openNameChangeRequest(selectedCourt),
                repository: widget.repository,
                onWriteReview: () => _openReview(selectedCourt),
                onAddReviewPhotos: _addReviewPhotos,
              ),
            ),
          ),
      ],
    );
  }
}

class _MapCourtPickerCard extends StatelessWidget {
  const _MapCourtPickerCard({required this.court, required this.onConfirm});

  final _CourtSheetData court;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 13, 13),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .97),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.text.withValues(alpha: .09)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.sports_basketball_rounded,
              color: AppColors.accent,
              size: 21,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  court.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.35,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  court.address ?? court.distance,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 10),
          FilledButton(
            key: const ValueKey('map-court-confirm'),
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.text,
              minimumSize: const Size(84, 46),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text('선택'),
          ),
        ],
      ),
    );
  }
}

class _LiveMarkerSummary {
  const _LiveMarkerSummary({required this.playerCount});

  factory _LiveMarkerSummary.fromStatuses(List<LiveCourtStatus> statuses) =>
      _LiveMarkerSummary(
        playerCount: statuses
            .map((status) => status.playerCount)
            .fold<int>(0, math.max),
      );

  final int playerCount;
}

class _OsmCourt {
  const _OsmCourt({
    required this.featureId,
    required this.name,
    required this.position,
    required this.detail,
    required this.facts,
    this.address,
    this.operatorName,
    this.indoor,
    this.covered,
    this.fee,
    this.lit,
  });

  factory _OsmCourt.fromFeature(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;
    final properties = feature['properties'] as Map<String, dynamic>;
    String? read(String key) {
      final value = properties[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final osmType = read('osm_type') ?? 'feature';
    final osmId = (properties['osm_id'] as num?)?.toInt() ?? feature['id'];
    final sourceName = read('name');

    final address = read('address');
    final operatorName = read('operator');
    final indoor = read('indoor');
    final covered = read('covered');
    final fee = read('fee');
    final lit = read('lit');
    final facts = <String>[];
    if (indoor == 'yes') {
      facts.add('실내');
    } else if (covered == 'yes') {
      facts.add('지붕 있음');
    } else {
      facts.add('야외');
    }
    if (lit == 'yes') facts.add('조명 있음');
    if (lit == 'no') facts.add('조명 없음');
    if (fee == 'no') facts.add('무료');
    if (fee == 'yes') facts.add('유료');
    if (read('surface') case final surface?) {
      facts.add('바닥 ${_surfaceLabel(surface)}');
    }
    if (read('hoops') case final hoops?) facts.add('골대 $hoops개');
    if (read('opening_hours') case final hours?) facts.add('운영 $hours');

    final summary = facts.take(2).join(' · ');
    return _OsmCourt(
      featureId: 'osm_${osmType}_$osmId',
      name: _stableCourtName(sourceName, address),
      position: LatLng(
        (coordinates[1] as num).toDouble(),
        (coordinates[0] as num).toDouble(),
      ),
      detail: summary,
      facts: facts,
      address: address,
      operatorName: operatorName,
      indoor: indoor,
      covered: covered,
      fee: fee,
      lit: lit,
    );
  }

  static String _stableCourtName(String? sourceName, String? address) {
    if (sourceName != null && sourceName != '이름 없는 농구 코트') {
      return sourceName;
    }
    if (address != null) {
      for (final part in address.split(RegExp(r'\s+')).reversed) {
        if (RegExp(r'(동|읍|면|리|구|시|군)$').hasMatch(part)) {
          return '$part 농구장';
        }
      }
    }
    return '지역 농구장';
  }

  static String _surfaceLabel(String value) => switch (value) {
    'asphalt' => '아스팔트',
    'concrete' => '콘크리트',
    'paved' => '포장',
    'rubber' => '고무',
    'synthetic' => '합성',
    'wood' => '목재',
    _ => value,
  };

  final String featureId;
  final String name;
  final LatLng position;
  final String detail;
  final List<String> facts;
  final String? address;
  final String? operatorName;
  final String? indoor;
  final String? covered;
  final String? fee;
  final String? lit;

  bool get isOutdoor => indoor != 'yes' && covered != 'yes';

  String get searchText =>
      [name, address, operatorName].whereType<String>().join(' ').toLowerCase();
}

class _CourtSheetData {
  const _CourtSheetData({
    required this.id,
    required this.name,
    required this.distance,
    required this.summary,
    required this.facts,
    required this.coordinates,
    this.address,
    this.operatorName,
  });

  final String id;
  final String name;
  final String distance;
  final String summary;
  final List<String> facts;
  final LatLng coordinates;
  final String? address;
  final String? operatorName;

  CourtSummary toSummary() => CourtSummary(
    id: id,
    name: name,
    latitude: coordinates.latitude,
    longitude: coordinates.longitude,
    address: address,
    facts: facts,
  );
}

class _CourtMarker {
  const _CourtMarker({
    required this.position,
    required this.count,
    this.courtId,
    this.targetZoom,
  });

  final LatLng position;
  final int count;
  final String? courtId;
  final double? targetZoom;
}

class _CourtHitTarget {
  const _CourtHitTarget({required this.circle, required this.position});

  final Circle circle;
  final Offset position;

  String? get courtId => circle.data?['feature_id'] as String?;
}

class _CourtMarkerOverlay extends StatelessWidget {
  const _CourtMarkerOverlay({
    super.key,
    required this.target,
    required this.live,
    required this.selected,
    required this.onTap,
  });

  final _CourtHitTarget target;
  final _LiveMarkerSummary? live;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summary = live;
    if (summary == null) {
      return Positioned(
        left: target.position.dx - 24,
        top: target.position.dy - 24,
        width: 48,
        height: 48,
        child: Semantics(
          button: true,
          label: '코트 선택',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
          ),
        ),
      );
    }

    return Positioned(
      left: target.position.dx - 43,
      top: target.position.dy - 50,
      width: 86,
      height: 74,
      child: Semantics(
        button: true,
        label: 'LIVE ${summary.playerCount}명, 코트 선택',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: _LiveCourtMapMarker(
            playerCount: summary.playerCount,
            selected: selected,
          ),
        ),
      ),
    );
  }
}

class _LiveCourtMapMarker extends StatelessWidget {
  const _LiveCourtMapMarker({
    required this.playerCount,
    required this.selected,
  });

  final int playerCount;
  final bool selected;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.topCenter,
    children: [
      Positioned(
        top: 0,
        child: Container(
          height: 27,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: const Color(0xF2111111),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white.withValues(alpha: .2)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x38000000),
                blurRadius: 9,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFBAF86A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .65,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$playerCount명',
                style: const TextStyle(
                  color: Color(0xFFD8D8D8),
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
      const Positioned(
        top: 27,
        width: 2,
        height: 13,
        child: ColoredBox(color: Color(0xB3111111)),
      ),
      Positioned(
        top: 38,
        child: Container(
          width: 23,
          height: 23,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFF633F) : Colors.white,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x45000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFBAF86A),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    ],
  );
}

class _CourtSheetLayout {
  const _CourtSheetLayout({
    required this.bottomClearance,
    required this.collapsedVisibleHeight,
    required this.collapsedExtent,
    required this.expandedExtent,
  });

  final double bottomClearance;
  final double collapsedVisibleHeight;
  final double collapsedExtent;
  final double expandedExtent;
}

class _ClusterAccumulator {
  double _latitudeSum = 0;
  double _longitudeSum = 0;
  int count = 0;

  void add(LatLng position) {
    _latitudeSum += position.latitude;
    _longitudeSum += position.longitude;
    count++;
  }

  LatLng get center => LatLng(_latitudeSum / count, _longitudeSum / count);
}

class _CourtCountBadge extends StatelessWidget {
  const _CourtCountBadge({
    required this.courtCount,
    required this.matchingCourtCount,
    required this.filtered,
  });

  final int courtCount;
  final int matchingCourtCount;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        courtCount == 0
            ? '전국 코트 불러오는 중'
            : filtered
            ? '검색 결과 $matchingCourtCount개'
            : '전국 $courtCount개 코트',
        style: TextStyle(
          color: AppColors.text,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MapCredits extends StatelessWidget {
  const _MapCredits();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'OpenFreeMap © OpenMapTiles · OpenStreetMap · KOSTAT',
        style: TextStyle(color: AppColors.muted, fontSize: 11),
      ),
    );
  }
}

class _LocationButton extends StatelessWidget {
  const _LocationButton({
    required this.loading,
    required this.active,
    required this.onTap,
  });

  final bool loading;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '내 위치로 이동',
      child: Material(
        color: AppColors.text,
        shape: const CircleBorder(),
        child: InkWell(
          key: const ValueKey('my-location-button'),
          onTap: loading ? null : onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: loading
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        color: AppColors.inverseText,
                        strokeWidth: 2.2,
                      ),
                    )
                  : Icon(
                      active
                          ? Icons.gps_fixed_rounded
                          : Icons.my_location_rounded,
                      color: active ? AppColors.accent : AppColors.inverseText,
                      size: 21,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected
            ? AppColors.text
            : AppColors.surface.withValues(alpha: .9),
        shape: StadiumBorder(
          side: BorderSide(
            color: AppColors.text.withValues(alpha: selected ? 0 : .1),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.inverseText : AppColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({
    required this.leftFactor,
    required this.topFactor,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final double leftFactor;
  final double topFactor;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Positioned(
      left: size.width * leftFactor - 29,
      top: size.height * topFactor,
      child: GestureDetector(
        key: ValueKey('map-marker-$label'),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 13 : 10,
            vertical: selected ? 9 : 7,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.text,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sports_basketball_rounded,
                size: 15,
                color: selected ? AppColors.onAccent : AppColors.inverseText,
              ),
              if (selected) ...[
                SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.onAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CourtDetailSheet extends StatefulWidget {
  const _CourtDetailSheet({
    required this.court,
    required this.scrollController,
    required this.bottomContentInset,
    required this.onExpand,
    required this.onClose,
    required this.onRequestNameChange,
    required this.repository,
    required this.onWriteReview,
    required this.onAddReviewPhotos,
  });

  final _CourtSheetData court;
  final ScrollController scrollController;
  final double bottomContentInset;
  final VoidCallback onExpand;
  final Future<void> Function() onClose;
  final VoidCallback onRequestNameChange;
  final BackcourtRepository? repository;
  final VoidCallback onWriteReview;
  final ValueChanged<ReviewRecord> onAddReviewPhotos;

  @override
  State<_CourtDetailSheet> createState() => _CourtDetailSheetState();
}

class _CourtDetailSheetState extends State<_CourtDetailSheet> {
  bool _showRanking = false;
  bool _savingFavorite = false;

  Future<void> _toggleFavorite() async {
    final repository = widget.repository;
    if (repository == null || _savingFavorite) return;
    setState(() => _savingFavorite = true);
    try {
      final saved = await repository.toggleFavoriteCourt(
        widget.court.toSummary(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(saved ? '즐겨찾기에 저장' : '즐겨찾기에서 제거')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error is BackcourtException ? error.message : '저장 실패'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final court = widget.court;
    final repository = widget.repository;
    final facts = court.facts.take(3).toList(growable: false);
    return Material(
      key: const ValueKey('court-sheet-surface'),
      color: AppColors.surface,
      elevation: 20,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: AppColors.subtleBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          28 + widget.bottomContentInset,
        ),
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          SizedBox(height: 12),
          InkWell(
            onTap: widget.onExpand,
            borderRadius: BorderRadius.circular(18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.sports_basketball_rounded,
                    color: AppColors.text,
                    size: 22,
                  ),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.3,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        court.summary.isEmpty
                            ? court.distance
                            : '${court.distance} · ${court.summary}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (repository != null)
                  StreamBuilder<bool>(
                    stream: repository.watchIsFavoriteCourt(court.id),
                    builder: (context, snapshot) {
                      final saved = snapshot.data ?? false;
                      return IconButton(
                        key: const ValueKey('favorite-court-button'),
                        tooltip: '즐겨찾기',
                        onPressed: _savingFavorite ? null : _toggleFavorite,
                        icon: Icon(
                          saved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: saved ? AppColors.accent : AppColors.muted,
                          size: 21,
                        ),
                      );
                    },
                  ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => unawaited(widget.onClose()),
                  icon: Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          if (facts.isNotEmpty) ...[
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [for (final fact in facts) _CourtFact(label: fact)],
            ),
            SizedBox(height: 16),
          ],
          if (court.address != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_rounded,
                  color: AppColors.muted,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    court.address!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.soft,
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
          ],
          Row(
            children: [
              Expanded(
                child: _CourtSheetAction(
                  key: const ValueKey('write-court-review'),
                  icon: Icons.rate_review_rounded,
                  label: '리뷰',
                  primary: true,
                  onTap: repository == null ? null : widget.onWriteReview,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _CourtSheetAction(
                  key: const ValueKey('toggle-court-ranking'),
                  icon: Icons.leaderboard_rounded,
                  label: '랭킹',
                  active: _showRanking,
                  onTap: repository == null
                      ? null
                      : () => setState(() => _showRanking = !_showRanking),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _CourtSheetAction(
                  key: const ValueKey('request-court-name-change'),
                  icon: Icons.edit_location_alt_rounded,
                  label: '수정',
                  onTap: widget.onRequestNameChange,
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _showRanking && repository != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: CourtRankingCard(
                      repository: repository,
                      court: court.toSummary(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (repository != null) ...[
            StreamBuilder<List<ReviewRecord>>(
              stream: repository.watchReviews(court.id),
              builder: (context, snapshot) {
                final reviews = snapshot.data;
                if (reviews == null) {
                  return const SizedBox.shrink();
                }
                if (reviews.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 22),
                    Row(
                      children: [
                        Text(
                          '최근 리뷰',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Icon(
                          Icons.verified_rounded,
                          color: AppColors.accent,
                          size: 17,
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    for (final review in reviews.take(3))
                      _ReviewPreview(
                        review: review,
                        canAddPhotos:
                            review.uid == repository.currentUid &&
                            DateTime.now().isBefore(review.editableUntil),
                        onAddPhotos: () => widget.onAddReviewPhotos(review),
                      ),
                  ],
                );
              },
            ),
          ],
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _CourtSheetAction extends StatelessWidget {
  const _CourtSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final highlighted = primary || active;
    return Material(
      color: highlighted ? AppColors.accent : AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: onTap == null
                    ? AppColors.muted
                    : highlighted
                    ? AppColors.onAccent
                    : AppColors.text,
              ),
              SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: onTap == null
                      ? AppColors.muted
                      : highlighted
                      ? AppColors.onAccent
                      : AppColors.text,
                  fontSize: 12,
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

class _ReviewPreview extends StatelessWidget {
  const _ReviewPreview({
    required this.review,
    required this.canAddPhotos,
    required this.onAddPhotos,
  });

  final ReviewRecord review;
  final bool canAddPhotos;
  final VoidCallback onAddPhotos;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.text.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.text.withValues(alpha: .06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.authorName,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              Icon(Icons.star_rounded, color: AppColors.accent, size: 17),
              Text(
                review.rating.toStringAsFixed(1),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(review.text, style: TextStyle(fontSize: 12, height: 1.45)),
          SizedBox(height: 9),
          Text(
            '${review.courtCondition} · 조명 ${review.lighting} · '
            '그물 ${review.netCondition} · ${review.crowdLevel}',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          if (review.media.isNotEmpty) ...[
            SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.media.length,
                separatorBuilder: (_, _) => SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final media = review.media[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox.square(
                      dimension: 72,
                      child: MediaThumbnail(
                        media: media,
                        allMedia: review.media,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (canAddPhotos)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onAddPhotos,
                icon: Icon(Icons.add_photo_alternate_outlined, size: 17),
                label: Text('사진 추가'),
              ),
            ),
        ],
      ),
    );
  }
}

class _CourtFact extends StatelessWidget {
  const _CourtFact({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.text.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _NewCourtReportSheet extends StatefulWidget {
  const _NewCourtReportSheet({required this.onSubmit});

  final Future<void> Function(String name, String reason) onSubmit;

  @override
  State<_NewCourtReportSheet> createState() => _NewCourtReportSheetState();
}

class _NewCourtReportSheetState extends State<_NewCourtReportSheet> {
  final _name = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(_name.text, _reason.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is BackcourtException ? error.message : '제보를 보내지 못했어요.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '새 코트 제보',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                '현재 위치로 접수됩니다.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _name,
                maxLength: 50,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: '코트 이름'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _reason,
                maxLength: 200,
                minLines: 3,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '위치를 확인할 수 있는 설명'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? '보내는 중' : '제보하기'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CourtNameRequestSheet extends StatefulWidget {
  const _CourtNameRequestSheet({
    required this.currentName,
    required this.onSubmit,
  });

  final String currentName;
  final Future<void> Function(
    CourtReportType type,
    String? requestedName,
    String reason,
  )
  onSubmit;

  @override
  State<_CourtNameRequestSheet> createState() => _CourtNameRequestSheetState();
}

class _CourtNameRequestSheetState extends State<_CourtNameRequestSheet> {
  late final TextEditingController _nameController;
  final TextEditingController _reasonController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _reasonFocus = FocusNode();
  String? _nameError;
  String? _reasonError;
  bool _submitting = false;
  CourtReportType _type = CourtReportType.name;

  String get _requestedName => _nameController.text.trim();
  String get _reason => _reasonController.text.trim();
  bool get _canSubmit =>
      (_type != CourtReportType.name ||
          (_requestedName.length >= 2 &&
              _requestedName != widget.currentName)) &&
      _reason.length >= 2;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.currentName == '코트명 제보 필요' ? '' : widget.currentName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _reasonController.dispose();
    _nameFocus.dispose();
    _reasonFocus.dispose();
    super.dispose();
  }

  bool _validate() {
    final nameError = _type != CourtReportType.name
        ? null
        : _requestedName.length < 2
        ? '코트명을 2자 이상 입력해주세요.'
        : _requestedName == widget.currentName
        ? '현재 이름과 다른 이름을 입력해주세요.'
        : null;
    final reasonError = _reason.length < 2 ? '확인할 수 있는 근거를 적어주세요.' : null;
    setState(() {
      _nameError = nameError;
      _reasonError = reasonError;
    });
    if (nameError != null) {
      _nameFocus.requestFocus();
    } else if (reasonError != null) {
      _reasonFocus.requestFocus();
    }
    return nameError == null && reasonError == null;
  }

  Future<void> _submit() async {
    if (_submitting || !_validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        _type,
        _type == CourtReportType.name ? _requestedName : null,
        _reason,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('요청을 저장하지 못했어요. 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewName = _requestedName.isEmpty ? '새 코트 이름' : _requestedName;
    final reportCopy = switch (_type) {
      CourtReportType.name => (
        icon: Icons.edit_location_alt_rounded,
        eyebrow: 'COURT NAME',
        title: '코트명 수정',
        hint: '공식 코트명',
      ),
      CourtReportType.duplicate => (
        icon: Icons.copy_all_rounded,
        eyebrow: 'DUPLICATE COURT',
        title: '중복 코트',
        hint: '중복 코트명 또는 위치',
      ),
      CourtReportType.closed => (
        icon: Icons.block_rounded,
        eyebrow: 'CLOSED COURT',
        title: '폐쇄 코트',
        hint: '철거 · 공사 · 출입 제한',
      ),
      CourtReportType.newCourt => (
        icon: Icons.add_location_alt_rounded,
        eyebrow: 'NEW COURT',
        title: '새 코트',
        hint: '지도의 코트 제보 버튼 이용',
      ),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(22, 11, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: .24),
                        ),
                      ),
                      child: Icon(
                        reportCopy.icon,
                        color: AppColors.accent,
                        size: 23,
                      ),
                    ),
                    SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reportCopy.eyebrow,
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            reportCopy.title,
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.text.withValues(alpha: .06),
                      ),
                      icon: Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                SizedBox(height: 18),
                _CourtReportTypePicker(
                  selected: _type,
                  onChanged: (value) => setState(() {
                    _type = value;
                    _nameError = null;
                    _reasonError = null;
                  }),
                ),
                SizedBox(height: 20),
                if (_type == CourtReportType.name) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.text.withValues(alpha: .075),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NAME PREVIEW',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.3,
                          ),
                        ),
                        SizedBox(height: 12),
                        _NamePreviewRow(
                          label: '현재',
                          name: widget.currentName,
                          muted: true,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Container(
                            width: 1,
                            height: 13,
                            color: AppColors.accent.withValues(alpha: .38),
                          ),
                        ),
                        _NamePreviewRow(label: '변경', name: previewName),
                      ],
                    ),
                  ),
                  SizedBox(height: 18),
                  _CourtRequestField(
                    fieldKey: const ValueKey('requested-court-name-field'),
                    label: 'NEW COURT NAME',
                    hintText: '현장에서 사용하는 정확한 이름',
                    icon: Icons.stadium_outlined,
                    controller: _nameController,
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.next,
                    maxLength: 50,
                    errorText: _nameError,
                    onChanged: (_) => setState(() => _nameError = null),
                    onSubmitted: (_) => _reasonFocus.requestFocus(),
                  ),
                ] else ...[
                  _CourtIssueSummary(
                    type: _type,
                    courtName: widget.currentName,
                  ),
                ],
                SizedBox(height: 12),
                _CourtRequestField(
                  fieldKey: const ValueKey('court-name-reason-field'),
                  label: 'WHY?',
                  hintText: reportCopy.hint,
                  icon: Icons.fact_check_outlined,
                  controller: _reasonController,
                  focusNode: _reasonFocus,
                  textInputAction: TextInputAction.done,
                  maxLength: 200,
                  maxLines: 3,
                  errorText: _reasonError,
                  onChanged: (_) => setState(() => _reasonError = null),
                  onSubmitted: (_) => _submit(),
                ),
                SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: .065),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: .13),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.accent,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '운영자 확인 후 반영',
                          style: TextStyle(
                            color: AppColors.soft,
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 18),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    color: _canSubmit
                        ? AppColors.accent
                        : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: _canSubmit
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: .17),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey('submit-court-name-request'),
                      onTap: _submitting ? null : _submit,
                      borderRadius: BorderRadius.circular(17),
                      child: Center(
                        child: _submitting
                            ? SizedBox.square(
                                dimension: 19,
                                child: CircularProgressIndicator(
                                  color: AppColors.onAccent,
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '운영자에게 제보 보내기',
                                    style: TextStyle(
                                      color: _canSubmit
                                          ? AppColors.onAccent
                                          : AppColors.muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: _canSubmit
                                        ? AppColors.onAccent
                                        : AppColors.muted,
                                    size: 18,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CourtReportTypePicker extends StatelessWidget {
  const _CourtReportTypePicker({
    required this.selected,
    required this.onChanged,
  });

  final CourtReportType selected;
  final ValueChanged<CourtReportType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.text.withValues(alpha: .07)),
      ),
      child: Row(
        children: [
          _CourtReportTypeItem(
            label: '이름 수정',
            icon: Icons.edit_outlined,
            selected: selected == CourtReportType.name,
            onTap: () => onChanged(CourtReportType.name),
          ),
          _CourtReportTypeItem(
            label: '중복',
            icon: Icons.copy_all_outlined,
            selected: selected == CourtReportType.duplicate,
            onTap: () => onChanged(CourtReportType.duplicate),
          ),
          _CourtReportTypeItem(
            label: '폐쇄',
            icon: Icons.block_outlined,
            selected: selected == CourtReportType.closed,
            onTap: () => onChanged(CourtReportType.closed),
          ),
        ],
      ),
    );
  }
}

class _CourtReportTypeItem extends StatelessWidget {
  const _CourtReportTypeItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.text : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: selected ? AppColors.inverseText : AppColors.muted,
                  size: 15,
                ),
                SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppColors.inverseText : AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CourtIssueSummary extends StatelessWidget {
  const _CourtIssueSummary({required this.type, required this.courtName});

  final CourtReportType type;
  final String courtName;

  @override
  Widget build(BuildContext context) {
    final isDuplicate = type == CourtReportType.duplicate;
    final color = isDuplicate
        ? const Color(0xFF8DCBFF)
        : const Color(0xFFFF7777);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .075),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isDuplicate ? Icons.copy_all_rounded : Icons.block_rounded,
              color: color,
              size: 20,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  courtName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 4),
                Text(
                  isDuplicate ? '중복 등록' : '이용 불가',
                  style: TextStyle(
                    color: color,
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

class _NamePreviewRow extends StatelessWidget {
  const _NamePreviewRow({
    required this.label,
    required this.name,
    this.muted = false,
  });

  final String label;
  final String name;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 21,
          height: 21,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: muted
                ? AppColors.text.withValues(alpha: .06)
                : AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            muted ? Icons.remove_rounded : Icons.check_rounded,
            color: muted ? AppColors.muted : AppColors.onAccent,
            size: 13,
          ),
        ),
        SizedBox(width: 10),
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: muted ? AppColors.muted : AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _CourtRequestField extends StatelessWidget {
  const _CourtRequestField({
    required this.fieldKey,
    required this.label,
    required this.hintText,
    required this.icon,
    required this.controller,
    required this.focusNode,
    required this.textInputAction,
    required this.maxLength,
    required this.errorText,
    required this.onChanged,
    required this.onSubmitted,
    this.maxLines = 1,
  });

  final Key fieldKey;
  final String label;
  final String hintText;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputAction textInputAction;
  final int maxLength;
  final int maxLines;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: errorText == null
              ? AppColors.text.withValues(alpha: .08)
              : AppColors.accent.withValues(alpha: .7),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: AppColors.text.withValues(alpha: .055),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.soft, size: 19),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${controller.text.length}/$maxLength',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
                TextField(
                  key: fieldKey,
                  controller: controller,
                  focusNode: focusNode,
                  maxLength: maxLength,
                  minLines: maxLines,
                  maxLines: maxLines,
                  textInputAction: textInputAction,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  cursorColor: AppColors.accent,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    counterText: '',
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    contentPadding: const EdgeInsets.only(top: 7),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
                if (errorText != null) ...[
                  SizedBox(height: 5),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
}

class _MapPreviewPainter extends CustomPainter {
  const _MapPreviewPainter({required this.light});

  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = light ? const Color(0xFFD8D7D1) : const Color(0xFF23262A)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final major = Paint()
      ..color = light ? const Color(0xFFB9BAB7) : const Color(0xFF34383E)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    final river = Paint()
      ..color = light ? const Color(0xFFD4E6F2) : const Color(0xFF161F26)
      ..strokeWidth = 55
      ..style = PaintingStyle.stroke;
    final park = Paint()
      ..color = light ? const Color(0xFFDCE8D6) : const Color(0xFF14201A);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .18, size.height * .39),
        width: 160,
        height: 110,
      ),
      park,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .79, size.height * .52),
        width: 190,
        height: 130,
      ),
      park,
    );

    final riverPath = Path()
      ..moveTo(-30, size.height * .28)
      ..cubicTo(
        size.width * .3,
        size.height * .34,
        size.width * .62,
        size.height * .21,
        size.width + 40,
        size.height * .31,
      );
    canvas.drawPath(riverPath, river);

    final majorA = Path()
      ..moveTo(-20, size.height * .61)
      ..quadraticBezierTo(
        size.width * .42,
        size.height * .51,
        size.width + 30,
        size.height * .66,
      );
    canvas.drawPath(majorA, major);
    canvas.drawLine(
      Offset(size.width * .42, 0),
      Offset(size.width * .36, size.height),
      major,
    );

    final random = math.Random(8);
    for (var i = 0; i < 20; i++) {
      final y = size.height * (.13 + i * .043);
      final offset = random.nextDouble() * 35;
      final path = Path()
        ..moveTo(-10, y + offset)
        ..cubicTo(
          size.width * .26,
          y - 35,
          size.width * .68,
          y + 28,
          size.width + 10,
          y - offset * .25,
        );
      canvas.drawPath(path, minor);
    }
    for (var i = 0; i < 8; i++) {
      final x = size.width * (i / 7);
      canvas.drawLine(
        Offset(x - 35, size.height * .16),
        Offset(x + 55, size.height * .84),
        minor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapPreviewPainter oldDelegate) =>
      oldDelegate.light != light;
}
