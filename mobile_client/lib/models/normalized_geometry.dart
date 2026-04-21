class NormalizedPoint {
  const NormalizedPoint(this.x, this.y);

  final double x;
  final double y;
}

class NormalizedRect {
  const NormalizedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}
