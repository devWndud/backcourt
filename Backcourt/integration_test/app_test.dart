import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:backcourt/app.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS 주요 화면을 이동하며 캡처한다', (tester) async {
    MapLibreMapController? mapController;
    await tester.pumpWidget(
      BackcourtApp(
        skipAuth: true,
        userLocationLoader: () async => const LatLng(37.4979, 127.0276),
        onMapControllerReady: (controller) => mapController = controller,
      ),
    );
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (mapController?.circles.isNotEmpty ?? false) break;
    }
    final controller = mapController!;
    expect(find.byKey(const ValueKey('selected-court-sheet')), findsNothing);
    await binding.takeScreenshot('01_map');

    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(const LatLng(36.2, 127.8), 6),
    );
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (controller.circles.length <= 25) break;
    }
    expect(controller.circles.length, inInclusiveRange(10, 25));

    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(const LatLng(37.5240, 126.9349), 15.2),
    );
    await tester.pump(const Duration(seconds: 1));
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.pump(const Duration(milliseconds: 300));
      if ((controller.cameraPosition?.zoom ?? 0) >= 15 &&
          controller.circles.any((circle) => circle.data?['kind'] == 'court')) {
        break;
      }
    }
    expect(
      controller.circles.where((circle) => circle.data?['kind'] == 'court'),
      isNotEmpty,
    );
    expect(
      controller.circles.where((circle) => circle.data?['kind'] == 'cluster'),
      isEmpty,
    );

    final courtHitTargets = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('court-hit-');
    });
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (courtHitTargets.evaluate().isNotEmpty) break;
    }
    expect(courtHitTargets, findsWidgets);
    await tester.tap(courtHitTargets.first);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('selected-court-sheet')), findsOneWidget);
    await binding.takeScreenshot('01_court_mini');
    final sheetSurface = find.byKey(const ValueKey('court-sheet-surface'));
    final collapsedTop = tester.getTopLeft(sheetSurface).dy;
    await tester.drag(sheetSurface, const Offset(0, -380));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(sheetSurface).dy, lessThan(collapsedTop - 150));
    expect(find.text('리뷰'), findsOneWidget);
    expect(find.text('랭킹'), findsOneWidget);
    expect(find.text('수정'), findsOneWidget);
    await binding.takeScreenshot('01_court_detail');

    await tester.tap(find.byTooltip('상세 정보 닫기'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('selected-court-sheet')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('my-location-button')));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byIcon(Icons.gps_fixed_rounded).evaluate().isNotEmpty) break;
    }
    expect(find.byIcon(Icons.gps_fixed_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('01_my_location');

    await tester.enterText(
      find.byKey(const ValueKey('court-search-field')),
      '영등포덩크',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find
          .byKey(const ValueKey('selected-court-sheet'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(find.text('영등포덩크'), findsWidgets);
    expect(find.byKey(const ValueKey('selected-court-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clear-court-search')));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('play-mode-switch')), findsOneWidget);
    expect(find.text('플레이'), findsWidgets);
    expect(
      find.byKey(const ValueKey('live-court-publish-button')),
      findsOneWidget,
    );
    await binding.takeScreenshot('02_live_court');
    await tester.tap(find.byKey(const ValueKey('live-court-publish-button')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const ValueKey('live-court-submit-button')),
      findsOneWidget,
    );
    await binding.takeScreenshot('02_live_court_create');
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('play-mode-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('약속'), findsWidgets);
    await binding.takeScreenshot('02_meetups');

    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('출석'), findsWidgets);
    await binding.takeScreenshot('03_checkin');

    await tester.tap(find.byKey(const ValueKey('nav-3')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('피드'), findsOneWidget);
    await binding.takeScreenshot('04_feed');

    await tester.tap(find.byKey(const ValueKey('nav-4')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('COURT PASSPORT'), findsOneWidget);
    await binding.takeScreenshot('05_profile');
  });
}
