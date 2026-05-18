import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_client/models/normalized_geometry.dart';

void main() {
  test('maps normalized points into the preview viewport', () {
    const transform = PreviewTransform(viewportSize: Size(200, 100));

    expect(
      transform.pointToViewport(const NormalizedPoint(0.25, 0.5)),
      const Offset(50, 50),
    );
  });

  test('mirrors normalized points on the x axis', () {
    const transform = PreviewTransform(
      viewportSize: Size(200, 100),
      mirrorX: true,
    );

    expect(
      transform.pointToViewport(const NormalizedPoint(0.25, 0.5)),
      const Offset(150, 50),
    );
  });

  test('maps normalized rectangles into the preview viewport', () {
    const transform = PreviewTransform(viewportSize: Size(1000, 500));

    _expectRect(
      transform.rectToViewport(
        const NormalizedRect(left: 0.1, top: 0.2, width: 0.3, height: 0.4),
      ),
      const Rect.fromLTRB(100, 100, 400, 300),
    );
  });

  test('mirrors normalized rectangles on the x axis', () {
    const transform = PreviewTransform(
      viewportSize: Size(1000, 500),
      mirrorX: true,
    );

    _expectRect(
      transform.rectToViewport(
        const NormalizedRect(left: 0.1, top: 0.2, width: 0.3, height: 0.4),
      ),
      const Rect.fromLTRB(600, 100, 900, 300),
    );
  });

  test('clamps overflowing rectangles to the preview viewport', () {
    const transform = PreviewTransform(viewportSize: Size(1000, 500));

    _expectRect(
      transform.rectToViewport(
        const NormalizedRect(left: 0.9, top: -0.1, width: 0.3, height: 0.4),
      ),
      const Rect.fromLTRB(900, 0, 1000, 150),
    );
  });
}

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 0.000001));
  expect(actual.top, closeTo(expected.top, 0.000001));
  expect(actual.right, closeTo(expected.right, 0.000001));
  expect(actual.bottom, closeTo(expected.bottom, 0.000001));
}
