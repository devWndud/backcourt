import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.firebaseReady, this.authService});

  final bool firebaseReady;
  final AuthService? authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  Future<void> _run(Future<void> Function() action) async {
    if (!widget.firebaseReady || widget.authService == null) {
      _showMessage('Firebase 프로젝트 설정이 필요해요. 설정 파일을 연결하면 바로 사용할 수 있어요.');
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await action();
    } catch (error) {
      _showMessage(_authMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openDirectLogin() async {
    if (!widget.firebaseReady || widget.authService == null) {
      _showMessage('Firebase 프로젝트 설정이 필요해요.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DirectAuthSheet(authService: widget.authService!),
    );
  }

  Future<void> _openPolicy(String path) async {
    final uri = Uri.parse('https://backcourt.kro.kr/$path/');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showMessage('페이지를 열 수 없어요. 잠시 후 다시 시도해 주세요.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Image.asset('icon.png', width: 44, height: 44),
                  SizedBox(width: 10),
                  Text(
                    '빽코트',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '일상에서,\n다시 코트로.',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 42,
                  height: 1.06,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2.2,
                ),
              ),
              SizedBox(height: 14),
              Text(
                '코트 · LIVE · 체크인 · 피드',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              if (!widget.firebaseReady) ...[
                Container(
                  key: const ValueKey('firebase-setup-banner'),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: .3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: AppColors.accent),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Firebase 프로젝트 연결 대기 중',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12),
              ],
              if (AuthService.kakaoLoginEnabled) ...[
                _LoginButton(
                  key: const ValueKey('login-kakao'),
                  label: '카카오로 시작하기',
                  background: const Color(0xFFFEE500),
                  foreground: const Color(0xFF191919),
                  leading: Text(
                    'K',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  onTap: () => _showMessage('카카오 로그인 서버 설정을 확인해주세요.'),
                ),
                SizedBox(height: 10),
              ],
              if (defaultTargetPlatform == TargetPlatform.iOS &&
                  AuthService.appleLoginEnabled) ...[
                _LoginButton(
                  key: const ValueKey('login-apple'),
                  label: 'Apple로 계속하기',
                  background: AppColors.text,
                  foreground: AppColors.inverseText,
                  leading: Icon(Icons.apple, size: 22),
                  loading: _loading,
                  onTap: () =>
                      _run(() => widget.authService!.signInWithApple()),
                ),
                SizedBox(height: 10),
              ],
              _LoginButton(
                key: const ValueKey('login-google'),
                label: 'Google로 계속하기',
                background: AppColors.text,
                foreground: AppColors.inverseText,
                leading: Text(
                  'G',
                  style: TextStyle(
                    color: Color(0xFF4285F4),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                loading: _loading,
                onTap: () => _run(() => widget.authService!.signInWithGoogle()),
              ),
              SizedBox(height: 10),
              _LoginButton(
                key: const ValueKey('login-direct'),
                label: AuthService.phoneLoginEnabled
                    ? '이메일 또는 전화번호'
                    : '이메일로 계속하기',
                background: AppColors.surfaceHigh,
                foreground: AppColors.text,
                leading: Icon(Icons.mail_outline_rounded, size: 20),
                onTap: _openDirectLogin,
              ),
              SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '계속하면 ',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  _PolicyLink(label: '이용약관', onTap: () => _openPolicy('terms')),
                  Text(
                    '과 ',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  _PolicyLink(
                    label: '개인정보 처리방침',
                    onTap: () => _openPolicy('privacy'),
                  ),
                  Text(
                    '에 동의합니다.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
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

class _PolicyLink extends StatelessWidget {
  const _PolicyLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.muted,
          ),
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.leading,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Widget leading;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(17),
        child: SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(left: 20, child: leading),
              if (loading)
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    color: foreground,
                    strokeWidth: 2.2,
                  ),
                )
              else
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
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

enum _DirectAuthMode { email, phone }

class DirectAuthSheet extends StatefulWidget {
  const DirectAuthSheet({super.key, required this.authService});

  final AuthService authService;

  @override
  State<DirectAuthSheet> createState() => _DirectAuthSheetState();
}

class _DirectAuthSheetState extends State<DirectAuthSheet> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController(text: '+82 ');
  final _smsController = TextEditingController();
  _DirectAuthMode _mode = _DirectAuthMode.email;
  bool _createAccount = false;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _verificationId;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _smsController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!email.contains('@') || password.length < 6) {
      setState(() => _error = '이메일과 6자 이상의 비밀번호를 확인해주세요.');
      return;
    }
    await _run(
      () => _createAccount
          ? widget.authService.createAccount(email: email, password: password)
          : widget.authService.signInWithEmail(
              email: email,
              password: password,
            ),
    );
  }

  Future<void> _submitPhone() async {
    if (_verificationId == null) {
      final phone = _phoneController.text.replaceAll(RegExp(r'[\s-]'), '');
      await _run(() async {
        final id = await widget.authService.sendPhoneCode(phone);
        if (mounted) setState(() => _verificationId = id);
      }, closeAfterSuccess: false);
      return;
    }
    if (_smsController.text.trim().length < 6) {
      setState(() => _error = '문자로 받은 인증번호를 입력해주세요.');
      return;
    }
    await _run(
      () => widget.authService.confirmPhoneCode(
        verificationId: _verificationId!,
        smsCode: _smsController.text.trim(),
      ),
    );
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = '이메일 주소를 먼저 입력해주세요.');
      return;
    }
    await _run(
      () => widget.authService.sendPasswordReset(email),
      closeAfterSuccess: false,
      successMessage: '비밀번호 재설정 메일을 보냈어요.',
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool closeAfterSuccess = true,
    String? successMessage,
  }) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
      if (successMessage != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      if (closeAfterSuccess && mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = _authMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailMode = _mode == _DirectAuthMode.email;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            child: Column(
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
                SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.accent,
                        size: 21,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '계정으로 시작',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.7,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surfaceHigh,
                        foregroundColor: AppColors.muted,
                      ),
                      icon: Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                if (AuthService.phoneLoginEnabled) ...[
                  _DirectAuthModeSwitch(
                    value: _mode,
                    onChanged: (value) => setState(() {
                      _mode = value;
                      _error = null;
                    }),
                  ),
                  SizedBox(height: 18),
                ],
                if (emailMode) ...[
                  TextField(
                    key: const ValueKey('auth-email-field'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      hintText: '이메일 주소',
                      prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                    ),
                  ),
                  SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('auth-password-field'),
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: _createAccount
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    onSubmitted: (_) => _submitEmail(),
                    decoration: InputDecoration(
                      hintText: '비밀번호 6자 이상',
                      prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        _createAccount ? '이미 계정이 있나요?' : '처음이신가요?',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _createAccount = !_createAccount;
                          _error = null;
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.text,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          minimumSize: const Size(0, 40),
                        ),
                        child: Text(_createAccount ? '로그인' : '회원가입'),
                      ),
                      const Spacer(),
                      if (!_createAccount)
                        TextButton(
                          onPressed: _loading ? null : _resetPassword,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.muted,
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            minimumSize: const Size(0, 40),
                          ),
                          child: const Text('비밀번호 찾기'),
                        ),
                    ],
                  ),
                ] else ...[
                  TextField(
                    key: const ValueKey('auth-phone-field'),
                    controller: _phoneController,
                    enabled: _verificationId == null,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: '휴대폰 번호',
                      prefixIcon: Icon(Icons.phone_iphone_rounded, size: 20),
                    ),
                  ),
                  if (_verificationId != null) ...[
                    SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('auth-sms-field'),
                      controller: _smsController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitPhone(),
                      decoration: InputDecoration(
                        hintText: '인증번호 6자리',
                        prefixIcon: Icon(Icons.password_rounded, size: 20),
                      ),
                    ),
                  ],
                ],
                if (_error != null) ...[
                  SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: AppColors.accentSoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 14),
                FilledButton(
                  key: const ValueKey('submit-direct-auth'),
                  onPressed: _loading
                      ? null
                      : emailMode
                      ? _submitEmail
                      : _submitPhone,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.text,
                    disabledBackgroundColor: AppColors.accent.withValues(
                      alpha: .45,
                    ),
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: Center(
                    child: _loading
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.text,
                              strokeWidth: 2.2,
                            ),
                          )
                        : Text(
                            emailMode
                                ? _createAccount
                                      ? '회원가입'
                                      : '로그인'
                                : _verificationId == null
                                ? '인증번호 받기'
                                : '인증하고 시작하기',
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

class _DirectAuthModeSwitch extends StatelessWidget {
  const _DirectAuthModeSwitch({required this.value, required this.onChanged});

  final _DirectAuthMode value;
  final ValueChanged<_DirectAuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.text.withValues(alpha: .06)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: value == _DirectAuthMode.email
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Container(
                width: constraints.maxWidth / 2,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _DirectAuthModeButton(
                    label: '이메일',
                    selected: value == _DirectAuthMode.email,
                    onTap: () => onChanged(_DirectAuthMode.email),
                  ),
                ),
                Expanded(
                  child: _DirectAuthModeButton(
                    label: '전화번호',
                    selected: value == _DirectAuthMode.phone,
                    onTap: () => onChanged(_DirectAuthMode.phone),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectAuthModeButton extends StatelessWidget {
  const _DirectAuthModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              color: selected ? AppColors.text : AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

String _authMessage(Object error) {
  if (error is AuthFlowException) return error.message;
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => '이메일 형식을 확인해주세요.',
      'invalid-credential' || 'wrong-password' => '이메일 또는 비밀번호가 맞지 않아요.',
      'email-already-in-use' => '이미 가입된 이메일이에요.',
      'weak-password' => '비밀번호를 6자 이상 입력해주세요.',
      'too-many-requests' => '요청이 너무 많아요. 잠시 후 다시 시도해주세요.',
      'invalid-verification-code' => '인증번호가 맞지 않아요.',
      'web-context-cancelled' || 'canceled' => 'Apple 로그인이 취소됐어요.',
      _ => error.message ?? '로그인 중 문제가 발생했어요.',
    };
  }
  return '로그인 중 문제가 발생했어요.';
}
