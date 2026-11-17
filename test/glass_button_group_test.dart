import 'dart:async';

import 'package:cupertino_native_plus/cupertino_native_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform_views.dart';

extension on FakePlatformViews {
  /// The buttons in the view's creation params.
  List<Map<Object?, Object?>> createdButtons(int id) => [
    for (final button in created[id]!['buttons']! as List<Object?>)
      button! as Map<Object?, Object?>,
  ];

  /// The `updateButton` calls sent to the view, as (index, button).
  List<(int, Map<Object?, Object?>)> updates(int id) => [
    for (final call in calls[id]!)
      if (call.method == 'updateButton')
        (
          (call.arguments as Map<Object?, Object?>)['index']! as int,
          (call.arguments as Map<Object?, Object?>)['button']!
              as Map<Object?, Object?>,
        ),
  ];

  /// The `isDark` values sent to the view with `setBrightness`.
  List<Object?> brightnesses(int id) => [
    for (final call in calls[id]!)
      if (call.method == 'setBrightness')
        (call.arguments as Map<Object?, Object?>)['isDark'],
  ];

  /// Presses the [index]th button on the iOS side. Pump to deliver it.
  void press(int id, int index) =>
      sendFromNative(id, MethodCall('buttonPressed', {'index': index}));
}

/// Stand-in image bytes; the views never decode them in these tests.
Uint8List _image(int seed) => Uint8List.fromList([seed]);

CNButtonData _button(
  Uint8List image, {
  bool enabled = true,
  VoidCallback? onPressed,
}) => CNButtonData.icon(
  icon: CNIcon.png(image, size: const Size(24, 24)),
  enabled: enabled,
  onPressed: onPressed,
);

Widget _group(
  List<CNButtonData> buttons, {
  Brightness brightness = Brightness.light,
  Axis axis = Axis.horizontal,
}) => CupertinoApp(
  theme: CupertinoThemeData(brightness: brightness),
  home: Center(
    child: SizedBox(
      width: 96,
      height: 44,
      child: CNGlassButtonGroup(buttons: buttons, axis: axis),
    ),
  ),
);

