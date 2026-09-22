import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import 'map_screen.dart';

typedef HomeCourtSetupSaver = Future<void> Function(List<CourtSummary> courts);
typedef HomeCourtSetupPicker =
    Future<CourtSummary?> Function(CourtSummary? initialCourt);

class HomeCourtSetupScreen extends StatefulWidget {
  const HomeCourtSetupScreen({
    super.key,
    this.repository,
    this.saveOverride,
    this.pickerOverride,
    this.initialCourts = const [],
  }) : assert(repository != null || saveOverride != null);

  final BackcourtRepository? repository;
  final HomeCourtSetupSaver? saveOverride;
  final HomeCourtSetupPicker? pickerOverride;
  final List<CourtSummary> initialCourts;

  @override
  State<HomeCourtSetupScreen> createState() => _HomeCourtSetupScreenState();
}

class _HomeCourtSetupScreenState extends State<HomeCourtSetupScreen> {
  late final List<CourtSummary> _courts = [...widget.initialCourts.take(3)];
  bool _saving = false;

  Future<void> _addCourt() async {
    if (_saving || _courts.length >= 3) return;
    final picker = widget.pickerOverride;
    final CourtSummary? selected;
    if (picker != null) {
      selected = await picker(_courts.firstOrNull);
    } else {
      if (!mounted) return;
      selected = await Navigator.of(context).push<CourtSummary>(
        MaterialPageRoute(
          builder: (pickerContext) => Scaffold(
            backgroundColor: AppColors.background,
            body: MapScreen(
              repository: widget.repository,
              initialCourt: _courts.firstOrNull,
              pickerMode: true,
              onPickerClose: () => Navigator.pop(pickerContext),
              onCourtSelected: (court) => Navigator.pop(pickerContext, court),
            ),
          ),
        ),
      );
    }
    if (selected == null || !mounted) return;
    final selectedCourt = selected;
    if (_courts.any((court) => court.id == selectedCourt.id)) {
      _show('이미 선택한 코트예요.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _courts.add(selectedCourt));
  }

  void _removeCourt(CourtSummary court) {
    if (_saving) return;
    HapticFeedback.selectionClick();
    setState(() => _courts.removeWhere((item) => item.id == court.id));
  }

  Future<void> _save() async {
    if (_saving || _courts.isEmpty) return;
    setState(() => _saving = true);
    try {
      final save = widget.saveOverride;
      if (save != null) {
        await save(List.unmodifiable(_courts));
      } else {
        await widget.repository!.saveHomeCourts(_courts);
      }
      HapticFeedback.mediumImpact();
    } catch (error) {
      _show(error is BackcourtException ? error.message : '저장하지 못했어요.');
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.asset('icon.png', width: 38, height: 38),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '빽코트',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_courts.length}/3',
                    key: const ValueKey('home-court-setup-count'),
                    style: TextStyle(
                      color: _courts.isEmpty
                          ? AppColors.muted
                          : AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 42),
              Text(
                'HOME COURT',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '자주 가는 코트',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                '최대 3개까지',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (var index = 0; index < _courts.length; index++)
                      _SelectedHomeCourt(
                        court: _courts[index],
                        primary: index == 0,
                        onRemove: () => _removeCourt(_courts[index]),
                      ),
                    if (_courts.length < 3)
                      _AddCourtButton(enabled: !_saving, onTap: _addCourt),
                    if (_courts.isEmpty) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          '코트를 하나 이상 골라주세요.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  key: const ValueKey('home-court-setup-save'),
                  onPressed: _courts.isEmpty || _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    disabledBackgroundColor: AppColors.subtleFill,
                    disabledForegroundColor: AppColors.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _saving
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onAccent,
                          ),
                        )
                      : const Text(
                          '이대로 시작',
                          style: TextStyle(fontWeight: FontWeight.w900),
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

class _SelectedHomeCourt extends StatelessWidget {
  const _SelectedHomeCourt({
    required this.court,
    required this.primary,
    required this.onRemove,
  });

  final CourtSummary court;
  final bool primary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(15, 13, 8, 13),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: primary
            ? AppColors.accent.withValues(alpha: .55)
            : AppColors.text.withValues(alpha: .08),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: primary
                ? AppColors.accent
                : AppColors.text.withValues(alpha: .06),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.sports_basketball_rounded,
            color: primary ? AppColors.onAccent : AppColors.soft,
            size: 19,
          ),
        ),
        const SizedBox(width: 12),
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
              const SizedBox(height: 4),
              Text(
                primary ? '기본 코트' : court.address ?? '홈코트',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: primary ? AppColors.accent : AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '선택 해제',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, size: 19),
          color: AppColors.muted,
        ),
      ],
    ),
  );
}

class _AddCourtButton extends StatelessWidget {
  const _AddCourtButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: const ValueKey('home-court-setup-add'),
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.text.withValues(alpha: .13),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.text.withValues(alpha: .06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_location_alt_outlined,
                color: AppColors.soft,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '지도에서 코트 추가',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppColors.muted,
              size: 15,
            ),
          ],
        ),
      ),
    ),
  );
}
