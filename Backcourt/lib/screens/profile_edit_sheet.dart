import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';
import '../widgets/branded_sheet.dart';

class ProfileEditSheet extends StatefulWidget {
  const ProfileEditSheet({
    super.key,
    required this.repository,
    required this.profile,
  });

  final BackcourtRepository repository;
  final AppUserProfile profile;

  @override
  State<ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<ProfileEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  final _picker = ImagePicker();
  Timer? _usernameDebounce;
  XFile? _profilePhoto;
  bool _saving = false;
  bool _checkingUsername = false;
  bool? _usernameAvailable;

  String get _normalizedUsername =>
      BackcourtRepository.normalizeUsername(_usernameController.text);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _usernameController = TextEditingController(
      text: widget.profile.username ?? '',
    );
    _bioController = TextEditingController(text: widget.profile.bio);
    _usernameAvailable = widget.profile.username?.isNotEmpty == true
        ? true
        : null;
    _usernameController.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameController
      ..removeListener(_onUsernameChanged)
      ..dispose();
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    _usernameDebounce?.cancel();
    final username = _normalizedUsername;
    final current = widget.profile.username?.toLowerCase();
    if (username == current && username.isNotEmpty) {
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = true;
      });
      return;
    }
    if (!BackcourtRepository.isValidUsername(username)) {
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = null;
      });
      return;
    }
    setState(() {
      _checkingUsername = true;
      _usernameAvailable = null;
    });
    _usernameDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final available = await widget.repository.isUsernameAvailable(username);
        if (!mounted || username != _normalizedUsername) return;
        setState(() {
          _checkingUsername = false;
          _usernameAvailable = available;
        });
      } catch (_) {
        if (!mounted || username != _normalizedUsername) return;
        setState(() {
          _checkingUsername = false;
          _usernameAvailable = null;
        });
      }
    });
  }

  Future<void> _pickProfilePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PhotoSourceSheet(
        onSelected: (source) => Navigator.pop(context, source),
      ),
    );
    if (source == null) return;
    final photo = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1440,
      maxHeight: 1440,
    );
    if (photo != null && mounted) setState(() => _profilePhoto = photo);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final username = _normalizedUsername;
    if (name.length < 2 || name.length > 24) {
      _show('이름은 2~24자로 입력해주세요.');
      return;
    }
    if (!BackcourtRepository.isValidUsername(username)) {
      _show('아이디는 영문 소문자·숫자·._ 조합 3~20자로 입력해주세요.');
      return;
    }
    if (_bioController.text.trim().length > 120) {
      _show('소개는 120자까지 입력할 수 있어요.');
      return;
    }
    if (_usernameAvailable == false) {
      _show('이미 사용 중인 아이디예요.');
      return;
    }
    if (_checkingUsername) {
      _show('아이디 중복 확인이 끝날 때까지 잠시만 기다려주세요.');
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repository.updateProfile(
        displayName: name,
        username: username,
        bio: _bioController.text,
        profilePhoto: _profilePhoto,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _show(error is BackcourtException ? error.message : '프로필을 저장하지 못했어요.');
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
      initialChildSize: .91,
      minChildSize: .7,
      maxChildSize: .97,
      expand: false,
      builder: (context, scrollController) => AnimatedPadding(
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
                    eyebrow: 'PROFILE',
                    title: '프로필 편집',
                    onClose: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 17),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                    children: [
                      Center(
                        child: _EditableAvatar(
                          displayName: _nameController.text,
                          currentPhotoUrl: widget.profile.photoUrl,
                          selectedPhoto: _profilePhoto,
                          onTap: _pickProfilePhoto,
                        ),
                      ),
                      const SizedBox(height: 11),
                      const Center(
                        child: Text(
                          '프로필 사진 변경',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      const BackcourtSectionLabel(title: '기본 정보'),
                      const SizedBox(height: 10),
                      _ProfileField(
                        controller: _nameController,
                        label: '이름',
                        hint: '이름',
                        icon: Icons.badge_outlined,
                        maxLength: 24,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      _ProfileField(
                        key: const ValueKey('profile-username-field'),
                        controller: _usernameController,
                        label: '빽코트 아이디',
                        hint: 'backcourt.player',
                        icon: Icons.alternate_email_rounded,
                        maxLength: 20,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.name,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9._]'),
                          ),
                        ],
                        suffix: _UsernameStatus(
                          checking: _checkingUsername,
                          available: _usernameAvailable,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
                        child: Text(
                          _usernameHelper,
                          style: TextStyle(
                            color: _usernameAvailable == false
                                ? AppColors.accent
                                : AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 19),
                      const BackcourtSectionLabel(
                        title: '소개',
                        trailing: '최대 120자',
                      ),
                      const SizedBox(height: 10),
                      _ProfileField(
                        controller: _bioController,
                        label: '소개',
                        hint: '포지션 · 플레이 스타일 · 자주 가는 코트',
                        icon: Icons.format_quote_rounded,
                        maxLength: 120,
                        minLines: 4,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
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
                    label: '프로필 저장',
                    loading: _saving,
                    icon: Icons.check_rounded,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _usernameHelper {
    if (_normalizedUsername.isEmpty) return 'a-z · 0-9 · . · _';
    if (!BackcourtRepository.isValidUsername(_normalizedUsername)) {
      return '3~20자 · 처음/끝 영문 또는 숫자';
    }
    if (_checkingUsername) return '중복 확인 중';
    if (_usernameAvailable == true) return '사용 가능';
    if (_usernameAvailable == false) return '사용 중';
    return '저장 시 중복 확인';
  }
}

class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.displayName,
    required this.currentPhotoUrl,
    required this.selectedPhoto,
    required this.onTap,
  });

  final String displayName;
  final String? currentPhotoUrl;
  final XFile? selectedPhoto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.accent, Color(0xFFFFB15C)],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
              shape: BoxShape.circle,
            ),
            child: ClipOval(child: _avatarContent()),
          ),
          Positioned(
            right: -2,
            bottom: 1,
            child: Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 3),
              ),
              child: const Icon(
                Icons.photo_camera_rounded,
                color: Colors.black,
                size: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarContent() {
    final selected = selectedPhoto;
    if (selected != null) {
      return Image.file(
        File(selected.path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    final photoUrl = currentPhotoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => ColoredBox(
    color: AppColors.accentSoft,
    child: Center(
      child: Text(
        displayName.characters.take(2).toString(),
        style: const TextStyle(
          color: Colors.black,
          fontSize: 23,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.maxLength,
    required this.textInputAction,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.suffix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLength;
  final int minLines;
  final int maxLines;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        maxLength: maxLength,
        textInputAction: textInputAction,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: AppColors.muted, fontSize: 11),
          hintStyle: const TextStyle(color: Color(0xFF626262), fontSize: 11),
          prefixIcon: Icon(icon, color: AppColors.muted, size: 18),
          suffixIcon: suffix,
          filled: false,
          counterText: '',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(
            0,
            minLines > 1 ? 15 : 8,
            14,
            minLines > 1 ? 15 : 8,
          ),
        ),
      ),
    );
  }
}

class _UsernameStatus extends StatelessWidget {
  const _UsernameStatus({required this.checking, required this.available});

  final bool checking;
  final bool? available;

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox.square(
          dimension: 15,
          child: CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 1.8,
          ),
        ),
      );
    }
    if (available == null) return const SizedBox.shrink();
    return Icon(
      available! ? Icons.check_circle_rounded : Icons.cancel_rounded,
      color: available! ? AppColors.success : AppColors.accent,
      size: 19,
    );
  }
}

class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet({required this.onSelected});

  final ValueChanged<ImageSource> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: backcourtSheetDecoration(),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 11, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BackcourtSheetHeader(
                eyebrow: 'PROFILE IMAGE',
                title: '사진 가져오기',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: BackcourtMediaAction(
                      icon: Icons.photo_library_rounded,
                      title: '갤러리',
                      caption: '사진 선택',
                      onTap: () => onSelected(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: BackcourtMediaAction(
                      icon: Icons.photo_camera_rounded,
                      title: '카메라',
                      caption: '촬영',
                      onTap: () => onSelected(ImageSource.camera),
                    ),
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
