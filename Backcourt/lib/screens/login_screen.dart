import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
                  const SizedBox(width: 10),
                  const Text(
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
              const Text(
                '일상에서,\n다시 코트로.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  height: 1.06,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2.2,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '코트 · LIVE · 출석 · 피드',
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
                  child: const Row(
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
                const SizedBox(height: 12),
              ],
              _LoginButton(
                key: const ValueKey('login-kakao'),
                label: '카카오로 시작하기',
                background: const Color(0xFFFEE500),
                foreground: const Color(0xFF191919),
                leading: const Text(
                  'K',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                onTap: () =>
                    _showMessage('카카오 로그인은 FastAPI 인증 서버를 연결한 뒤 활성화돼요.'),
              ),
              const SizedBox(height: 10),
              if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                _LoginButton(
                  key: const ValueKey('login-apple'),
                  label: 'Apple로 계속하기',
                  background: Colors.white,
                  foreground: Colors.black,
                  leading: const Icon(Icons.apple, size: 22),
                  loading: _loading,
                  onTap: () =>
                      _run(() => widget.authService!.signInWithApple()),
                ),
                const SizedBox(height: 10),
              ],
              _LoginButton(
                key: const ValueKey('login-google'),
                label: 'Google로 계속하기',
                background: Colors.white,
                foreground: Colors.black,
                leading: const Text(
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
              const SizedBox(height: 10),
              _LoginButton(
                key: const ValueKey('login-direct'),
                label: '이메일 또는 전화번호',
                background: AppColors.surfaceHigh,
                foreground: Colors.white,
                leading: const Icon(Icons.mail_outline_rounded, size: 20),
                onTap: _openDirectLogin,
              ),
              const SizedBox(height: 16),
              const Text(
                '계속하면 빽코트의 이용약관과 개인정보 처리방침에 동의하게 됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
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

  Future<void> _run(
    Future<void> Function() action, {
    bool closeAfterSuccess = true,
  }) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
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
                const SizedBox(height: 22),
                Text(
                  '직접 로그인',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                SegmentedButton<_DirectAuthMode>(
                  segments: const [
                    ButtonSegment(
                      value: _DirectAuthMode.email,
                      label: Text('이메일'),
                    ),
                    ButtonSegment(
                      value: _DirectAuthMode.phone,
                      label: Text('전화번호'),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => setState(() {
                    _mode = value.first;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 16),
                if (emailMode) ...[
                  TextField(
                    key: const ValueKey('auth-email-field'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '이메일'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('auth-password-field'),
                    controller: _passwordController,
                    obscureText: true,
                    onSubmitted: (_) => _submitEmail(),
                    decoration: const InputDecoration(labelText: '비밀번호'),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('처음이라면 회원가입'),
                    value: _createAccount,
                    onChanged: (value) =>
                        setState(() => _createAccount = value),
                  ),
                ] else ...[
                  TextField(
                    key: const ValueKey('auth-phone-field'),
                    controller: _phoneController,
                    enabled: _verificationId == null,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: '전화번호'),
                  ),
                  if (_verificationId != null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('auth-sms-field'),
                      controller: _smsController,
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _submitPhone(),
                      decoration: const InputDecoration(labelText: '인증번호 6자리'),
                    ),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('submit-direct-auth'),
                  onPressed: _loading
                      ? null
                      : emailMode
                      ? _submitEmail
                      : _submitPhone,
                  child: Center(
                    child: _loading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              color: Colors.black,
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
