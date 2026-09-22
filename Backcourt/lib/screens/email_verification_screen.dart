import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _loading = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await action();
      if (mounted && success.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (!mounted) return;
      final message = error is AuthFlowException
          ? error.message
          : '잠시 후 다시 시도해주세요.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _check() => _run(() async {
    final verified = await widget.authService.reloadEmailVerification();
    if (!verified) throw const AuthFlowException('아직 인증되지 않았어요.');
  }, '');

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Image.asset('icon.png', width: 42, height: 42),
                const SizedBox(width: 10),
                const Text(
                  '빽코트',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const Spacer(),
            Icon(
              Icons.mark_email_read_outlined,
              color: AppColors.accent,
              size: 48,
            ),
            const SizedBox(height: 20),
            const Text(
              '이메일을 확인해주세요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 9),
            Text(
              '인증 메일의 링크를 누른 뒤 아래 버튼을 눌러주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: _loading ? null : _check,
              child: Text(_loading ? '확인 중' : '인증 완료'),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => _run(
                      widget.authService.resendEmailVerification,
                      '인증 메일을 다시 보냈어요.',
                    ),
              child: const Text('인증 메일 다시 보내기'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _loading ? null : widget.authService.signOut,
              child: const Text('다른 계정으로 로그인'),
            ),
          ],
        ),
      ),
    ),
  );
}
