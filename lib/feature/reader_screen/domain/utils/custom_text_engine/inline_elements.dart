// inline_elements.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:math' as math;

enum CustomTextDirection {
  ltr,
  rtl,
}

enum ImageDisplayMode {
  inline,
  block,
}

abstract class InlineElement {
  double width = 0;
  double height = 0;
  double baseline = 0;
  List<Rect> selectionRects = [];

  void performLayout(double maxWidth);
  void paint(ui.Canvas canvas, Offset offset);
  List<Rect> getInteractiveRects(Offset offset) => [];
}

class TextInlineElement extends InlineElement {
  final String text;
  final TextStyle style;
  ui.Paragraph? _paragraph;

  TextInlineElement(this.text, this.style);

  @override
  void performLayout(double maxWidth) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: style.fontSize,
        fontFamily: style.fontFamily,
        fontWeight: style.fontWeight,
        fontStyle: style.fontStyle,
      ),
    );
    builder.pushStyle(ui.TextStyle(
      color: style.color,
      fontSize: style.fontSize,
      fontFamily: style.fontFamily,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      letterSpacing: style.letterSpacing,
      wordSpacing: style.wordSpacing,
      height: style.height,
    ));
    builder.addText(text);
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: maxWidth));
    _paragraph = paragraph;
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
      for (final box in boxes) {
        selectionRects.add(Rect.fromLTWH(box.left, box.top, box.right - box.left, box.bottom - box.top));
      }
    }
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    if (_paragraph != null) {
      canvas.drawParagraph(_paragraph!, offset);
    }
  }
}

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
        final underline = Rect.fromLTWH(shifted.left, shifted.bottom - 1, shifted.width, 1);
        canvas.drawRect(underline, paint);
      }
    }
  }
}

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
    final w = desiredWidth > maxWidth ? maxWidth : desiredWidth;
    width = w;
    height = desiredHeight;
    baseline = height;
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(offset.dx, offset.dy, width, height);
    canvas.drawImageRect(image, src, dst, Paint());
  }
}

/// Асинхронное изображение, которое после загрузки масштабируется по натуральным размерам
class ImageFutureInlineElement extends InlineElement {
  final Future<ui.Image> future;
  // Если desiredWidth/desiredHeight не заданы, используется натуральный размер,
  // но масштабируется так, чтобы не превышать maxWidth.
  final double? desiredWidth;
  final double? desiredHeight;
  // Минимальная высота, ниже которой масштабирование корректируется
  final double minHeight;
  final ImageDisplayMode mode;

  ui.Image? _img;
  bool _loaded = false;

  ImageFutureInlineElement({
    required this.future,
    this.desiredWidth,
    this.desiredHeight,
    this.mode = ImageDisplayMode.inline,
    this.minHeight = 100,
  });

  @override
  void performLayout(double maxWidth) {
    if (!_loaded) {
      // Пока не загружено, задаем placeholder размеры
      final w = desiredWidth ?? maxWidth;
      final h = desiredHeight ?? 150;
      width = w > maxWidth ? maxWidth : w;
      height = h;
      baseline = height;
      future.then((image) {
        _img = image;
        _loaded = true;
        final natW = image.width.toDouble();
        final natH = image.height.toDouble();
        double scale = 1.0;
        if (natW > maxWidth) {
          scale = maxWidth / natW;
        }
        double newWidth = natW * scale;
        double newHeight = natH * scale;
        // Если высота после масштабирования меньше минимальной, используем minHeight
        if (newHeight < minHeight) {
          scale = minHeight / natH;
          newHeight = minHeight;
          newWidth = natW * scale;
        }
        width = newWidth;
        height = newHeight;
        baseline = height;
        // Для перерисовки родительского RenderObject требуется вызвать соответствующий callback.
      }).catchError((err) {
        debugPrint("Error decoding image: $err");
      });
    } else {
      final natW = _img!.width.toDouble();
      final natH = _img!.height.toDouble();
      double scale = 1.0;
      if (natW > maxWidth) {
        scale = maxWidth / natW;
      }
      double newWidth = natW * scale;
      double newHeight = natH * scale;
      if (newHeight < minHeight) {
        scale = minHeight / natH;
        newHeight = minHeight;
        newWidth = natW * scale;
      }
      width = newWidth;
      height = newHeight;
      baseline = height;
    }
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    if (!_loaded || _img == null) {
      final rect = Rect.fromLTWH(offset.dx, offset.dy, width, height);
      canvas.drawRect(rect, Paint()..color = const Color(0x66CCCCCC));
    } else {
      final src = Rect.fromLTWH(0, 0, _img!.width.toDouble(), _img!.height.toDouble());
      final dst = Rect.fromLTWH(offset.dx, offset.dy, width, height);
      canvas.drawImageRect(_img!, src, dst, Paint());
    }
  }
}
