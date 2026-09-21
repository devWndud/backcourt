import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backcourt/app.dart';
import 'package:backcourt/backend/app_release_config.dart';
import 'package:backcourt/backend/backcourt_repository.dart';
import 'package:backcourt/backend/models.dart';
import 'package:backcourt/backend/push_notification_service.dart';
import 'package:backcourt/screens/operator_reports_screen.dart';
import 'package:backcourt/screens/map_screen.dart';
import 'package:backcourt/screens/player_setup_screen.dart';
import 'package:backcourt/theme/app_theme.dart';
import 'package:backcourt/widgets/court_ranking_card.dart';

void main() {
  test('일반 빌드는 운영 푸시 API를 사용한다', () {
    expect(
      PushNotificationService.defaultApiBaseUrl,
      'https://backcourt.kro.kr',
    );
  });

  test('앱 버전을 숫자 기준으로 비교한다', () {
    expect(isVersionLower('1.0.9', '1.0.10'), isTrue);
    expect(isVersionLower('1.2.0+18', '1.2.0'), isFalse);
    expect(isVersionLower('2.0.0', '1.9.9'), isFalse);
    expect(isVersionLower('1.0.0', ''), isFalse);
  });

  test('점검이 필수 업데이트보다 먼저 적용된다', () {
    const config = AppReleaseConfig(
      maintenanceEnabled: true,
      minIosVersion: '2.0.0',
      latestIosVersion: '2.1.0',
    );
    final decision = config.decide(isIos: true, currentVersion: '1.0.0');
    expect(decision.action, AppReleaseAction.maintenance);
  });

  test('최소 버전과 최신 버전을 구분한다', () {
    const config = AppReleaseConfig(
      minAndroidVersion: '1.1.0',
      latestAndroidVersion: '1.3.0',
    );
    expect(
      config.decide(isIos: false, currentVersion: '1.0.0').action,
      AppReleaseAction.requiredUpdate,
    );
    expect(
      config.decide(isIos: false, currentVersion: '1.2.0').action,
      AppReleaseAction.optionalUpdate,
    );
    expect(
      config.decide(isIos: false, currentVersion: '1.3.0').action,
      AppReleaseAction.open,
    );
  });

  test('빽코트 아이디 형식은 3~20자 영문 소문자 기준으로 검사한다', () {
    expect(BackcourtRepository.isValidUsername('court.king'), isTrue);
    expect(BackcourtRepository.isValidUsername('Court_King'), isTrue);
    expect(BackcourtRepository.normalizeUsername(' Court_King '), 'court_king');
    expect(BackcourtRepository.isValidUsername('ab'), isFalse);
    expect(BackcourtRepository.isValidUsername('_court'), isFalse);
    expect(BackcourtRepository.isValidUsername('court_'), isFalse);
    expect(BackcourtRepository.isValidUsername('농구왕'), isFalse);
  });

  testWidgets('Firebase 연결 전에도 로그인 화면이 안전하게 표시된다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BackcourtApp(firebaseReadyOverride: false));
    await tester.pump();

    expect(find.text('일상에서,\n다시 코트로.'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-kakao')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-google')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-direct')), findsOneWidget);
    expect(find.byKey(const ValueKey('firebase-setup-banner')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('login-google')));
    await tester.pump();
    expect(find.textContaining('Firebase 프로젝트 설정'), findsOneWidget);
  });

  testWidgets('Apple 로그인은 iOS에서만 표시된다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(const BackcourtApp(firebaseReadyOverride: false));
    await tester.pump();
    expect(find.byKey(const ValueKey('login-apple')), findsOneWidget);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const BackcourtApp(firebaseReadyOverride: false));
    await tester.pump();
    expect(find.byKey(const ValueKey('login-apple')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('핵심 탭 이동과 GPS 출석 흐름이 동작한다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const BackcourtApp(useRealMap: false, skipAuth: true),
    );

    expect(find.byKey(const ValueKey('selected-court-sheet')), findsNothing);
    expect(find.byKey(const ValueKey('court-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-location-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('play-mode-switch')), findsOneWidget);
    expect(find.text('플레이'), findsWidgets);
    expect(find.text('15분 뒤 도착'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('출석'), findsWidgets);
    expect(find.byKey(const ValueKey('court-pass-card')), findsOneWidget);
    expect(find.text('자주 가는 코트까지 1회'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('check-in-button')));
    await tester.pump();
    expect(find.text('출석 완료'), findsOneWidget);
    expect(find.text('자주 가는 코트'), findsOneWidget);
    expect(find.text('홈코트까지 5회'), findsOneWidget);
    final now = DateTime.now();
    expect(find.text('${now.month}.${now.day} 출석 완료'), findsOneWidget);
  });

  testWidgets('코트 랭킹이 전체·달·주 기간을 전환한다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requestedPeriods = <CourtRankingPeriod>[];
    Stream<List<MonthlyPlayStat>> rankingStream(CourtRankingPeriod period) {
      requestedPeriods.add(period);
      return Stream.value([
        const MonthlyPlayStat(
          uid: 'me',
          displayName: '코트왕',
          username: 'court.king',
          monthKey: '2026-09',
          totalMinutes: 145,
          sessionCount: 3,
        ),
      ]);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CourtRankingCard(
              court: const CourtSummary(
                id: 'court-1',
                name: '테스트 농구장',
                latitude: 37.5,
                longitude: 127,
              ),
              previewStream: rankingStream,
              previewCurrentUid: 'me',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPeriods.last, CourtRankingPeriod.month);
    expect(find.text('코트왕 · 나'), findsOneWidget);
    expect(find.text('2시간 25분'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('court-ranking-period-all')));
    await tester.pumpAndSettle();
    expect(requestedPeriods.last, CourtRankingPeriod.all);
    expect(find.text('이 코트 누적 랭킹'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('court-ranking-period-week')));
    await tester.pumpAndSettle();
    expect(requestedPeriods.last, CourtRankingPeriod.week);
    expect(find.text('이번 주 월요일부터 오늘까지'), findsOneWidget);
  });

  testWidgets('가입 온보딩에서 지도로 홈코트와 플레이 스타일을 고른다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    CourtSummary? savedCourt;
    String? savedPosition;
    List<String>? savedStyles;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: PlayerSetupScreen(
          courtsOverride: const [
            CourtSummary(
              id: 'osm_node_3975396530',
              name: '잠실2동 농구장',
              latitude: 37.5129735,
              longitude: 127.0806893,
              address: '잠실2동',
            ),
          ],
          mapPickerOverride: (_) async => const CourtSummary(
            id: 'osm_node_3975396530',
            name: '잠실2동 농구장',
            latitude: 37.5129735,
            longitude: 127.0806893,
            address: '잠실2동',
          ),
          saveOverride: (court, position, styles) async {
            savedCourt = court;
            savedPosition = position;
            savedStyles = styles;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('setup-court-map')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('setup-court-map')));
    await tester.pump();
    expect(find.text('잠실2동 농구장'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('setup-continue')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('setup-play-step')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('setup-position-guard')));
    await tester.tap(find.byKey(const ValueKey('setup-style-shooting')));
    await tester.tap(find.byKey(const ValueKey('setup-style-defense')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('setup-continue')));
    await tester.pump();

    expect(savedCourt?.id, 'osm_node_3975396530');
    expect(savedPosition, 'guard');
    expect(savedStyles, ['shooting', 'defense']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('홈코트 지도에서 핀을 고르고 확정한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    CourtSummary? pickedCourt;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: MapScreen(
            useRealMap: false,
            pickerMode: true,
            onPickerClose: () {},
            onCourtSelected: (court) => pickedCourt = court,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('map-picker-back')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-marker-한강')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('map-court-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-court-confirm')));
    await tester.pump();
    expect(pickedCourt?.id, 'sample-0');
    expect(pickedCourt?.name, '한강 시민공원 농구장');
  });

  testWidgets('코트 미선택 안내를 누르면 코트 탭으로 이동한다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const AppShell(
          useRealMap: false,
          initialCourt: CourtSummary(
            id: 'sample-unselected',
            name: '코트를 선택해 주세요',
            latitude: 37.5665,
            longitude: 126.978,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('select-court-prompt')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('select-court-prompt')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('court-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('select-court-prompt')), findsNothing);
  });

  testWidgets('지금 코트 신호를 만들고 합류 상태를 바꿀 수 있다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const BackcourtApp(useRealMap: false, skipAuth: true),
    );
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('15분 뒤 도착'));
    await tester.pump();
    expect(find.text('도착 예정 · 취소'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-court-publish-button')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('LIVE 등록'), findsWidgets);
    expect(find.text('인원 모집'), findsWidgets);

    final submitButton = find.byKey(const ValueKey('live-court-submit-button'));
    await tester.ensureVisible(submitButton);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(submitButton);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('수정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('플레이 탭에서 LIVE와 약속을 전환하고 약속을 만들 수 있다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const BackcourtApp(useRealMap: false, skipAuth: true),
    );
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('play-mode-switch')), findsOneWidget);

    final indicator = find.byKey(const ValueKey('play-mode-indicator'));
    final startX = tester.getTopLeft(indicator).dx;
    await tester.tap(find.byKey(const ValueKey('play-mode-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    final middleX = tester.getTopLeft(indicator).dx;
    await tester.pump(const Duration(milliseconds: 160));
    final endX = tester.getTopLeft(indicator).dx;
    expect(middleX, greaterThan(startX));
    expect(endX, greaterThan(middleX));
    expect(find.text('약속'), findsWidgets);
    expect(find.text('전체'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('create-meetup-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('약속 만들기'), findsWidgets);
    expect(find.text('정원'), findsOneWidget);
    expect(find.text('6명'), findsOneWidget);

    final submit = find.byKey(const ValueKey('submit-meetup'));
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('submit-meetup')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('play-mode-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('live-court-publish-button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('플레이 탭에서 저장한 홈코트를 바로 바꾼다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const courts = [
      CourtSummary(
        id: 'court-1',
        name: '천안시청 농구장',
        latitude: 36.8151,
        longitude: 127.1139,
      ),
      CourtSummary(
        id: 'court-2',
        name: '천안종합운동장 농구장',
        latitude: 36.8187,
        longitude: 127.1162,
      ),
      CourtSummary(
        id: 'court-3',
        name: '불당동 체육공원 농구장',
        latitude: 36.8082,
        longitude: 127.1084,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AppShell(
          useRealMap: false,
          initialCourt: courts[0],
          homeCourts: courts,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const ValueKey('home-court-switcher')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('홈코트'), findsWidgets);
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('홈코트 3개 저장됨'), findsOneWidget);

    await tester.tap(find.text('천안종합운동장 농구장'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('천안종합운동장 농구장'), findsOneWidget);
    expect(find.text('3/3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MY 설정이 빽코트 전용 시트로 표시된다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const BackcourtApp(useRealMap: false, skipAuth: true),
    );
    await tester.tap(find.byKey(const ValueKey('nav-4')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const ValueKey('profile-settings-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('앱 권한'), findsOneWidget);
    expect(find.text('화면 스타일'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('운영자가 코트 제보를 확인하고 승인할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final report = CourtReport(
      id: 'request-1',
      courtId: 'osm_way_123',
      currentName: '잠실2동 농구장',
      requestedName: '잠실 한강공원 농구장',
      reason: '현장 안내판에 적힌 공식 명칭입니다.',
      uid: 'user-1',
      requesterName: '코트러너',
      type: CourtReportType.name,
      status: CourtReportStatus.pending,
      createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
      latitude: 37.51,
      longitude: 127.08,
    );
    CourtReportStatus? reviewedAs;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: OperatorReportsScreen(
          previewReports: Stream.value([report]),
          onPreviewReview: (report, status, note) async {
            reviewedAs = status;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('코트 데이터 센터'), findsOneWidget);
    expect(find.text('1건을 확인해주세요'), findsOneWidget);
    expect(find.text('잠실 한강공원 농구장'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('court-report-request-1')));
    await tester.pumpAndSettle();
    expect(find.text('코트명 수정 제보'), findsOneWidget);
    expect(find.text('현장 안내판에 적힌 공식 명칭입니다.'), findsWidgets);

    await tester.tap(find.text('승인'));
    await tester.pumpAndSettle();
    expect(find.text('이 제보를 승인할까요?'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('confirm-court-report-decision')),
    );
    await tester.pumpAndSettle();
    expect(reviewedAs, CourtReportStatus.approved);
    expect(find.text('코트명이 지도 데이터에 반영됐어요.'), findsOneWidget);
  });
}
