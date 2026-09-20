import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'backend/backcourt_repository.dart';
import 'backend/models.dart';
import 'backend/push_notification_service.dart';
import 'firebase_options.dart';
import 'screens/app_access_gate.dart';
import 'screens/checkin_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/player_setup_screen.dart';
import 'screens/play_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'theme/app_theme.dart';

class BackcourtApp extends StatelessWidget {
  const BackcourtApp({
    super.key,
    this.useRealMap = true,
    this.userLocationLoader,
    this.onMapControllerReady,
    this.skipAuth = false,
    this.firebaseReadyOverride,
  });

  final bool useRealMap;
  final UserLocationLoader? userLocationLoader;
  final MapControllerReady? onMapControllerReady;
  final bool skipAuth;
  final bool? firebaseReadyOverride;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '빽코트',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: skipAuth
          ? AppShell(
              useRealMap: useRealMap,
              userLocationLoader: userLocationLoader,
              onMapControllerReady: onMapControllerReady,
            )
          : _AuthGate(
              firebaseReadyOverride: firebaseReadyOverride,
              appBuilder: (authService, repository, profile) => AppShell(
                useRealMap: useRealMap,
                userLocationLoader: userLocationLoader,
                onMapControllerReady: onMapControllerReady,
                onSignOut: authService.signOut,
                repository: repository,
                initialCourt: profile.homeCourt,
              ),
            ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.appBuilder, this.firebaseReadyOverride});

  final Widget Function(
    AuthService authService,
    BackcourtRepository repository,
    AppUserProfile profile,
  )
  appBuilder;
  final bool? firebaseReadyOverride;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<bool> _firebaseReady = _initializeFirebase();
  AuthService? _authService;
  BackcourtRepository? _repository;

  Future<bool> _initializeFirebase() async {
    final override = widget.firebaseReadyOverride;
    if (override != null) return override;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _firebaseReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AuthLoadingScreen();
        }
        if (snapshot.data != true) {
          return const LoginScreen(firebaseReady: false);
        }
        final authService = _authService ??= AuthService();
        return AppAccessGate(
          child: StreamBuilder<User?>(
            stream: authService.authStateChanges,
            builder: (context, authSnapshot) {
              if (authSnapshot.connectionState == ConnectionState.waiting) {
                return const _AuthLoadingScreen();
              }
              if (authSnapshot.data == null) {
                return LoginScreen(
                  firebaseReady: true,
                  authService: authService,
                );
              }
              final repository = _repository ??= BackcourtRepository();
              return _UserBootstrap(
                user: authSnapshot.data!,
                repository: repository,
                appBuilder: (profile) =>
                    widget.appBuilder(authService, repository, profile),
              );
            },
          ),
        );
      },
    );
  }
}

class _UserBootstrap extends StatefulWidget {
  const _UserBootstrap({
    required this.user,
    required this.repository,
    required this.appBuilder,
  });

  final User user;
  final BackcourtRepository repository;
  final Widget Function(AppUserProfile profile) appBuilder;

  @override
  State<_UserBootstrap> createState() => _UserBootstrapState();
}

class _UserBootstrapState extends State<_UserBootstrap> {
  late Future<void> _bootstrap;

  @override
  void initState() {
    super.initState();
    _bootstrap = widget.repository.ensureUserProfile(widget.user);
  }

  @override
  void didUpdateWidget(covariant _UserBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _bootstrap = widget.repository.ensureUserProfile(widget.user);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, bootstrapSnapshot) {
        if (bootstrapSnapshot.connectionState != ConnectionState.done) {
          return const _AuthLoadingScreen();
        }
        if (bootstrapSnapshot.hasError) {
          return _BackendErrorScreen(
            onRetry: () {
              setState(() {
                _bootstrap = widget.repository.ensureUserProfile(widget.user);
              });
            },
          );
        }
        return StreamBuilder<AppUserProfile?>(
          stream: widget.repository.watchCurrentProfile(),
          builder: (context, profileSnapshot) {
            if (!profileSnapshot.hasData) return const _AuthLoadingScreen();
            final profile = profileSnapshot.data!;
            if (!profile.isComplete) {
              return ProfileSetupScreen(
                repository: widget.repository,
                profile: profile,
              );
            }
            if (!profile.onboardingComplete) {
              return PlayerSetupScreen(
                repository: widget.repository,
                profile: profile,
              );
            }
            return widget.appBuilder(profile);
          },
        );
      },
    );
  }
}

