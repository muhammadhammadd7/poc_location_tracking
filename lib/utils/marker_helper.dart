import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Future<BitmapDescriptor> createCustomMarkerBitmap(String label) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(48, 48);

  final paint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  // Draw circle background
  canvas.drawCircle(const Offset(24, 24), 24, paint);

  // Draw white border
  final borderPaint = Paint()
    ..color = Colors.grey
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  canvas.drawCircle(const Offset(24, 24), 22, borderPaint);

  // Draw text
  final textPainter = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.grey,
        fontSize: 30,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  textPainter.layout();

  final textOffset = Offset(
    24 - textPainter.width / 2,
    24 - textPainter.height / 2,
  );
  textPainter.paint(canvas, textOffset);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
}
