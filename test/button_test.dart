import 'dart:async';

import 'package:cupertino_native_plus/cupertino_native_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform_views.dart';

extension on FakePlatformViews {
  /// The `pressed` values sent to the view with `setPressed`.
  List<Object?> presses(int id) => [
    for (final call in calls[id]!)
      if (call.method == 'setPressed')
        (call.arguments as Map<Object?, Object?>)['pressed'],
  ];

  /// The widths sent to the view with `setButtonWidth`.
  List<Object?> widths(int id) => [
    for (final call in calls[id]!)
      if (call.method == 'setButtonWidth')
        (call.arguments as Map<Object?, Object?>)['width'],
  ];

  /// The titles sent to the view with `setButtonTitle`.
  List<Object?> titles(int id) => [
    for (final call in calls[id]!)
      if (call.method == 'setButtonTitle')
        (call.arguments as Map<Object?, Object?>)['title'],
  ];

  /// The arguments of the `setButtonWidth` calls.
  List<Map<Object?, Object?>> widthCalls(int id) => [
    for (final call in calls[id]!)
      if (call.method == 'setButtonWidth')
        call.arguments! as Map<Object?, Object?>,
  ];
}

Widget _button(CNButtonConfig config, {bool enabled = true}) => CupertinoApp(
  home: Center(
    child: CNButton(
      label: 'タブ',
      onPressed: enabled ? () {} : null,
      config: config,
    ),
  ),
);

Widget _labeled(String label, CNButtonConfig config) => CupertinoApp(
  home: Center(
    child: CNButton(label: label, onPressed: () {}, config: config),
  ),
);

/// スクロールの中に置くボタン（タブなど）
const _delayed = CNButtonConfig(width: 100, minHeight: 36, delayedPress: true);

Future<TestGesture> _touch(WidgetTester tester) =>
    tester.startGesture(tester.getCenter(find.byType(CNButton)));

