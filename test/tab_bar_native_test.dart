import 'package:cupertino_native_plus/cupertino_native_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform_views.dart';

Widget _tabBar({required int currentIndex, ValueChanged<int>? onTap}) =>
    CupertinoApp(
      home: Align(
        alignment: Alignment.bottomCenter,
        child: CNTabBar(
          items: const [
            CNTabBarItem(label: 'Home', icon: CNIcon.symbol('house')),
            CNTabBarItem(label: 'Settings', icon: CNIcon.symbol('gear')),
          ],
          currentIndex: currentIndex,
          onTap: onTap ?? (_) {},
        ),
      ),
    );

/// Pumps until the native tab bar is created, and returns its view id.
Future<int> _pumpUntilCreated(
  WidgetTester tester,
  FakePlatformViews views,
) async {
  // In debug builds native views wait for PlatformViewGuard.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  final id = views.onlyId;
  // Let the label refresh after creation run.
  await tester.pump(const Duration(milliseconds: 100));
  return id;
}

void main() {
  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

  setUp(() => PlatformVersion.debugShouldUseNativeGlassOverride = true);
  tearDown(() => PlatformVersion.debugShouldUseNativeGlassOverride = null);

  group('CNTabBar のネイティブのタブバー', () {
    testWidgets('選んでいるタブをもう一度押しても onTap を呼ぶ', (tester) async {
      final views = FakePlatformViews(tester);
      final taps = <int>[];
      await tester.pumpWidget(_tabBar(currentIndex: 0, onTap: taps.add));
      final id = await _pumpUntilCreated(tester, views);

      views.sendFromNative(id, const MethodCall('valueChanged', {'index': 0}));
      await tester.pump();
      views.sendFromNative(id, const MethodCall('valueChanged', {'index': 1}));
      await tester.pump();

      expect(taps, [0, 1]);
    }, variant: iOS);
  });
}
