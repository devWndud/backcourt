import 'package:flutter/material.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';

class OperatorReportsScreen extends StatefulWidget {
  const OperatorReportsScreen({
    super.key,
    this.repository,
    this.previewReports,
    this.onPreviewReview,
  }) : assert(repository != null || previewReports != null);

  final BackcourtRepository? repository;
  final Stream<List<CourtReport>>? previewReports;
  final Future<void> Function(
    CourtReport report,
    CourtReportStatus status,
    String note,
  )?
  onPreviewReview;

  @override
  State<OperatorReportsScreen> createState() => _OperatorReportsScreenState();
}

enum _ReportFilter { pending, onHold, completed }

class _OperatorReportsScreenState extends State<OperatorReportsScreen> {
  _ReportFilter _filter = _ReportFilter.pending;
  String? _processingId;

  List<CourtReport> _filtered(List<CourtReport> reports) => switch (_filter) {
    _ReportFilter.pending =>
      reports
          .where((report) => report.status == CourtReportStatus.pending)
          .toList(),
    _ReportFilter.onHold =>
      reports
          .where((report) => report.status == CourtReportStatus.onHold)
          .toList(),
    _ReportFilter.completed =>
      reports
          .where(
            (report) =>
                report.status == CourtReportStatus.approved ||
                report.status == CourtReportStatus.rejected,
          )
          .toList(),
  };

  Future<void> _openReport(CourtReport report) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ReportDetailSheet(
        report: report,
        processing: _processingId == report.id,
        onDecision: (decision) async {
          Navigator.pop(context);
          await _confirmDecision(report, decision);
        },
      ),
    );
  }

  Future<void> _confirmDecision(
    CourtReport report,
    CourtReportStatus decision,
  ) async {
    final result = await showModalBottomSheet<_ReviewDecision>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DecisionSheet(report: report, decision: decision),
    );
    if (result == null || !mounted) return;

    setState(() => _processingId = report.id);
    try {
      final previewReview = widget.onPreviewReview;
      if (previewReview != null) {
        await previewReview(report, result.status, result.note);
      } else {
        await widget.repository!.reviewCourtReport(
          report: report,
          decision: result.status,
          resolutionNote: result.note,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_completionMessage(report, result.status))),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is BackcourtException
          ? error.message
          : '제보를 처리하지 못했어요. 다시 시도해주세요.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  String _completionMessage(CourtReport report, CourtReportStatus status) {
    if (status == CourtReportStatus.onHold) return '제보를 보류함으로 옮겼어요.';
    if (status == CourtReportStatus.rejected) return '제보를 반려했어요.';
    return switch (report.type) {
      CourtReportType.name => '코트명이 지도 데이터에 반영됐어요.',
      CourtReportType.duplicate => '중복 코트로 처리했어요.',
      CourtReportType.closed => '폐쇄 코트로 처리했어요.',
      CourtReportType.newCourt => '새 코트를 지도에 등록했어요.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<CourtReport>>(
          stream:
              widget.previewReports ?? widget.repository!.watchCourtReports(),
          builder: (context, snapshot) {
            final reports = snapshot.data ?? const <CourtReport>[];
            final visible = _filtered(reports);
            final pending = reports
                .where((report) => report.status == CourtReportStatus.pending)
                .length;
            final onHold = reports
                .where((report) => report.status == CourtReportStatus.onHold)
                .length;
            final approved = reports
                .where((report) => report.status == CourtReportStatus.approved)
                .length;
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverList.list(
                    children: [
                      _TopBar(onBack: () => Navigator.pop(context)),
                      SizedBox(height: 24),
                      _OpsOverview(
                        pending: pending,
                        onHold: onHold,
                        approved: approved,
                      ),
                      SizedBox(height: 22),
                      _FilterBar(
                        selected: _filter,
                        pending: pending,
                        onHold: onHold,
                        completed: reports.length - pending - onHold,
                        onChanged: (value) => setState(() => _filter = value),
                      ),
                      SizedBox(height: 17),
                    ],
                  ),
                ),
                if (snapshot.hasError)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: '제보함을 열지 못했어요',
                      subtitle: '권한과 네트워크를 확인해주세요.',
                    ),
                  )
                else if (!snapshot.hasData)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                        strokeWidth: 2.4,
                      ),
                    ),
                  )
                else if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      icon: _filter == _ReportFilter.completed
                          ? Icons.inventory_2_outlined
                          : Icons.done_all_rounded,
                      title: _filter == _ReportFilter.completed
                          ? '아직 처리 내역이 없어요'
                          : '여기는 깨끗해요',
                      subtitle: _filter == _ReportFilter.pending
                          ? '새 제보가 들어오면 바로 표시할게요.'
                          : '해당 상태의 제보가 없습니다.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 34),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => SizedBox(height: 11),
                      itemBuilder: (context, index) {
                        final report = visible[index];
                        return _ReportCard(
                          report: report,
                          processing: _processingId == report.id,
                          onTap: () => _openReport(report),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
        SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BACKCOURT OPERATIONS',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.55,
                ),
              ),
              SizedBox(height: 5),
              Text(
                '코트 데이터 센터',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.success.withValues(alpha: .18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_rounded, size: 13, color: AppColors.success),
              SizedBox(width: 5),
              Text(
                'OPERATOR',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OpsOverview extends StatelessWidget {
  const _OpsOverview({
    required this.pending,
    required this.onHold,
    required this.approved,
  });

  final int pending;
  final int onHold;
  final int approved;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF704E), AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: .18),
            blurRadius: 30,
            offset: const Offset(0, 13),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.onAccent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.manage_search_rounded,
                  color: AppColors.onAccent,
                  size: 23,
                ),
              ),
              const Spacer(),
              Text(
                'LIVE QUEUE',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Text(
            pending == 0 ? '처리할 제보가 없어요' : '$pending건을 확인해주세요',
            style: TextStyle(
              color: AppColors.onAccent,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          SizedBox(height: 5),
          Text(
            pending == 0 ? '전국 코트 데이터가 최신 상태예요.' : '승인하면 코트 데이터에 즉시 반영됩니다.',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 19),
          Row(
            children: [
              _OverviewStat(value: '$pending', label: '대기'),
              const _DarkDivider(),
              _OverviewStat(value: '$onHold', label: '보류'),
              const _DarkDivider(),
              _OverviewStat(value: '$approved', label: '승인 완료'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: AppColors.onAccent,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.black54,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _DarkDivider extends StatelessWidget {
  const _DarkDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 29,
    margin: const EdgeInsets.symmetric(horizontal: 15),
    color: AppColors.onAccent.withValues(alpha: .17),
  );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.pending,
    required this.onHold,
    required this.completed,
    required this.onChanged,
  });

  final _ReportFilter selected;
  final int pending;
  final int onHold;
  final int completed;
  final ValueChanged<_ReportFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.text.withValues(alpha: .055)),
      ),
      child: Row(
        children: [
          _FilterItem(
            label: '대기',
            count: pending,
            selected: selected == _ReportFilter.pending,
            onTap: () => onChanged(_ReportFilter.pending),
          ),
          _FilterItem(
            label: '보류',
            count: onHold,
            selected: selected == _ReportFilter.onHold,
            onTap: () => onChanged(_ReportFilter.onHold),
          ),
          _FilterItem(
            label: '완료',
            count: completed,
            selected: selected == _ReportFilter.completed,
            onTap: () => onChanged(_ReportFilter.completed),
          ),
        ],
      ),
    );
  }
}

