import 'dart:async';

import 'package:cupertino_native_plus/cupertino_native_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform_views.dart';

Widget _tabBar({
  required int currentIndex,
  ValueChanged<int>? onTap,
  TextStyle? labelStyle,
  TextStyle? activeLabelStyle,
  bool split = false,
}) => CupertinoApp(
  home: Align(
    alignment: Alignment.bottomCenter,
    child: CNTabBar(
      items: const [
        CNTabBarItem(label: 'Home', icon: CNIcon.symbol('house')),
        CNTabBarItem(label: 'Settings', icon: CNIcon.symbol('gear')),
      ],
      currentIndex: currentIndex,
      onTap: onTap ?? (_) {},
      labelStyle: labelStyle,
      activeLabelStyle: activeLabelStyle,
      split: split,
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

/// The style the native bar has: the last one sent with [method], or the one
/// it was created with ([param]).
Object? _nativeStyle(
  FakePlatformViews views,
  int id,
  String method,
  String param,
) {
  final sent = [
    for (final call in views.calls[id]!)
      if (call.method == method) call.arguments,
  ];
  return sent.isEmpty ? views.created[id]![param] : sent.last;
}

const _regular = TextStyle(fontSize: 10);
const _bold = TextStyle(fontSize: 10, fontWeight: FontWeight.bold);
const _regularSent = {'fontSize': 10.0};
const _boldSent = {'fontSize': 10.0, 'fontWeight': 700};

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

    testWidgets('ラベルの書式が同じなら、作り直すたびには送らない', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _tabBar(currentIndex: 0, labelStyle: _bold, activeLabelStyle: _bold),
      );
      final id = await _pumpUntilCreated(tester, views);
      views.calls[id]!.clear();

      await tester.pumpWidget(
        _tabBar(currentIndex: 1, labelStyle: _bold, activeLabelStyle: _bold),
      );
      await tester.pump();

      expect(views.calls[id]!.map((call) => call.method), ['setSelectedIndex']);
    }, variant: iOS);

    testWidgets('ラベルの書式を送っている途中に元へ戻しても、最後の書式にする', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _tabBar(
          currentIndex: 0,
          labelStyle: _regular,
          activeLabelStyle: _regular,
        ),
      );
      final id = await _pumpUntilCreated(tester, views);

      views.replying = Completer<void>();
      await tester.pumpWidget(
        _tabBar(currentIndex: 0, labelStyle: _bold, activeLabelStyle: _bold),
      );
      await tester.pumpWidget(
        _tabBar(
          currentIndex: 0,
          labelStyle: _regular,
          activeLabelStyle: _regular,
        ),
      );
      views.replying!.complete();
      await tester.pump();

      expect(
        _nativeStyle(views, id, 'setLabelStyle', 'labelStyle'),
        _regularSent,
      );
      expect(
        _nativeStyle(views, id, 'setActiveLabelStyle', 'activeLabelStyle'),
        _regularSent,
      );
    }, variant: iOS);

    testWidgets('ビューができる前に変わったラベルの書式を、できた後に送る', (tester) async {
      final views = FakePlatformViews(tester)..creating = Completer<void>();
      await tester.pumpWidget(
        _tabBar(
          currentIndex: 0,
          labelStyle: _regular,
          activeLabelStyle: _regular,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final id = views.onlyId;
      expect(views.created[id]!['labelStyle'], _regularSent);

      await tester.pumpWidget(
        _tabBar(currentIndex: 0, labelStyle: _bold, activeLabelStyle: _bold),
      );
      await tester.pump();
      views.creating!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_nativeStyle(views, id, 'setLabelStyle', 'labelStyle'), _boldSent);
      expect(
        _nativeStyle(views, id, 'setActiveLabelStyle', 'activeLabelStyle'),
        _boldSent,
      );
    }, variant: iOS);

    testWidgets('選んだタブの書式だけを送っている途中に元へ戻しても、最後の書式にする', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _tabBar(
          currentIndex: 0,
          labelStyle: _regular,
          activeLabelStyle: _regular,
        ),
      );
      final id = await _pumpUntilCreated(tester, views);

      views.replying = Completer<void>();
      await tester.pumpWidget(
        _tabBar(currentIndex: 0, labelStyle: _regular, activeLabelStyle: _bold),
      );
      expect(
        _nativeStyle(views, id, 'setActiveLabelStyle', 'activeLabelStyle'),
        _boldSent,
      );
      await tester.pumpWidget(
        _tabBar(
          currentIndex: 0,
          labelStyle: _regular,
          activeLabelStyle: _regular,
        ),
      );
      views.replying!.complete();
      await tester.pump();

      expect(
        _nativeStyle(views, id, 'setActiveLabelStyle', 'activeLabelStyle'),
        _regularSent,
      );
    }, variant: iOS);

    testWidgets('ビューができる前に書式を外したら、できた後に外す', (tester) async {
      final views = FakePlatformViews(tester)..creating = Completer<void>();
      await tester.pumpWidget(
        _tabBar(currentIndex: 0, labelStyle: _bold, activeLabelStyle: _bold),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final id = views.onlyId;
      expect(views.created[id]!['labelStyle'], _boldSent);
      expect(views.created[id]!['activeLabelStyle'], _boldSent);

      await tester.pumpWidget(_tabBar(currentIndex: 0));
      await tester.pump();
      views.creating!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final sent = [
        for (final call in views.calls[id]!)
          if (call.method == 'setLabelStyle' ||
              call.method == 'setActiveLabelStyle')
            (call.method, call.arguments),
      ];
      expect(sent, [('setLabelStyle', null), ('setActiveLabelStyle', null)]);
    }, variant: iOS);

    testWidgets('レイアウトを変えてバーが作り直されたら、同じ書式でも送り直す', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _tabBar(currentIndex: 0, labelStyle: _bold, activeLabelStyle: _bold),
      );
      final id = await _pumpUntilCreated(tester, views);
      views.calls[id]!.clear();

      await tester.pumpWidget(
        _tabBar(
          currentIndex: 0,
          labelStyle: _bold,
          activeLabelStyle: _bold,
          split: true,
        ),
      );
      await tester.pump();

      final methods = [for (final call in views.calls[id]!) call.method];
      final layout = methods.indexOf('setLayout');
      expect(layout, isNot(-1));
      expect(
        methods.sublist(layout),
        containsAll(['setLabelStyle', 'setActiveLabelStyle']),
      );
      expect(_nativeStyle(views, id, 'setLabelStyle', 'labelStyle'), _boldSent);
      expect(
        _nativeStyle(views, id, 'setActiveLabelStyle', 'activeLabelStyle'),
        _boldSent,
      );

      // Without a layout change, the same styles aren't sent again.
      await tester.pump(const Duration(milliseconds: 100));
      views.calls[id]!.clear();
      await tester.pumpWidget(
        _tabBar(
          currentIndex: 1,
          labelStyle: _bold,
          activeLabelStyle: _bold,
          split: true,
        ),
      );
      await tester.pump();

      expect(views.calls[id]!.map((call) => call.method), ['setSelectedIndex']);
    }, variant: iOS);

    testWidgets('ラベルの書式が変わったら送る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _tabBar(
          currentIndex: 0,
          labelStyle: _regular,
          activeLabelStyle: _regular,
        ),
      );
      final id = await _pumpUntilCreated(tester, views);
      views.calls[id]!.clear();

      await tester.pumpWidget(
        _tabBar(currentIndex: 0, labelStyle: _bold, activeLabelStyle: _bold),
      );
      await tester.pump();

      final sent = {
        for (final call in views.calls[id]!) call.method: call.arguments,
      };
      expect(sent['setLabelStyle'], {'fontSize': 10.0, 'fontWeight': 700});
      expect(sent['setActiveLabelStyle'], {
        'fontSize': 10.0,
        'fontWeight': 700,
      });
    }, variant: iOS);
  });
}
