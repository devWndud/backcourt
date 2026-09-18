import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/app_release_config.dart';
import '../theme/app_theme.dart';

class AppAccessGate extends StatefulWidget {
  const AppAccessGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppAccessGate> createState() => _AppAccessGateState();
}

class _AppAccessGateState extends State<AppAccessGate> {
  late Future<String> _version;
  late Stream<Map<String, dynamic>> _configStream;
  String? _promptedVersion;

  @override
  void initState() {
    super.initState();
    _version = PackageInfo.fromPlatform().then((info) => info.version);
    _configStream = _releaseConfigStream();
  }

  Stream<Map<String, dynamic>> _releaseConfigStream() => FirebaseFirestore
      .instance
      .collection('app_config')
      .doc('release')
      .snapshots()
      .map((snapshot) => snapshot.data() ?? const <String, dynamic>{});

  void _retry() {
    setState(() {
      _version = PackageInfo.fromPlatform().then((info) => info.version);
      _configStream = _releaseConfigStream();
    });
  }

  Future<void> _openStore(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
      _showStoreError();
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showStoreError();
  }

  void _showStoreError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('스토어를 열지 못했어요.')));
  }

  void _queueOptionalUpdate(AppReleaseDecision decision) {
    if (_promptedVersion == decision.targetVersion) return;
    _promptedVersion = decision.targetVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('업데이트'),
          content: Text(decision.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('나중에'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                unawaited(_openStore(decision.storeUrl));
              },
              child: const Text('업데이트'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _version,
      builder: (context, versionSnapshot) {
        if (versionSnapshot.hasError) return widget.child;
        if (!versionSnapshot.hasData) return const _GateLoadingScreen();
        return StreamBuilder<Map<String, dynamic>>(
          stream: _configStream,
          initialData: const <String, dynamic>{},
          builder: (context, configSnapshot) {
            if (configSnapshot.hasError) return widget.child;
            if (!configSnapshot.hasData) return const _GateLoadingScreen();
            final config = AppReleaseConfig.fromMap(configSnapshot.data!);
            final decision = config.decide(
              isIos: defaultTargetPlatform == TargetPlatform.iOS,
              currentVersion: versionSnapshot.data!,
            );
            switch (decision.action) {
              case AppReleaseAction.maintenance:
                return _StatusScreen(
                  icon: Icons.sports_basketball_rounded,
                  label: 'BACKCOURT',
                  title: '점검 중',
                  message: decision.message,
                  maintenanceEndsAt: decision.maintenanceEndsAt,
                  buttonLabel: '다시 확인',
                  onPressed: _retry,
                );
              case AppReleaseAction.requiredUpdate:
                return _StatusScreen(
                  icon: Icons.system_update_rounded,
                  label: 'BACKCOURT',
                  title: '업데이트 필요',
                  message: decision.message,
                  buttonLabel: '업데이트',
                  onPressed: () => _openStore(decision.storeUrl),
                );
              case AppReleaseAction.optionalUpdate:
                _queueOptionalUpdate(decision);
                return widget.child;
              case AppReleaseAction.open:
                return widget.child;
            }
          },
        );
      },
    );
  }
}

class _GateLoadingScreen extends StatelessWidget {
  const _GateLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.background,
      child: Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}

class _StatusScreen extends StatelessWidget {
  const _StatusScreen({
    required this.icon,
    required this.label,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
    this.maintenanceEndsAt,
  });

  final IconData icon;
  final String label;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;
  final DateTime? maintenanceEndsAt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Image.asset('icon.png', width: 38, height: 38),
                  const SizedBox(width: 9),
                  const Text(
                    '빽코트',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: .28),
                  ),
                ),
                child: Icon(icon, color: AppColors.accent, size: 29),
              ),
              const SizedBox(height: 24),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.6,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 14,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (maintenanceEndsAt != null) ...[
                const SizedBox(height: 10),
                Text(
                  '예정 · ${_dateLabel(maintenanceEndsAt!)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  buttonLabel,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}월 ${local.day}일 $hour:$minute';
}
