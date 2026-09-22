import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/backcourt_repository.dart';
import '../backend/models.dart';
import '../theme/app_theme.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.repository,
    required this.profile,
  });

  final BackcourtRepository repository;
  final AppUserProfile profile;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _birthYearController;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _birthYearFocus = FocusNode();
  bool _guardianConsent = false;
  bool _saving = false;

  String get _name => _nameController.text.trim();
  int? get _birthYear => int.tryParse(_birthYearController.text.trim());
  bool get _validBirthYear {
    final year = _birthYear;
    return year != null && year >= 1900 && year <= DateTime.now().year;
  }

  bool get _isMinor {
    final year = _birthYear;
    return year != null && DateTime.now().year - year < 19;
  }

  bool get _canSubmit =>
      _name.length >= 2 &&
      _validBirthYear &&
      (!_isMinor || _guardianConsent) &&
      !_saving;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _birthYearController = TextEditingController();
    _nameFocus.addListener(_refresh);
    _birthYearFocus.addListener(_refresh);
  }

  @override
  void dispose() {
    _nameFocus
      ..removeListener(_refresh)
      ..dispose();
    _birthYearFocus
      ..removeListener(_refresh)
      ..dispose();
    _nameController.dispose();
    _birthYearController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (_name.length < 2 || !_validBirthYear) {
      _show('닉네임과 출생 연도를 확인해주세요.');
      return;
    }
    if (_isMinor && !_guardianConsent) {
      _show('보호자 동의를 확인해주세요.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      await widget.repository.completeProfile(
        displayName: _name,
        birthYear: _birthYear!,
        guardianConsent: _guardianConsent,
      );
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
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _ProfileBackdrop()),
          SafeArea(
            bottom: false,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 138),
              children: [
                const _ProfileHeader(),
                SizedBox(height: 48),
                Text(
                  'WELCOME TO THE COURT',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  '코트에서,\n뭐라고 부를까요?',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 38,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2.2,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  '닉네임 · 출생 연도',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: 30),
                _ProfilePreview(name: _name),
                SizedBox(height: 26),
                _ProfileField(
                  label: 'NICKNAME',
                  hintText: '코트에서 사용할 이름',
                  icon: Icons.alternate_email_rounded,
                  controller: _nameController,
                  focusNode: _nameFocus,
                  maxLength: 20,
                  textInputAction: TextInputAction.next,
                  trailing: '${_nameController.text.length}/20',
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _birthYearFocus.requestFocus(),
                ),
                SizedBox(height: 14),
                _ProfileField(
                  label: 'BIRTH YEAR',
                  hintText: '예: 2002',
                  icon: Icons.calendar_month_outlined,
                  controller: _birthYearController,
                  focusNode: _birthYearFocus,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  trailing: _validBirthYear ? '확인 완료' : null,
                  trailingAccent: _validBirthYear,
                  onChanged: (_) => setState(() {
                    if (!_isMinor) _guardianConsent = false;
                  }),
                  onSubmitted: (_) {
                    if (_canSubmit) _submit();
                  },
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(3, 9, 3, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 13,
                        color: AppColors.muted,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '연령 확인용',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _isMinor
                      ? Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: _ConsentCard(
                            checked: _guardianConsent,
                            onTap: () => setState(
                              () => _guardianConsent = !_guardianConsent,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _BottomAction(
              enabled: _canSubmit,
              loading: _saving,
              onTap: _submit,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
            'SETUP  ·  01/03',
            style: TextStyle(
              color: AppColors.soft,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final hasName = name.isNotEmpty;
    final initial = hasName ? name.substring(0, 1).toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.text.withValues(alpha: .08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.text.withValues(alpha: .35),
                width: 1.5,
              ),
            ),
            child: Text(
              initial,
              style: TextStyle(
                color: AppColors.onAccent,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MY COURT NAME',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                SizedBox(height: 5),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Text(
                    hasName ? name : '코트 위 닉네임',
                    key: ValueKey(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasName ? AppColors.text : AppColors.muted,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.sports_basketball_rounded,
            color: AppColors.accent,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.hintText,
    required this.icon,
    required this.controller,
    required this.focusNode,
    required this.maxLength,
    required this.textInputAction,
    required this.onChanged,
    required this.onSubmitted,
    this.keyboardType,
    this.trailing,
    this.trailingAccent = false,
  });

  final String label;
  final String hintText;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxLength;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final String? trailing;
  final bool trailingAccent;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      padding: const EdgeInsets.fromLTRB(16, 13, 14, 10),
      decoration: BoxDecoration(
        color: focused
            ? AppColors.accent.withValues(alpha: .06)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: focused
              ? AppColors.accent
              : AppColors.text.withValues(alpha: .09),
          width: focused ? 1.4 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: focused
                  ? AppColors.accent.withValues(alpha: .13)
                  : AppColors.text.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: focused ? AppColors.accent : AppColors.soft,
              size: 19,
            ),
          ),
          SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: focused ? AppColors.accent : AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    if (trailing != null)
                      Text(
                        trailing!,
                        style: TextStyle(
                          color: trailingAccent
                              ? AppColors.success
                              : AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                SizedBox(
                  height: 32,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLength: maxLength,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    inputFormatters: keyboardType == TextInputType.number
                        ? [FilteringTextInputFormatter.digitsOnly]
                        : null,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    cursorColor: AppColors.accent,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.3,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      counterText: '',
                      hintText: hintText,
                      hintStyle: TextStyle(
                        color: AppColors.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      contentPadding: const EdgeInsets.only(top: 7),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
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

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: checked
                ? AppColors.accent.withValues(alpha: .09)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: checked
                  ? AppColors.accent.withValues(alpha: .65)
                  : AppColors.text.withValues(alpha: .09),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: checked ? AppColors.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: checked ? AppColors.accent : AppColors.muted,
                    width: 1.5,
                  ),
                ),
                child: checked
                    ? Icon(
                        Icons.check_rounded,
                        color: AppColors.onAccent,
                        size: 17,
                      )
                    : null,
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '보호자 동의를 받았어요',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '미성년자의 위치 기반 체크인 및 커뮤니티 이용 동의',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        34,
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
          stops: [0, .38, 1],
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 58,
        decoration: BoxDecoration(
          color: enabled ? AppColors.accent : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(19),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: .22),
                    blurRadius: 22,
                    offset: const Offset(0, 9),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('complete-profile'),
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(19),
            child: Center(
              child: loading
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        color: AppColors.onAccent,
                        strokeWidth: 2.2,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '다음',
                          style: TextStyle(
                            color: enabled
                                ? AppColors.onAccent
                                : AppColors.muted,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.4,
                          ),
                        ),
                        SizedBox(width: 9),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: enabled ? AppColors.onAccent : AppColors.muted,
                          size: 19,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileBackdrop extends StatelessWidget {
  const _ProfileBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -170,
            right: -155,
            child: Container(
              width: 390,
              height: 390,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: .13),
                    AppColors.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(top: 112, right: -68, child: _CourtArc()),
        ],
      ),
    );
  }
}

class _CourtArc extends StatelessWidget {
  const _CourtArc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.text.withValues(alpha: .055),
          width: 1.2,
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 80,
          height: 1.2,
          color: AppColors.text.withValues(alpha: .055),
        ),
      ),
    );
  }
}
