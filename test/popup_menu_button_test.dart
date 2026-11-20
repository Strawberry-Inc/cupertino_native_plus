import 'package:cupertino_native_plus/cupertino_native_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform_views.dart';

extension on FakePlatformViews {
  /// The arguments of the calls to [method] sent to view [id].
  List<Map<Object?, Object?>> argsOf(int id, String method) => [
    for (final call in calls[id]!)
      if (call.method == method) call.arguments! as Map<Object?, Object?>,
  ];
}

Widget _menu({String checked = 'B', String? accessibilityLabel = 'カテゴリ B'}) =>
    CupertinoApp(
      home: Center(
        child: SizedBox(
          width: 120,
          height: 32,
          child: CNPopupMenuButton(
            buttonLabel: '',
            accessibilityLabel: accessibilityLabel,
            items: [
              for (final label in const ['A', 'B', 'C'])
                CNPopupMenuItem(label: label, checked: label == checked),
            ],
            onSelected: (_) {},
          ),
        ),
      ),
    );

void main() {
  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

  setUp(() => PlatformVersion.debugShouldUseNativeGlassOverride = true);
  tearDown(() => PlatformVersion.debugShouldUseNativeGlassOverride = null);

  group('CNPopupMenuButton のチェック', () {
    testWidgets('作るときに、項目ごとのチェックを checked で送る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_menu());
      await tester.pumpAndSettle();

      expect(views.created[views.onlyId]!['checked'], [false, true, false]);
    }, variant: iOS);

    testWidgets('チェックを変えたら、setItems で送る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_menu());
      await tester.pumpAndSettle();

      await tester.pumpWidget(_menu(checked: 'C'));
      await tester.pumpAndSettle();

      expect(views.argsOf(views.onlyId, 'setItems').last['checked'], [
        false,
        false,
        true,
      ]);
    }, variant: iOS);

    test('checked は既定で false で、等しさに含める', () {
      expect(const CNPopupMenuItem(label: 'A').checked, isFalse);
      expect(
        const CNPopupMenuItem(label: 'A', checked: true),
        isNot(const CNPopupMenuItem(label: 'A')),
      );
    });
  });

  group('CNPopupMenuButton の読み上げ', () {
    testWidgets('作るときに、ボタンの読み上げを accessibilityLabel で送る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_menu());
      await tester.pumpAndSettle();

      expect(views.created[views.onlyId]!['accessibilityLabel'], 'カテゴリ B');
    }, variant: iOS);

    testWidgets('読み上げを変えたら、setAccessibilityLabel で送る', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_menu());
      await tester.pumpAndSettle();

      await tester.pumpWidget(_menu(accessibilityLabel: 'カテゴリ C'));
      await tester.pumpAndSettle();

      expect(views.argsOf(views.onlyId, 'setAccessibilityLabel'), [
        {'label': 'カテゴリ C'},
      ]);
    }, variant: iOS);

    testWidgets('読み上げが変わらなければ、setAccessibilityLabel を送らない', (tester) async {
      final views = FakePlatformViews(tester);
      await tester.pumpWidget(_menu());
      await tester.pumpAndSettle();

      await tester.pumpWidget(_menu(checked: 'C'));
      await tester.pumpAndSettle();

      expect(views.argsOf(views.onlyId, 'setAccessibilityLabel'), isEmpty);
    }, variant: iOS);
  });
}
