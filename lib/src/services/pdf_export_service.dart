import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/drum_models.dart';
import '../widgets/score_preview.dart';

class PdfExportService {
  static Future<Uint8List> buildPdf(ScoreDocument score) async {
    final document = pw.Document(title: score.title, author: 'midi_to_drum');

    for (final page in score.pages) {
      final pageBytes = await _renderPage(score, page);
      final image = pw.MemoryImage(pageBytes);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) {
            return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
          },
        ),
      );
    }

    return document.save();
  }

  static Future<Uint8List> _renderPage(
    ScoreDocument score,
    ScorePageData page,
  ) async {
    const logicalWidth = 900.0;
    const logicalHeight = logicalWidth / a4AspectRatio;
    const pixelRatio = 3.0;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(pixelRatio);

    final painter = ScorePagePainter(score: score, page: page);
    painter.paint(canvas, const ui.Size(logicalWidth, logicalHeight));

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (logicalWidth * pixelRatio).round(),
      (logicalHeight * pixelRatio).round(),
    );

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Unable to render the score preview for export.');
    }

    return byteData.buffer.asUint8List();
  }
}