void main() {
  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

  setUp(() => PlatformVersion.debugShouldUseNativeGlassOverride = true);
  tearDown(() => PlatformVersion.debugShouldUseNativeGlassOverride = null);

  group('CNButton の押したときの膨らみ', () {
    testWidgets('ふつうは、指が触れたらすぐに押した状態を送る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 100, minHeight: 36)),
      );
      await tester.pump();
      final id = views.onlyId;

      final gesture = await _touch(tester);
      await tester.pump();
      expect(views.presses(id), [true]);

      await gesture.up();
      await tester.pump();
      expect(views.presses(id), [true, false]);
      expect(views.created[id]!['delayedPress'], isFalse);
    }, variant: iOS);

    testWidgets('delayedPress では、ネイティブのガラスに触れても膨らませない設定で作る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_button(_delayed));
      await tester.pump();

      expect(views.created[views.onlyId]!['delayedPress'], isTrue);
    }, variant: iOS);

    testWidgets('delayedPress では、触れてすぐには送らず、動かさずに待ってから押した状態を送る', (
      tester,
    ) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_button(_delayed));
      await tester.pump();
      final id = views.onlyId;

      final gesture = await _touch(tester);
      await tester.pump(kPressTimeout - const Duration(milliseconds: 1));
      expect(views.presses(id), isEmpty);

      await tester.pump(const Duration(milliseconds: 2));
      expect(views.presses(id), [true]);

      await gesture.up();
      await tester.pump();
      expect(views.presses(id), [true, false]);
    }, variant: iOS);

    testWidgets('delayedPress では、ボタンの上から始めたスクロールで膨らませない', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_button(_delayed));
      await tester.pump();
      final id = views.onlyId;

      final gesture = await _touch(tester);
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump(kPressTimeout);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(views.presses(id), isEmpty);
    }, variant: iOS);

    testWidgets('delayedPress で、すぐに離したタップでも、少しの間だけ膨らませる', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_button(_delayed));
      await tester.pump();
      final id = views.onlyId;

      final gesture = await _touch(tester);
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.up();
      await tester.pump();
      expect(views.presses(id), [true]);

      await tester.pump(const Duration(milliseconds: 300));
      expect(views.presses(id), [true, false]);
    }, variant: iOS);
  });

  group('CNButton の delayedPress の細かい場合', () {
    testWidgets('押せないボタンは、待っても膨らませない', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_button(_delayed, enabled: false));
      await tester.pump();
      final id = views.onlyId;

      final gesture = await _touch(tester);
      await tester.pump(kPressTimeout * 2);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(views.presses(id), isEmpty);
    }, variant: iOS);

    testWidgets('押している間に押せなくなったら、膨らみを戻す', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_button(_delayed));
      await tester.pump();
      final id = views.onlyId;

      final gesture = await _touch(tester);
      await tester.pump(kPressTimeout * 2);
      expect(views.presses(id), [true]);

      await tester.pumpWidget(_button(_delayed, enabled: false));
      await tester.pump();
      expect(views.presses(id), [true, false]);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(views.presses(id), [true, false]);
    }, variant: iOS);

    testWidgets('指の動きが取り消されたら、膨らみを戻す', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_button(_delayed));
      await tester.pump();
      final id = views.onlyId;

      final gesture = await _touch(tester);
      await tester.pump(kPressTimeout * 2);
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 300));

      expect(views.presses(id), [true, false]);
    }, variant: iOS);

    testWidgets('待っている間にボタンが消えても、後から何も送らない', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_button(_delayed));
      await tester.pump();
      final id = views.onlyId;

      final gesture = await _touch(tester);
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpWidget(const CupertinoApp(home: SizedBox()));
      await tester.pump(kPressTimeout * 2);
      await gesture.up();

      expect(views.presses(id), isEmpty);
    }, variant: iOS);

    testWidgets('タップの短い膨らみの間にまた触れてスクロールしたら、膨らみを戻して後から送らない', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_button(_delayed));
      await tester.pump();
      final id = views.onlyId;

      final tap = await _touch(tester);
      await tester.pump(const Duration(milliseconds: 30));
      await tap.up();
      await tester.pump();
      expect(views.presses(id), [true]);

      final drag = await _touch(tester);
      await tester.pump(const Duration(milliseconds: 30));
      await drag.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await drag.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(views.presses(id), [true, false]);
    }, variant: iOS);

    testWidgets('2本目の指は、1本目の指の押し方を変えない', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_button(_delayed));
      await tester.pump();
      final id = views.onlyId;

      final first = await _touch(tester);
      await tester.pump(const Duration(milliseconds: 30));
      final second = await tester.startGesture(
        tester.getCenter(find.byType(CNButton)),
        pointer: 7,
      );
      await tester.pump(const Duration(milliseconds: 10));
      await second.up();
      await tester.pump();
      // 2本目のすぐ離した指を、タップとして扱わない
      expect(views.presses(id), isEmpty);

      await tester.pump(kPressTimeout);
      expect(views.presses(id), [true]);

      await first.up();
      await tester.pump();
      expect(views.presses(id), [true, false]);
    }, variant: iOS);
  });

  group('CNButton の幅', () {
    testWidgets('幅を決めた文字のボタンは、ネイティブの大きさを待たずにその幅にする', (tester) async {
      FakePlatformViews(tester);
      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 100, minHeight: 36)),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(CNButton)), const Size(100, 36));
    }, variant: iOS);

    testWidgets('作った後で幅が変わったら、ネイティブのボタンにも新しい幅を送る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();
      final id = views.onlyId;
      expect(views.created[id]!['buttonWidth'], 70);

      // 例：タブの件数が後から読み込まれて、文字が長くなった
      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 87, minHeight: 36)),
      );
      await tester.pump();

      expect(views.widths(id), [87]);
      expect(tester.getSize(find.byType(CNButton)), const Size(87, 36));
    }, variant: iOS);
  });

  group('CNButton の幅の送り方', () {
    testWidgets('幅を送っている間に元の幅に戻したら、元の幅も送る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();
      final id = views.onlyId;

      final sending = Completer<void>();
      views.replyingTo['setButtonWidth'] = sending;
      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 87, minHeight: 36)),
      );
      await tester.pump();
      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();
      sending.complete();
      await tester.pump();

      expect(views.widths(id), [87, 70]);
    }, variant: iOS);

    testWidgets('ビューを作っている間に幅が変わったら、できた後に新しい幅を送る', (tester) async {
      final views = FakePlatformViews(tester)..creating = Completer<void>();
      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();
      final id = views.onlyId;
      expect(views.created[id]!['buttonWidth'], 70);

      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 87, minHeight: 36)),
      );
      await tester.pump();
      views.creating!.complete();
      await tester.pump();
      await tester.pump();

      expect(views.widths(id), [87]);
    }, variant: iOS);

    testWidgets('幅を外したら、広がるかどうかも一緒に送る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();
      final id = views.onlyId;
      expect(views.created[id]!['buttonExpandWidth'], isFalse);

      await tester.pumpWidget(_button(const CNButtonConfig(minHeight: 36)));
      await tester.pump();

      expect(views.widthCalls(id).single['width'], isNull);
      expect(views.widthCalls(id).single['expandWidth'], isTrue);
    }, variant: iOS);

    testWidgets('幅を外す送信に失敗したら、次に同期するときに送り直す', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _button(const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();
      final id = views.onlyId;

      views.failingMethods.add('setButtonWidth');
      await tester.pumpWidget(_button(const CNButtonConfig(minHeight: 36)));
      await tester.pump();
      expect(views.widthCalls(id), hasLength(1));

      views.failingMethods.clear();
      // 同じ設定のまま、次の同期が起きる
      await tester.pumpWidget(_button(const CNButtonConfig(minHeight: 36)));
      await tester.pump();

      expect(views.widthCalls(id), hasLength(2));
      expect(views.widthCalls(id).last['width'], isNull);
      expect(views.widthCalls(id).last['expandWidth'], isTrue);
    }, variant: iOS);

    testWidgets(
      'macOS では幅の変更を送らない（受け口が無い）',
      (tester) async {
        final views = FakePlatformViews(tester);
        await tester.pumpWidget(
          _button(const CNButtonConfig(width: 70, minHeight: 36)),
        );
        await tester.pump();
        final id = views.onlyId;

        await tester.pumpWidget(
          _button(const CNButtonConfig(width: 87, minHeight: 36)),
        );
        await tester.pump();

        expect(views.widths(id), isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });

  group('CNButton の文字と幅を一緒に変えたとき', () {
    testWidgets('文字と幅が一緒に変わったら、1 回でまとめて送る（長い文字が古い幅に入って「…」にならないように）', (
      tester,
    ) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _labeled('ToDo', const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();
      final id = views.onlyId;

      // 例：タブの件数が後から読み込まれて、文字が長くなった
      await tester.pumpWidget(
        _labeled('ToDo  6', const CNButtonConfig(width: 87, minHeight: 36)),
      );
      await tester.pump();

      expect(views.titles(id), isEmpty);
      expect(views.widthCalls(id), hasLength(1));
      expect(views.widthCalls(id).single['width'], 87);
      expect(views.widthCalls(id).single['title'], 'ToDo  6');
    }, variant: iOS);

    testWidgets('幅だけが変わったときは、文字を送らない', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _labeled('ToDo', const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();
      final id = views.onlyId;

      await tester.pumpWidget(
        _labeled('ToDo', const CNButtonConfig(width: 87, minHeight: 36)),
      );
      await tester.pump();

      expect(views.widthCalls(id).single.containsKey('title'), isFalse);
    }, variant: iOS);

    testWidgets('文字だけが変わったときは、これまでどおり文字だけを送る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _labeled('ToDo', const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();
      final id = views.onlyId;

      await tester.pumpWidget(
        _labeled('Todo', const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();

      expect(views.titles(id), ['Todo']);
      expect(views.widthCalls(id), isEmpty);
    }, variant: iOS);

    testWidgets('まとめた送信に失敗したら、次に同期するときに文字も送り直す', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _labeled('ToDo', const CNButtonConfig(width: 70, minHeight: 36)),
      );
      await tester.pump();
      final id = views.onlyId;

      views.failingMethods.add('setButtonWidth');
      await tester.pumpWidget(
        _labeled('ToDo  6', const CNButtonConfig(width: 87, minHeight: 36)),
      );
      await tester.pump();
      expect(views.widthCalls(id), hasLength(1));

      views.failingMethods.clear();
      // 同じ設定のまま、次の同期が起きる
      await tester.pumpWidget(
        _labeled('ToDo  6', const CNButtonConfig(width: 87, minHeight: 36)),
      );
      await tester.pump();

      final sent = [
        ...views.titles(id),
        for (final call in views.widthCalls(id).skip(1)) call['title'],
      ];
      expect(sent, contains('ToDo  6'));
      expect(views.widthCalls(id).last['width'], 87);
    }, variant: iOS);

    testWidgets(
      'macOS では幅を送らないので、文字はこれまでどおり文字だけで送る',
      (tester) async {
        final views = FakePlatformViews(tester);
        await tester.pumpWidget(
          _labeled('ToDo', const CNButtonConfig(width: 70, minHeight: 36)),
        );
        await tester.pump();
        final id = views.onlyId;

        await tester.pumpWidget(
          _labeled('ToDo  6', const CNButtonConfig(width: 87, minHeight: 36)),
        );
        await tester.pump();

        expect(views.titles(id), ['ToDo  6']);
        expect(views.widthCalls(id), isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });

  group('CNButton の膨らむための余白', () {
    testWidgets('pressOverflow の分だけネイティブのビューを大きくし、ボタンの大きさは変えない', (
      tester,
    ) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(
        _button(
          const CNButtonConfig(width: 100, minHeight: 36, pressOverflow: 6),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(CNButton)), const Size(100, 36));
      expect(tester.getSize(find.byType(UiKitView)), const Size(112, 48));
      expect(views.created[views.onlyId]!['pressOverflow'], 6);
      // 膨らんだガラスを切らない
      expect(
        find.descendant(
          of: find.byType(CNButton),
          matching: find.byType(ClipRect),
        ),
        findsNothing,
      );
    }, variant: iOS);

    testWidgets('親が狭いときは親に合わせた大きさの周りにだけ余白を取る', (tester) async {
      FakePlatformViews(tester);
      await tester.pumpWidget(
        CupertinoApp(
          home: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 60),
              child: CNButton(
                label: 'タブ',
                onPressed: () {},
                config: const CNButtonConfig(minHeight: 36, pressOverflow: 6),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(CNButton)), const Size(60, 36));
      expect(tester.getSize(find.byType(UiKitView)), const Size(72, 48));
    }, variant: iOS);

    testWidgets('余白の外を押しても、ボタンは押されない', (tester) async {
      var pressed = 0;
      FakePlatformViews(tester);
      await tester.pumpWidget(
        CupertinoApp(
          home: Center(
            child: CNButton(
              label: 'タブ',
              onPressed: () => pressed++,
              config: const CNButtonConfig(
                width: 100,
                minHeight: 36,
                pressOverflow: 6,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // ボタンの右端から 3pt 外（余白の中）
      final rect = tester.getRect(find.byType(CNButton));
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(
        result,
        rect.centerRight + const Offset(3, 0),
        tester.view.viewId,
      );
      expect(
        result.path.any((entry) => entry.target is RenderUiKitView),
        isFalse,
      );
      expect(pressed, 0);
    }, variant: iOS);
  });
}
