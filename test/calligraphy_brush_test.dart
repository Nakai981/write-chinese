import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hanzi_practice/calligraphy_brush.dart';

List<BrushPoint> line(double? pressure, {int interval = 16000}) =>
    List.generate(
      24,
      (i) =>
          BrushPoint(ui.Offset(0.1 + i * 0.032, 0.5), pressure, i * interval),
    );
double bodyWidth(List<BrushDab> dabs) =>
    dabs
        .where((p) => p.position.dx > 140 && p.position.dx < 220)
        .map((p) => p.radius)
        .reduce((a, b) => a + b) /
    dabs.where((p) => p.position.dx > 140 && p.position.dx < 220).length;

void main() {
  test('pressure thickens ink and both tips taper', () {
    final light = CalligraphyBrush.shape(line(0.15), 400);
    final heavy = CalligraphyBrush.shape(line(0.9), 400);
    expect(bodyWidth(heavy), greaterThan(bodyWidth(light) * 1.3));
    expect(heavy.first.radius, lessThan(bodyWidth(heavy)));
    expect(heavy.last.radius, lessThan(bodyWidth(heavy) * 0.3));
  });
  test('without pressure slower movement makes a fuller stroke', () {
    final slow = CalligraphyBrush.shape(line(null, interval: 40000), 400);
    final fast = CalligraphyBrush.shape(line(null, interval: 4000), 400);
    expect(bodyWidth(slow), greaterThan(bodyWidth(fast)));
    expect(CalligraphyBrush.shape([], 400), isEmpty);
    expect(
      CalligraphyBrush.shape([
        const BrushPoint(ui.Offset(0.5, 0.5), null, 0),
      ], 400).single.radius,
      greaterThan(5),
    );
  });
  testWidgets('brush renders a smooth ink preview', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xfffffdf7), ui.BlendMode.src);
      CalligraphyBrush.paint(
        canvas,
        line(null),
        400,
        const ui.Color(0xff293f36),
      );
      final image = await recorder.endRecording().toImage(400, 400);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('.dart_tool/brush-preview.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