class _FilterItem extends StatelessWidget {
  const _FilterItem({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
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
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.inverseText : AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 19),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accent
                      : AppColors.text.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(99),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? AppColors.onAccent : AppColors.soft,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
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

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.processing,
    required this.onTap,
  });

  final CourtReport report;
  final bool processing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = _ReportMeta.of(report.type);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        key: ValueKey('court-report-${report.id}'),
        onTap: processing ? null : onTap,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: AppColors.text.withValues(alpha: .06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _TypeBadge(meta: meta),
                  SizedBox(width: 7),
                  _StatusBadge(status: report.status),
                  const Spacer(),
                  Text(
                    _relativeDate(report.createdAt),
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              Text(
                report.currentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.4,
                ),
              ),
              if (report.type == CourtReportType.name) ...[
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right_rounded,
                      color: AppColors.accent,
                      size: 17,
                    ),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        report.requestedName ?? '새 이름 없음',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      report.reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ),
                  SizedBox(width: 10),
                  if (processing)
                    SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                        strokeWidth: 2,
                      ),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppColors.muted,
                      size: 13,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportDetailSheet extends StatelessWidget {
  const _ReportDetailSheet({
    required this.report,
    required this.processing,
    required this.onDecision,
  });

  final CourtReport report;
  final bool processing;
  final ValueChanged<CourtReportStatus> onDecision;

  @override
  Widget build(BuildContext context) {
    final meta = _ReportMeta.of(report.type);
    final isDone =
        report.status == CourtReportStatus.approved ||
        report.status == CourtReportStatus.rejected;
    return DraggableScrollableSheet(
      initialChildSize: .78,
      minChildSize: .55,
      maxChildSize: .94,
      expand: false,
      builder: (context, controller) => Material(
        color: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(22, 11, 22, 28),
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
            SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: meta.color.withValues(alpha: .2)),
                  ),
                  child: Icon(meta.icon, color: meta.color, size: 24),
                ),
                SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.eyebrow,
                        style: TextStyle(
                          color: meta.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        meta.title,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.7,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: report.status),
              ],
            ),
            SizedBox(height: 22),
            _DataBlock(
              label: report.type == CourtReportType.name
                  ? 'NAME CHANGE'
                  : 'COURT',
              child: report.type == CourtReportType.name
                  ? _NameChange(
                      currentName: report.currentName,
                      requestedName: report.requestedName ?? '새 이름 없음',
                    )
                  : Text(
                      report.currentName,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
            SizedBox(height: 11),
            _DataBlock(
              label: 'REPORT',
              child: Text(
                report.reason,
                style: TextStyle(
                  color: AppColors.soft,
                  fontSize: 13,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(height: 11),
            _DataBlock(
              label: 'DETAILS',
              child: Column(
                children: [
                  _DetailRow(
                    icon: Icons.person_outline_rounded,
                    label: '제보자',
                    value: report.requesterName,
                  ),
                  _DetailRow(
                    icon: Icons.schedule_rounded,
                    label: '접수',
                    value: _fullDate(report.createdAt),
                  ),
                  _DetailRow(
                    icon: Icons.tag_rounded,
                    label: '코트 ID',
                    value: report.courtId,
                  ),
                  if (report.latitude != null && report.longitude != null)
                    _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: '좌표',
                      value:
                          '${report.latitude!.toStringAsFixed(5)}, ${report.longitude!.toStringAsFixed(5)}',
                      last: true,
                    ),
                ],
              ),
            ),
            if (report.resolutionNote?.isNotEmpty == true) ...[
              SizedBox(height: 11),
              _DataBlock(
                label: 'OPERATOR NOTE',
                child: Text(
                  report.resolutionNote!,
                  style: TextStyle(
                    color: AppColors.soft,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            SizedBox(height: 20),
            if (isDone)
              Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.text.withValues(alpha: .055),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  report.status == CourtReportStatus.approved
                      ? '처리가 완료된 제보입니다'
                      : '반려 처리된 제보입니다',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              Row(
                children: [
                  _DecisionButton(
                    icon: Icons.pause_rounded,
                    label: '보류',
                    color: const Color(0xFFFFC857),
                    onTap: processing
                        ? null
                        : () => onDecision(CourtReportStatus.onHold),
                  ),
                  SizedBox(width: 8),
                  _DecisionButton(
                    icon: Icons.close_rounded,
                    label: '반려',
                    color: const Color(0xFFFF7777),
                    onTap: processing
                        ? null
                        : () => onDecision(CourtReportStatus.rejected),
                  ),
                  SizedBox(width: 8),
                  _DecisionButton(
                    icon: Icons.check_rounded,
                    label: '승인',
                    color: AppColors.accent,
                    filled: true,
                    onTap: processing
                        ? null
                        : () => onDecision(CourtReportStatus.approved),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DecisionSheet extends StatefulWidget {
  const _DecisionSheet({required this.report, required this.decision});

  final CourtReport report;
  final CourtReportStatus decision;

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final approved = widget.decision == CourtReportStatus.approved;
    final rejected = widget.decision == CourtReportStatus.rejected;
    final color = approved
        ? AppColors.accent
        : rejected
        ? const Color(0xFFFF7777)
        : const Color(0xFFFFC857);
    final title = approved
        ? '이 제보를 승인할까요?'
        : rejected
        ? '반려 사유를 남길까요?'
        : '보류함으로 옮길까요?';
    final action = approved
        ? '확인하고 반영'
        : rejected
        ? '반려 처리'
        : '보류 처리';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 11, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                SizedBox(height: 22),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.7,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  approved
                      ? _approvalDescription(widget.report)
                      : '제보자에게 보여줄 운영 메모를 선택적으로 남길 수 있어요.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: 17),
                TextField(
                  controller: _noteController,
                  maxLength: 200,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: widget.report.type == CourtReportType.duplicate
                        ? '중복되는 코트명이나 코트 ID를 적어두세요.'
                        : '운영 메모 (선택)',
                    counterText: '',
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.notes_rounded),
                    ),
                  ),
                ),
                SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 53,
                  child: FilledButton(
                    key: const ValueKey('confirm-court-report-decision'),
                    onPressed: () => Navigator.pop(
                      context,
                      _ReviewDecision(
                        status: widget.decision,
                        note: _noteController.text.trim(),
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: AppColors.onAccent,
                    ),
                    child: Text(action),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _approvalDescription(CourtReport report) => switch (report.type) {
    CourtReportType.name =>
      '승인 즉시 코트명이 “${report.requestedName ?? ''}”으로 바뀝니다.',
    CourtReportType.duplicate => '승인 즉시 해당 코트가 중복 상태로 표시됩니다.',
    CourtReportType.closed => '승인 즉시 해당 코트가 폐쇄 상태로 표시됩니다.',
    CourtReportType.newCourt => '승인 즉시 제보된 위치에 새 코트가 등록됩니다.',
  };
}

class _NameChange extends StatelessWidget {
  const _NameChange({required this.currentName, required this.requestedName});

  final String currentName;
  final String requestedName;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _NameLine(label: '현재', value: currentName, muted: true),
      Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 1,
            height: 13,
            color: AppColors.accent.withValues(alpha: .4),
          ),
        ),
      ),
      _NameLine(label: '변경', value: requestedName),
    ],
  );
}

class _NameLine extends StatelessWidget {
  const _NameLine({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 21,
        height: 21,
        decoration: BoxDecoration(
          color: muted
              ? AppColors.text.withValues(alpha: .07)
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
        width: 34,
        child: Text(
          label,
          style: TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ),
      Expanded(
        child: Text(
          value,
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

class _DataBlock extends StatelessWidget {
  const _DataBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: AppColors.text.withValues(alpha: .06)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.35,
          ),
        ),
        SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.muted, size: 17),
        SizedBox(width: 9),
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _DecisionButton extends StatelessWidget {
  const _DecisionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => Expanded(
    child: SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          backgroundColor: filled ? color : color.withValues(alpha: .08),
          foregroundColor: filled ? AppColors.onAccent : color,
          side: BorderSide(
            color: filled ? color : color.withValues(alpha: .24),
          ),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
      ),
    ),
  );
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.meta});

  final _ReportMeta meta;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: meta.color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: meta.color.withValues(alpha: .16)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(meta.icon, color: meta.color, size: 12),
        SizedBox(width: 4),
        Text(
          meta.shortLabel,
          style: TextStyle(
            color: meta.color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final CourtReportStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      CourtReportStatus.pending => ('대기', AppColors.soft),
      CourtReportStatus.onHold => ('보류', const Color(0xFFFFC857)),
      CourtReportStatus.approved => ('승인', AppColors.success),
      CourtReportStatus.rejected => ('반려', const Color(0xFFFF7777)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceHigh,
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(width: 43, height: 43, child: Icon(icon, size: 20)),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 80),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.text.withValues(alpha: .06)),
          ),
          child: Icon(icon, color: AppColors.accent, size: 28),
        ),
        SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 5),
        Text(subtitle, style: TextStyle(color: AppColors.muted, fontSize: 11)),
      ],
    ),
  );
}

