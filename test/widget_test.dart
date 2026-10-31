import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hanzi_practice/main.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(744, 1133),
    const Size(1133, 744),
  ]) {
    testWidgets(
      '$size: HSK buttons, responsive grid, automatic progress, return',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'char_好': File('assets/sample_strokes.json').readAsStringSync(),
        });
        await tester.runAsync(() async {
          await tester.pumpWidget(const HanziApp());
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('150 từ'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const ValueKey('hsk-1')))
              .selected,
          isTrue,
        );
        final grid = tester.widget<GridView>(
          find.byKey(const ValueKey('word-grid')),
        );
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(
          delegate.crossAxisCount,
          size.width < 600 ? 2 : (size.width / 180).floor(),
        );
        await tester.tap(find.byKey(const ValueKey('hsk-2')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const ValueKey('hsk-2')))
              .selected,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('hsk-1')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('word-好')),
          400,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('word-grid')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.ensureVisible(find.byKey(const ValueKey('word-好')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('word-好')));
        await tester.pumpAndSettle();
        expect(find.text('Hướng dẫn viết'), findsOneWidget);
        final board = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is WritingPainter,
        );
        await tester.dragFrom(tester.getCenter(board), const Offset(30, 50));
        await tester.pump();
        expect(find.text('Thử lại gần nét mẫu hơn'), findsOneWidget);
        final data = jsonDecode(
          File('assets/sample_strokes.json').readAsStringSync(),
        );
        final medians = data['medians'] as List;
        Future<void> draw(int index) async {
          final origin = tester.getTopLeft(board);
          final width = tester.getSize(board).width;
          final points = (medians[index] as List)
              .map(
                (p) =>
                    origin +
                    Offset(
                          (p[0] as num).toDouble() / 1024,
                          (900 - (p[1] as num).toDouble()) / 1024,
                        ) *
                        width +
                    const Offset(2, 2),
              )
              .toList();
          final pen = await tester.startGesture(points.first);
          for (final p in points.skip(1)) {
            await pen.moveTo(p);
            await tester.pump();
          }
          await pen.up();
          await tester.pump();
        }

        // A recognizable later stroke must fill that outline immediately.
        await draw(5);
        expect(
          (tester.widget<CustomPaint>(board).painter as WritingPainter)
              .acceptedIndices,
          [5],
        );
        await tester.tap(find.byTooltip('Hoàn tác'));
        await tester.pump();
        await draw(0);
        expect(find.text('1 / 6 nét'), findsOneWidget);
        expect(
          (tester.widget<CustomPaint>(board).painter as WritingPainter)
              .acceptedCount,
          1,
        );
        await tester.tap(find.byTooltip('Hoàn tác'));
        await tester.pump();
        expect(find.text('0 / 6 nét'), findsOneWidget);
        for (int i = 0; i < medians.length; i++) {
          await draw(i);
        }
        expect(find.text('6 / 6 nét'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(
          (await SharedPreferences.getInstance()).getStringList('learned'),
          contains('好'),
        );
        await tester.tap(find.byTooltip('Tùy chọn'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Giải thích'));
        await tester.pumpAndSettle();
        expect(find.text('Cách luyện viết'), findsOneWidget);
        Navigator.of(tester.element(find.text('Cách luyện viết'))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Về danh sách'));
        await tester.pumpAndSettle();
        expect(find.text('1 đã viết · 149 chưa viết'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('saved words sort after unfinished words within HSK', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'learned': ['爱', '八'],
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(const HanziApp());
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
    expect(find.text('2 đã viết · 148 chưa viết'), findsOneWidget);
    expect(find.byKey(const ValueKey('word-爱')), findsNothing);
    expect(find.byKey(const ValueKey('word-八')), findsNothing);
    expect(find.byKey(const ValueKey('word-爸爸')), findsOneWidget);
    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('word-grid')),
    );
    final delegate = grid.childrenDelegate as SliverChildBuilderDelegate;
    final context = tester.element(find.byKey(const ValueKey('word-grid')));
    // Inspect the final two cards, preserving their original source order.
    final lastTwo = [
      delegate.builder(context, 148),
      delegate.builder(context, 149),
    ];
    for (int i = 0; i < lastTwo.length; i++) {
      final card = lastTwo[i] as Material;
      expect(
        (card.child as InkWell).key,
        ValueKey(i == 0 ? 'word-爱' : 'word-八'),
      );
    }
    expect(Theme.of(context).brightness, Brightness.light);
    await tester.tap(find.byKey(const ValueKey('hsk-6')));
    await tester.pumpAndSettle();
    expect(find.text('2500 từ'), findsOneWidget);
    expect(find.text('0 đã viết · 2500 chưa viết'), findsOneWidget);
  });
  testWidgets(
    'Mandarin reads Hanzi at saved speed; unavailable voice shows recovery',
    (tester) async {
      final calls = <MethodCall>[];
      bool available = true;
      const channel = MethodChannel('flutter_tts');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'isLanguageAvailable') return available;
        return 1;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      SharedPreferences.setMockInitialValues({
        'char_好': File('assets/sample_strokes.json').readAsStringSync(),
        'speechSpeed': 1.25,
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(const HanziApp());
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('word-好')),
        400,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('word-grid')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('word-好')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('word-好')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Nghe phát âm'));
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c.method == 'setLanguage').last.arguments,
        'zh-CN',
      );
      expect(
        calls.where((c) => c.method == 'setSpeechRate').last.arguments,
        0.625,
      );
      expect(calls.where((c) => c.method == 'speak').last.arguments, '好');
      await tester.tap(find.byTooltip('Dừng phát âm'));
      await tester.pumpAndSettle();
      available = false;
      await tester.tap(find.byTooltip('Nghe phát âm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa có giọng Quan thoại'), findsOneWidget);
    },
  );
}
