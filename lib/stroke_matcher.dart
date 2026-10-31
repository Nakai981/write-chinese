import 'dart:math' as math;
import 'dart:ui';

/// Compares one normalized user stroke with the next 1024-unit Hanzi median.
/// Accepts approximate tracing, but requires position, direction and coverage.
class StrokeMatcher {
  static bool matches(List<Offset> input, List<Offset> median) {
    if (input.length < 2 || median.length < 2) return false;
    final target = median
        .map((p) => Offset(p.dx / 1024, (900 - p.dy) / 1024))
        .toList();
    final actualLength = _length(input);
    final expectedLength = _length(target);
    if (expectedLength < 0.001 ||
        actualLength < expectedLength * 0.35 ||
        actualLength > expectedLength * 3.0) {
      return false;
    }
    const tolerance = 0.16;
    if ((input.first - target.first).distance > tolerance ||
        (input.last - target.last).distance > tolerance) {
      return false;
    }
    final actual = _sample(input);
    final expected = _sample(target);
    // Compare distance to the whole path rather than requiring equal progress.
    // A pause, small wobble or short hook should not reject a recognizable trace.
    double distanceToPath(Offset point, List<Offset> path) =>
        path.map((p) => (point - p).distance).reduce(math.min);
    final errors = actual.map((p) => distanceToPath(p, expected)).toList();
    if (errors.any((d) => d > 0.18)) return false;
    final coverage = expected.map((p) => distanceToPath(p, actual)).toList();
    return errors.reduce((a, b) => a + b) / errors.length < 0.10 &&
        coverage.reduce((a, b) => a + b) / coverage.length < 0.10;
  }

  static double _length(List<Offset> points) {
    double result = 0;
    for (int i = 1; i < points.length; i++) {
      result += (points[i] - points[i - 1]).distance;
    }
    return result;
  }

  static List<Offset> _sample(List<Offset> points) {
    final length = _length(points);
    final result = <Offset>[];
    int segment = 1;
    double traveled = 0;
    for (int i = 0; i < 24; i++) {
      final position = length * i / 23;
      while (segment < points.length - 1 &&
          traveled + (points[segment] - points[segment - 1]).distance <
              position) {
        traveled += (points[segment] - points[segment - 1]).distance;
        segment++;
      }
      final span = (points[segment] - points[segment - 1]).distance;
      final t = span == 0 ? 0.0 : math.min(1.0, (position - traveled) / span);
      result.add(Offset.lerp(points[segment - 1], points[segment], t)!);
    }
    return result;
  }
}