class _ReportMeta {
  const _ReportMeta({
    required this.icon,
    required this.color,
    required this.shortLabel,
    required this.eyebrow,
    required this.title,
  });

  factory _ReportMeta.of(CourtReportType type) => switch (type) {
    CourtReportType.name => const _ReportMeta(
      icon: Icons.edit_location_alt_rounded,
      color: AppColors.accent,
      shortLabel: '이름 수정',
      eyebrow: 'COURT NAME',
      title: '코트명 수정 제보',
    ),
    CourtReportType.duplicate => const _ReportMeta(
      icon: Icons.copy_all_rounded,
      color: Color(0xFF8DCBFF),
      shortLabel: '중복',
      eyebrow: 'DUPLICATE COURT',
      title: '중복 코트 제보',
    ),
    CourtReportType.closed => const _ReportMeta(
      icon: Icons.block_rounded,
      color: Color(0xFFFF7777),
      shortLabel: '폐쇄',
      eyebrow: 'CLOSED COURT',
      title: '폐쇄 코트 제보',
    ),
    CourtReportType.newCourt => const _ReportMeta(
      icon: Icons.add_location_alt_rounded,
      color: Color(0xFF7FD8A4),
      shortLabel: '새 코트',
      eyebrow: 'NEW COURT',
      title: '새 코트 제보',
    ),
  };

  final IconData icon;
  final Color color;
  final String shortLabel;
  final String eyebrow;
  final String title;
}

class _ReviewDecision {
  const _ReviewDecision({required this.status, required this.note});

  final CourtReportStatus status;
  final String note;
}

String _relativeDate(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return '방금';
  if (difference.inHours < 1) return '${difference.inMinutes}분 전';
  if (difference.inDays < 1) return '${difference.inHours}시간 전';
  if (difference.inDays < 7) return '${difference.inDays}일 전';
  return '${value.month}.${value.day}';
}

String _fullDate(DateTime value) =>
    '${value.year}.${value.month.toString().padLeft(2, '0')}.'
    '${value.day.toString().padLeft(2, '0')}  '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