void main() {
  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

  setUp(() => PlatformVersion.debugShouldUseNativeGlassOverride = true);
  tearDown(() => PlatformVersion.debugShouldUseNativeGlassOverride = null);

  group('CNGlassButtonGroup のネイティブのビュー', () {
    testWidgets('できた後に変わったボタンだけを送る', (tester) async {
      final views = FakePlatformViews(tester);
      final first = _image(1);
      await tester.pumpWidget(_group([_button(first), _button(_image(2))]));
      await tester.pump();
      final id = views.onlyId;
      expect(views.calls[id], isEmpty);

      final changed = _image(3);
      await tester.pumpWidget(_group([_button(first), _button(changed)]));
      await tester.pump();

      expect(views.updates(id), hasLength(1));
      expect(views.updates(id).single.$1, 1);
      expect(views.updates(id).single.$2['imageBytes'], changed);
    }, variant: iOS);

    testWidgets('ビューができる前に変わったボタンを、できた後に送る', (tester) async {
      final views = FakePlatformViews(tester)..creating = Completer<void>();
      final before = _image(1);
      await tester.pumpWidget(_group([_button(before)]));
      await tester.pump();
      final id = views.onlyId;
      expect(views.createdButtons(id).single['imageBytes'], before);

      final after = _image(2);
      await tester.pumpWidget(_group([_button(after, enabled: false)]));
      await tester.pump();
      views.creating!.complete();
      await tester.pump();

      expect(views.updates(id), hasLength(1));
      expect(views.updates(id).single.$1, 0);
      expect(views.updates(id).single.$2['imageBytes'], after);
      expect(views.updates(id).single.$2['enabled'], isFalse);
    }, variant: iOS);

    testWidgets('ビューができる前に変わった明暗を、できた後に送る', (tester) async {
      final views = FakePlatformViews(tester)..creating = Completer<void>();
      final buttons = [_button(_image(1))];
      await tester.pumpWidget(_group(buttons));
      await tester.pump();
      final id = views.onlyId;
      expect(views.created[id]!['isDark'], isFalse);

      await tester.pumpWidget(_group(buttons, brightness: Brightness.dark));
      await tester.pump();
      views.creating!.complete();
      await tester.pump();

      expect(views.brightnesses(id), [true]);
    }, variant: iOS);

    testWidgets('送っている途中に変わったボタンも、送り終わった後に送る', (tester) async {
      final views = FakePlatformViews(tester);
      final image = _image(1);
      await tester.pumpWidget(_group([_button(image)]));
      await tester.pump();
      final id = views.onlyId;

      views.replying = Completer<void>();
      await tester.pumpWidget(_group([_button(image, enabled: false)]));
      // Back to enabled before the first update is answered.
      await tester.pumpWidget(_group([_button(image)]));
      views.replying!.complete();
      await tester.pump();

      expect(views.updates(id).map((update) => update.$2['enabled']), [
        false,
        true,
      ]);
    }, variant: iOS);

    testWidgets('明暗を送っている途中に戻した明暗も送る', (tester) async {
      final views = FakePlatformViews(tester);
      final buttons = [_button(_image(1))];
      await tester.pumpWidget(_group(buttons));
      await tester.pump();
      final id = views.onlyId;

      views.replying = Completer<void>();
      await tester.pumpWidget(_group(buttons, brightness: Brightness.dark));
      // Back to light before the first change is answered.
      await tester.pumpWidget(_group(buttons));
      views.replying!.complete();
      await tester.pump();

      expect(views.brightnesses(id), [true, false]);
    }, variant: iOS);

    testWidgets('なくなった後は、ネイティブで押されても前のボタンの処理を呼ばない', (tester) async {
      final views = FakePlatformViews(tester);
      var pressed = 0;
      await tester.pumpWidget(
        _group([_button(_image(1), onPressed: () => pressed++)]),
      );
      await tester.pump();
      final id = views.onlyId;
      views.press(id, 0);
      await tester.pump();
      expect(pressed, 1);

      await tester.pumpWidget(const SizedBox());
      views.press(id, 0);
      await tester.pump();

      expect(pressed, 1);
    }, variant: iOS);

    group('axis を変えてビューを作り直したとき', () {
      testWidgets('作っている途中に変わったボタンと明暗を、新しいビューに送る', (tester) async {
        final views = FakePlatformViews(tester);
        final image = _image(1);
        await tester.pumpWidget(_group([_button(image)]));
        await tester.pump();
        await tester.pumpWidget(
          _group([_button(image)], brightness: Brightness.dark),
        );
        await tester.pump();

        // The new view is created dark with the first button.
        views.creating = Completer<void>();
        await tester.pumpWidget(
          _group(
            [_button(image)],
            brightness: Brightness.dark,
            axis: Axis.vertical,
          ),
        );
        await tester.pump();
        expect(views.created, hasLength(2));
        final second = views.created.keys.last;
        expect(views.created[second]!['isDark'], isTrue);

        final changed = _image(2);
        await tester.pumpWidget(
          _group([_button(changed, enabled: false)], axis: Axis.vertical),
        );
        await tester.pump();
        views.creating!.complete();
        await tester.pump();

        expect(views.brightnesses(second), [false]);
        expect(views.updates(second), hasLength(1));
        expect(views.updates(second).single.$2['imageBytes'], changed);
        expect(views.updates(second).single.$2['enabled'], isFalse);
      }, variant: iOS);

      testWidgets('前のビューへの送信が終わる前に作り直しても、新しいビューに最新のボタンを送る', (tester) async {
        final views = FakePlatformViews(tester);
        final a = _image(1);
        final b = _image(2);
        final c = _image(3);
        await tester.pumpWidget(_group([_button(a)]));
        await tester.pump();
        final first = views.onlyId;

        // The first view hasn't answered the change to b when it's replaced
        // by a view created with c.
        views.replying = Completer<void>();
        await tester.pumpWidget(_group([_button(b)]));
        await tester.pumpWidget(_group([_button(c)]));
        await tester.pumpWidget(_group([_button(c)], axis: Axis.vertical));
        await tester.pump();
        final second = views.created.keys.last;
        expect(views.createdButtons(second).single['imageBytes'], c);
        await tester.pumpWidget(_group([_button(b)], axis: Axis.vertical));
        views.replying!.complete();
        await tester.pump();

        expect(views.updates(first).map((update) => update.$2['imageBytes']), [
          b,
        ]);
        expect(views.updates(second).map((update) => update.$2['imageBytes']), [
          b,
        ]);

        await tester.pumpWidget(_group([_button(c)], axis: Axis.vertical));
        await tester.pump();

        expect(views.updates(second).map((update) => update.$2['imageBytes']), [
          b,
          c,
        ]);
      }, variant: iOS);

      testWidgets('前のビューで明暗の送信が失敗しても、新しいビューの明暗を取り違えない', (tester) async {
        final views = FakePlatformViews(tester);
        final buttons = [_button(_image(1))];
        await tester.pumpWidget(_group(buttons));
        await tester.pump();

        // The first view fails the change to dark after it's replaced.
        views
          ..replying = Completer<void>()
          ..failing = true;
        await tester.pumpWidget(_group(buttons, brightness: Brightness.dark));
        await tester.pumpWidget(
          _group(buttons, brightness: Brightness.dark, axis: Axis.vertical),
        );
        await tester.pump();
        final second = views.created.keys.last;
        expect(views.created[second]!['isDark'], isTrue);
        views.replying!.complete();
        await tester.pump();

        views.failing = false;
        await tester.pumpWidget(
          _group(buttons, brightness: Brightness.dark, axis: Axis.vertical),
        );
        await tester.pump();

        expect(views.brightnesses(second), isEmpty);
      }, variant: iOS);

      testWidgets('なくなった後は、前のどのビューで押されても処理を呼ばない', (tester) async {
        final views = FakePlatformViews(tester);
        var pressed = 0;
        final buttons = [_button(_image(1), onPressed: () => pressed++)];
        await tester.pumpWidget(_group(buttons));
        await tester.pump();
        await tester.pumpWidget(_group(buttons, axis: Axis.vertical));
        await tester.pump();
        expect(views.created, hasLength(2));

        await tester.pumpWidget(const SizedBox());
        for (final id in views.created.keys) {
          views.press(id, 0);
        }
        await tester.pump();

        expect(pressed, 0);
      }, variant: iOS);
    });
  });
}
