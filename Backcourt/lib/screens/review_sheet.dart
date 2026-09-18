import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/branded_sheet.dart';

class ReviewComposerSheet extends StatefulWidget {
  const ReviewComposerSheet({
    super.key,
    required this.repository,
    required this.court,
  });

  final BackcourtRepository repository;
  final CourtSummary court;

  @override
  State<ReviewComposerSheet> createState() => _ReviewComposerSheetState();
}

class _ReviewComposerSheetState extends State<ReviewComposerSheet> {
  final _textController = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _images = [];
  XFile? _video;
  int _rating = 5;
  String _courtCondition = '좋음';
  String _lighting = '밝음';
  String _netCondition = '좋음';
  String _crowdLevel = '보통';
  bool _saving = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage(
      imageQuality: 88,
      maxWidth: 2160,
      maxHeight: 2160,
      limit: 6,
    );
    if (!mounted) return;
    setState(() {
      _images
        ..clear()
        ..addAll(files);
    });
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 30),
    );
    if (file != null && mounted) setState(() => _video = file);
  }

  Future<void> _submit() async {
    if (_textController.text.trim().isEmpty) {
      _show('리뷰 입력 필요');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.createReview(
        court: widget.court,
        rating: _rating,
        text: _textController.text,
        courtCondition: _courtCondition,
        lighting: _lighting,
        netCondition: _netCondition,
        crowdLevel: _crowdLevel,
        images: _images,
        video: _video,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _show(error is BackcourtException ? error.message : '리뷰 저장 실패');
    } finally {
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
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .93,
      minChildSize: .72,
      maxChildSize: .97,
      expand: false,
      builder: (context, controller) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DecoratedBox(
          decoration: backcourtSheetDecoration(),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 11, 22, 0),
                  child: BackcourtSheetHeader(
                    eyebrow: 'REVIEW',
                    title: '코트 리뷰',
                    onClose: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 19),
                Expanded(
                  child: ListView(
                    controller: controller,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                    children: [
                      BackcourtContextCard(
                        title: widget.court.name,
                        caption: 'GPS 인증 · 48시간',
                        icon: Icons.location_on_rounded,
                        badge: 'CHECKED IN',
                      ),
                      const SizedBox(height: 23),
                      const BackcourtSectionLabel(
                        title: '코트 만족도',
                        trailing: '필수',
                      ),
                      const SizedBox(height: 10),
                      _RatingPicker(
                        rating: _rating,
                        onChanged: (value) => setState(() => _rating = value),
                      ),
                      const SizedBox(height: 23),
                      const BackcourtSectionLabel(
                        title: '한 줄 리뷰',
                        trailing: '필수',
                      ),
                      const SizedBox(height: 10),
                      _ReviewTextField(controller: _textController),
                      const SizedBox(height: 23),
                      const BackcourtSectionLabel(
                        title: '코트 컨디션',
                        trailing: '4개 항목',
                      ),
                      const SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 9,
                        crossAxisSpacing: 9,
                        childAspectRatio: 2.2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _ReviewMetricPicker(
                            icon: Icons.texture_rounded,
                            label: '코트 상태',
                            value: _courtCondition,
                            values: const ['매우 좋음', '좋음', '보통', '나쁨'],
                            onChanged: (value) =>
                                setState(() => _courtCondition = value),
                          ),
                          _ReviewMetricPicker(
                            icon: Icons.light_mode_rounded,
                            label: '조명',
                            value: _lighting,
                            values: const ['밝음', '보통', '어두움', '없음'],
                            onChanged: (value) =>
                                setState(() => _lighting = value),
                          ),
                          _ReviewMetricPicker(
                            icon: Icons.sports_basketball_rounded,
                            label: '골대 그물',
                            value: _netCondition,
                            values: const ['좋음', '보통', '훼손', '없음'],
                            onChanged: (value) =>
                                setState(() => _netCondition = value),
                          ),
                          _ReviewMetricPicker(
                            icon: Icons.groups_rounded,
                            label: '현재 혼잡도',
                            value: _crowdLevel,
                            values: const ['한산', '보통', '혼잡', '매우 혼잡'],
                            onChanged: (value) =>
                                setState(() => _crowdLevel = value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 23),
                      const BackcourtSectionLabel(
                        title: '현장 미디어',
                        trailing: '선택',
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: BackcourtMediaAction(
                              icon: Icons.photo_library_rounded,
                              title: '사진 ${_images.length}/6',
                              caption: _images.isEmpty
                                  ? '여러 장 선택 가능'
                                  : '선택 완료 · 다시 고르기',
                              active: _images.isNotEmpty,
                              onTap: _pickImages,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: BackcourtMediaAction(
                              icon: Icons.videocam_rounded,
                              title: _video == null ? '영상' : '영상 선택됨',
                              caption: _video == null ? '최대 30초' : '다시 고르기',
                              active: _video != null,
                              onTap: _pickVideo,
                            ),
                          ),
                        ],
                      ),
                      if (_images.isNotEmpty) ...[
                        const SizedBox(height: 11),
                        _ImagePreviewStrip(
                          images: _images,
                          onRemove: (image) =>
                              setState(() => _images.remove(image)),
                        ),
                      ],
                      const SizedBox(height: 10),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            color: AppColors.muted,
                            size: 11,
                          ),
                          SizedBox(width: 5),
                          Text(
                            '사진 10MB · 영상 100MB · 출석 인증 리뷰',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    13,
                    22,
                    MediaQuery.paddingOf(context).bottom + 13,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: .06),
                      ),
                    ),
                  ),
                  child: BackcourtPrimaryAction(
                    label: '리뷰 등록',
                    loading: _saving,
                    icon: Icons.check_rounded,
                    onPressed: _submit,
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

class _RatingPicker extends StatelessWidget {
  const _RatingPicker({required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  static const _labels = ['아쉬워요', '별로예요', '괜찮아요', '좋아요', '최고예요'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) {
              final value = index + 1;
              final selected = value <= rating;
              return Expanded(
                child: Semantics(
                  button: true,
                  label: '$value점',
                  child: InkWell(
                    onTap: () => onChanged(value),
                    borderRadius: BorderRadius.circular(13),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Icon(
                        selected
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: selected
                            ? AppColors.accent
                            : Colors.white.withValues(alpha: .19),
                        size: 34,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$rating.0',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Container(
                width: 3,
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                decoration: const BoxDecoration(
                  color: AppColors.muted,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                _labels[rating - 1],
                style: const TextStyle(
                  color: AppColors.soft,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewTextField extends StatelessWidget {
  const _ReviewTextField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Stack(
        children: [
          TextField(
            controller: controller,
            minLines: 4,
            maxLines: 7,
            maxLength: 1000,
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: const InputDecoration(
              hintText: '리뷰 입력',
              hintStyle: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.55,
              ),
              filled: false,
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(16, 15, 16, 31),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 11,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => Text(
                '${value.text.length}/1000',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewMetricPicker extends StatelessWidget {
  const _ReviewMetricPicker({
    required this.icon,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: value,
      color: const Color(0xFF242424),
      elevation: 14,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final item in values)
          PopupMenuItem<String>(
            value: item,
            child: Row(
              children: [
                Icon(
                  item == value ? Icons.check_rounded : null,
                  color: AppColors.accent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(item, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: AppColors.soft, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              color: AppColors.muted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewStrip extends StatelessWidget {
  const _ImagePreviewStrip({required this.images, required this.onRemove});

  final List<XFile> images;
  final ValueChanged<XFile> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = images[index];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(image.path),
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: AppColors.surfaceHigh,
                    child: SizedBox.square(
                      dimension: 76,
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => onRemove(image),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .72),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