class _BackendErrorScreen extends StatelessWidget {
  const _BackendErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 42),
              const SizedBox(height: 16),
              const Text('서버에 연결하지 못했어요.'),
              const SizedBox(height: 14),
              FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

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

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.useRealMap = true,
    this.userLocationLoader,
    this.onMapControllerReady,
    this.onSignOut,
    this.repository,
    this.initialCourt,
  });

  final bool useRealMap;
  final UserLocationLoader? userLocationLoader;
  final MapControllerReady? onMapControllerReady;
  final Future<void> Function()? onSignOut;
  final BackcourtRepository? repository;
  final CourtSummary? initialCourt;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _unselectedCourt = CourtSummary(
    id: 'sample-unselected',
    name: '코트를 선택해 주세요',
    latitude: 37.5665,
    longitude: 126.978,
  );
  static const _previewCourt = CourtSummary(
    id: 'sample-0',
    name: '한강 시민공원 농구장',
    latitude: 37.5272,
    longitude: 126.9347,
    facts: ['야외', '무료'],
  );

  int _currentIndex = 0;
  PushNotificationService? _pushNotifications;
  late CourtSummary _activeCourt;

  @override
  void initState() {
    super.initState();
    _activeCourt =
        widget.initialCourt ??
        (widget.repository == null ? _previewCourt : _unselectedCourt);
    _configurePushNotifications();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _pushNotifications?.dispose();
      _pushNotifications = null;
      _configurePushNotifications();
    }
    if (oldWidget.initialCourt?.id != widget.initialCourt?.id &&
        widget.initialCourt != null) {
      _activeCourt = widget.initialCourt!;
    }
  }

  void _configurePushNotifications() {
    final repository = widget.repository;
    if (repository == null) return;
    final service = PushNotificationService(
      repository: repository,
      onOpen: _handlePushOpen,
    );
    _pushNotifications = service;
    unawaited(service.start());
  }

  void _handlePushOpen(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type']?.toString();
    final tab = switch (type) {
      'live' || 'meetup' || 'meetup_join' || 'meetup_cancelled' => 1,
      'comment' => 3,
      _ => 0,
    };
    setState(() => _currentIndex = tab);
  }

  Future<void> _signOut() async {
    await _pushNotifications?.unregister();
    await widget.onSignOut?.call();
  }

  Future<void> _beforeDeleteAccount() async {
    await _pushNotifications?.unregister();
  }

  @override
  void dispose() {
    _pushNotifications?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsCourt =
        _activeCourt.id == _unselectedCourt.id &&
        _currentIndex >= 1 &&
        _currentIndex <= 3;
    final screens = <Widget>[
      MapScreen(
        useRealMap: widget.useRealMap,
        active: _currentIndex == 0,
        userLocationLoader: widget.userLocationLoader,
        onMapControllerReady: widget.onMapControllerReady,
        repository: widget.repository,
        initialCourt: widget.initialCourt,
        onCourtSelected: (court) => setState(() => _activeCourt = court),
      ),
      PlayScreen(repository: widget.repository, activeCourt: _activeCourt),
      CheckinScreen(repository: widget.repository, activeCourt: _activeCourt),
      FeedScreen(repository: widget.repository, activeCourt: _activeCourt),
      ProfileScreen(
        onSignOut: widget.onSignOut == null ? null : _signOut,
        beforeDeleteAccount: _beforeDeleteAccount,
        repository: widget.repository,
        activeCourt: _activeCourt,
      ),
    ];
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(index: _currentIndex, children: screens),
          ),
          if (needsCourt)
            Positioned.fill(
              child: _CourtSelectionRequired(
                onTap: () => setState(() => _currentIndex = 0),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}

class _CourtSelectionRequired extends StatelessWidget {
  const _CourtSelectionRequired({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 110),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('select-court-prompt'),
                onTap: onTap,
                borderRadius: BorderRadius.circular(28),
                child: Ink(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 34, 24, 27),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: .24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.place_rounded,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '코트를 선택해 주세요',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.7,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '코트 탭으로 이동',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.map_outlined, Icons.map_rounded, '코트'),
    (Icons.sensors_outlined, Icons.sensors_rounded, '플레이'),
    (Icons.near_me_outlined, Icons.near_me_rounded, '출석'),
    (Icons.dynamic_feed_outlined, Icons.dynamic_feed_rounded, '피드'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'MY'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.nav,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: List.generate(_items.length, (index) {
            final selected = index == currentIndex;
            final item = _items[index];
            return Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label: item.$3,
                child: InkWell(
                  key: ValueKey('nav-$index'),
                  onTap: () => onTap(index),
                  borderRadius: BorderRadius.circular(22),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: index == 2 ? 38 : 32,
                        height: index == 2 ? 38 : 28,
                        decoration: index == 2
                            ? BoxDecoration(
                                color: selected
                                    ? AppColors.accent
                                    : Colors.white,
                                shape: BoxShape.circle,
                              )
                            : null,
                        alignment: Alignment.center,
                        child: Icon(
                          selected ? item.$2 : item.$1,
                          size: index == 2 ? 20 : 22,
                          color: index == 2
                              ? Colors.black
                              : selected
                              ? Colors.white
                              : AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.$3,
                        style: TextStyle(
                          color: selected ? Colors.white : AppColors.muted,
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
