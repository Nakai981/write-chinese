import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanzi_practice/stroke_matcher.dart';

void main() {
  final data = jsonDecode(
    File('assets/sample_strokes.json').readAsStringSync(),
  );
  final medians = (data['medians'] as List)
      .map(
        (line) => (line as List)
            .map(
              (p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
            )
            .toList(),
      )
      .toList();
  List<Offset> normalized(List<Offset> line) =>
      line.map((p) => Offset(p.dx / 1024, (900 - p.dy) / 1024)).toList();

  test('accepts approximate strokes with uneven sampling', () {
    for (final median in medians) {
      final points = normalized(median)
          .map((p) => p + const Offset(0.02, -0.015))
          .toList();
      final uneven = <Offset>[];
      for (int i = 0; i < points.length - 1; i++) {
        uneven.add(points[i]);
        uneven.add(Offset.lerp(points[i], points[i + 1], 0.1)!);
      }
      uneven.add(points.last);
      expect(StrokeMatcher.matches(uneven, median), isTrue);
    }
  });
  test('rejects reversed, displaced, incomplete and out-of-order strokes', () {
    final first = normalized(medians.first);
    expect(
      StrokeMatcher.matches(first.reversed.toList(), medians.first),
      isFalse,
    );
    expect(
      StrokeMatcher.matches(
        first.map((p) => p + const Offset(0.22, 0)).toList(),
        medians.first,
      ),
      isFalse,
    );
    expect(
      StrokeMatcher.matches([
        first.first,
        Offset.lerp(first.first, first[1], 0.1)!,
      ], medians.first),
      isFalse,
    );
    expect(
      StrokeMatcher.matches(normalized(medians[1]), medians.first),
      isFalse,
    );
    expect(
      StrokeMatcher.matches([first.first, first.first], medians.first),
      isFalse,
    );
  });
  test('accepts a visibly approximate trace with small hand wobble', () {
    final first = normalized(medians.first);
    final approximate = first.indexed
        .map(
          (entry) =>
              entry.$2 +
              Offset(0.075 + (entry.$1.isEven ? 0.01 : -0.01), 0.025),
        )
        .toList();
    expect(StrokeMatcher.matches(approximate, medians.first), isTrue);
  });
}
