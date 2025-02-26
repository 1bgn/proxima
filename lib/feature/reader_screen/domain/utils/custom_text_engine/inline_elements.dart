// inline_elements.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Направление текста
enum CustomTextDirection {
  ltr,
  rtl,
}

/// Тип отображения изображения
enum ImageDisplayMode {
  inline,
  block,
}

/// Базовый интерфейс для «инлайнового элемента» (текст, картинка, ссылка).
abstract class InlineElement {
  double width = 0.0;
  double height = 0.0;
  double baseline = 0.0;

  List<Rect> selectionRects = [];

  void performLayout(double maxWidth);
  void paint(ui.Canvas canvas, Offset offset);

  List<Rect> getInteractiveRects(Offset offset) => [];
}

/// Текстовый элемент
class TextInlineElement extends InlineElement {
  String text;
  TextStyle style;

  ui.Paragraph? _paragraph;

  TextInlineElement(this.text, this.style);

  @override
  void performLayout(double maxWidth) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: style.fontSize,
      fontFamily: style.fontFamily,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
    ));

    pb.pushStyle(ui.TextStyle(
      color: style.color,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      letterSpacing: style.letterSpacing,
      wordSpacing: style.wordSpacing,
      height: style.height,
    ));
    pb.addText(text);

    final paragraph = pb.build();
    paragraph.layout(ui.ParagraphConstraints(width: maxWidth));

    _paragraph = paragraph;
    // используйте paragraph.longestLine / paragraph.maxIntrinsicWidth,
    // решайте сами.
    width = paragraph.maxIntrinsicWidth;
    height = paragraph.height;

    final metrics = paragraph.computeLineMetrics();
    if (metrics.isNotEmpty) {
      baseline = metrics.first.ascent;
    } else {
      baseline = height;
    }

    selectionRects = [];
    if (text.isNotEmpty) {
      final boxes = paragraph.getBoxesForRange(0, text.length);
      for (final b in boxes) {
        final rect = Rect.fromLTWH(b.left, b.top, b.right - b.left, b.bottom - b.top);
        selectionRects.add(rect);
      }
    }
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    if (_paragraph != null) {
      canvas.drawParagraph(_paragraph!, offset);
    }
  }

  @override
  List<Rect> getInteractiveRects(Offset offset) {
    return selectionRects.map((r) => r.shift(offset)).toList();
  }
}

/// Ссылка (inline)
class InlineLinkElement extends TextInlineElement {
  final String url;

  InlineLinkElement(String text, TextStyle style, this.url) : super(text, style);

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    super.paint(canvas, offset);
    if (_paragraph != null) {
      final paint = Paint()..color = (style.color ?? Colors.blue);
      for (final r in selectionRects) {
        final shifted = r.shift(offset);
        final lineRect = Rect.fromLTWH(shifted.left, shifted.bottom - 1, shifted.width, 1);
        canvas.drawRect(lineRect, paint);
      }
    }
  }
}

/// Изображение
class ImageInlineElement extends InlineElement {
  final ui.Image image;
  final double desiredWidth;
  final double desiredHeight;
  final ImageDisplayMode mode;

  ImageInlineElement({
    required this.image,
    required this.desiredWidth,
    required this.desiredHeight,
    this.mode = ImageDisplayMode.inline,
  });

  @override
  void performLayout(double maxWidth) {
    final w = (desiredWidth > maxWidth) ? maxWidth : desiredWidth;
    width = w;
    height = desiredHeight;
    baseline = height; // упрощённо
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(offset.dx, offset.dy, width, height);
    canvas.drawImageRect(image, src, dst, Paint());
  }
}
