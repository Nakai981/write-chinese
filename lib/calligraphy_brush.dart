import 'dart:math' as math;
import 'dart:ui';

class BrushPoint {
  final Offset position;
  final double? pressure;
  final int microseconds;
  const BrushPoint(this.position, this.pressure, this.microseconds);
}

class BrushDab {
  final Offset position;
  final double radius;
  const BrushDab(this.position, this.radius);
}

/// Smooth, solid ink with pressure, speed and a tapered brush tip.
class CalligraphyBrush {
  static List<BrushDab> shape(List<BrushPoint> samples, double side) {
    if (samples.isEmpty) return [];
    final base = (side * 0.065).clamp(18.0, 42.0);
    final points = samples.map((s) => s.position * side).toList();
    if (points.length == 1) return [BrushDab(points.first, base * 0.32)];
    final distances = <double>[0];
    for (int i = 1; i < points.length; i++) {
      distances.add(distances.last + (points[i] - points[i - 1]).distance);
    }
    final total = distances.last;
    if (total < 0.5) return [BrushDab(points.first, base * 0.32)];
    final widths = <double>[];
    double smoothed = base * 0.8;
    for (int i = 0; i < samples.length; i++) {
      final before = i == 0 ? 0 : i - 1;
      final after = i == 0 ? 1 : i;
      final delta = points[after] - points[before];
      final dt =
          math.max(
            1000,
            samples[after].microseconds - samples[before].microseconds,
          ) /
          1000000;
      final speed = (delta.distance / side / dt).clamp(0.0, 6.0);
      final pressure = samples[i].pressure;
      final weight = pressure == null
          ? 1.12 - speed * 0.075
          : 0.48 + 0.85 * math.sqrt(pressure.clamp(0.0, 1.0));
      final angle = delta.distance < 0.01
          ? 0.0
          : math.atan2(delta.dy, delta.dx);
      final nib = 0.87 + 0.13 * math.sin(angle - math.pi / 4).abs();
      final desired = base * weight * nib;
      smoothed += (desired - smoothed) * 0.45;
      widths.add(smoothed);
    }
    final result = <BrushDab>[];
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[math.max(0, i - 1)];
      final p1 = points[i], p2 = points[i + 1];
      final p3 = points[math.min(points.length - 1, i + 2)];
      final steps = math.max(1, ((p2 - p1).distance / 2).ceil());
      for (int j = 0; j < steps; j++) {
        final t = j / steps;
        final t2 = t * t, t3 = t2 * t;
        final point =
            (p1 * 2 +
                (p2 - p0) * t +
                (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                (p3 - p0 + (p1 - p2) * 3) * t3) *
            0.5;
        final distance = distances[i] + (distances[i + 1] - distances[i]) * t;
        final entry = (distance / (base * 0.9)).clamp(0.0, 1.0);
        final exit = ((total - distance) / (base * 1.3)).clamp(0.0, 1.0);
        final taper = (0.35 + 0.65 * entry) * (0.16 + 0.84 * exit);
        result.add(
          BrushDab(
            point,
            (widths[i] + (widths[i + 1] - widths[i]) * t) * taper / 2,
          ),
        );
      }
    }
    result.add(BrushDab(points.last, widths.last * 0.08));
    return result;
  }

  static void paint(
    Canvas canvas,
    List<BrushPoint> samples,
    double side,
    Color color,
  ) {
    final dabs = shape(samples, side);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    // Dense overlapping solid dabs form one brush silhouette without seams.
    for (final dab in dabs) {
      canvas.drawCircle(dab.position, dab.radius, paint);
    }
  }
}
