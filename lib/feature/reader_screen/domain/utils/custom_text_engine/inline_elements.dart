// lib/custom_text_engine/inline_elements.dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Направление текста: LTR или RTL.
enum CustomTextDirection {
  ltr,
  rtl,
}

/// Тип отображения изображения: inline или block.
enum ImageDisplayMode {
  inline,
  block,
}

/// Базовый класс для любого инлайнового элемента в тексте.
abstract class InlineElement {
  double width = 0.0;
  double height = 0.0;
  double baseline = 0.0;

  /// Прямоугольники (для выделения, интерактивности).
  List<Rect> selectionRects = [];

  /// Вычисляет размеры элемента при заданной максимальной ширине.
  void performLayout(double maxWidth);

  /// Рисует элемент на [canvas] по указанным координатам.
  void paint(ui.Canvas canvas, Offset offset);

  /// Возвращает зоны интерактивности (например, для ссылок).
  List<Rect> getInteractiveRects(Offset offset) => [];
}

/// Текстовый элемент.
class TextInlineElement extends InlineElement {
  final String text;
  final TextStyle style;

  ui.Paragraph? _paragraphCache;

  TextInlineElement(this.text, this.style);

  @override
  void performLayout(double maxWidth) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontFamily: style.fontFamily,
        fontSize: style.fontSize,
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
    _paragraphCache = paragraph;
    width = paragraph.maxIntrinsicWidth;
    height = paragraph.height;
    final metrics = paragraph.computeLineMetrics();
    if (metrics.isNotEmpty) {
      baseline = metrics.first.ascent;
    } else {
      baseline = height;
    }
    // Заполняем selectionRects для интерактивности.
    selectionRects = [];
    if (text.isNotEmpty) {
      final boxes = paragraph.getBoxesForRange(0, text.length);
      for (final box in boxes) {
        selectionRects.add(Rect.fromLTWH(
          box.left,
          box.top,
          box.right - box.left,
          box.bottom - box.top,
        ));
      }
    }
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    if (_paragraphCache != null) {
      canvas.drawParagraph(_paragraphCache!, offset);
    }
  }

  @override
  List<Rect> getInteractiveRects(Offset offset) {
    return selectionRects.map((r) => r.shift(offset)).toList();
  }
}

/// Ссылка (inline). Отрисовывается как текст с подчёркиванием.
class InlineLinkElement extends TextInlineElement {
  final String url;

  InlineLinkElement(String text, TextStyle style, this.url) : super(text, style);

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    super.paint(canvas, offset);
    if (_paragraphCache != null) {
      final linkColor = style.color ?? Colors.blue;
      final paint = Paint()..color = linkColor;
      for (final rect in selectionRects) {
        final shifted = rect.shift(offset);
        final underlineRect = Rect.fromLTWH(
          shifted.left,
          shifted.bottom - 1,
          shifted.width,
          1,
        );
        canvas.drawRect(underlineRect, paint);
      }
    }
  }
}

/// Отображает изображение, если оно уже загружено.
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
    baseline = height; // baseline равна высоте
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(offset.dx, offset.dy, width, height);
    canvas.drawImageRect(image, srcRect, dstRect, Paint());
  }
}

/// Отображает изображение, которое загружается асинхронно.
// Отображает изображение, которое загружается асинхронно.
class ImageFutureInlineElement extends InlineElement {
  final Future<ui.Image> future;
  final double? desiredWidth;
  final double? desiredHeight;
  final double minHeight;

  /// Колбэк, который вызовется после успешной загрузки изображения.
  final VoidCallback? onImageLoaded;

  ui.Image? _image;

  ImageFutureInlineElement({
    required this.future,
    this.desiredWidth,
    this.desiredHeight,
    required this.minHeight,
    this.onImageLoaded,
  }) {
    future.then((img) {
      _image = img;
      // После загрузки вызываем колбэк, чтобы движок узнал о готовности изображения.
      onImageLoaded?.call();
    });
  }

  @override
  void performLayout(double maxWidth) {
    if (_image != null) {
      final w = _image!.width.toDouble();
      final h = _image!.height.toDouble();

      // Сохраняем пропорции, если desiredWidth не указана.
      // Если же desiredWidth указана, используем её (с сохранением aspect ratio, если нужно).
      double scale = 1.0;
      if (desiredWidth != null) {
        // Масштабируем к желаемой ширине
        scale = desiredWidth! / w;
      } else if (w > maxWidth) {
        // Если натуральная ширина больше maxWidth, уменьшаем
        scale = maxWidth / w;
      }
      width = w * scale;

      // Для высоты, если desiredHeight не указана, вычисляем пропорционально.
      if (desiredHeight != null) {
        height = desiredHeight!;
      } else {
        height = (h * scale).clamp(minHeight, double.infinity);
      }
      baseline = height;
    } else {
      // Изображение ещё не загружено – рисуем placeholder
      width = maxWidth;
      height = minHeight;
      baseline = height;
    }
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    if (_image != null) {
      final srcRect = Rect.fromLTWH(0, 0, _image!.width.toDouble(), _image!.height.toDouble());
      final dstRect = Rect.fromLTWH(offset.dx, offset.dy, width, height);
      canvas.drawImageRect(_image!, srcRect, dstRect, Paint());
    } else {
      // Placeholder
      final paint = Paint()..color = Colors.grey.shade300;
      final rect = Rect.fromLTWH(offset.dx, offset.dy, width, height);
      canvas.drawRect(rect, paint);

      final borderPaint = Paint()
        ..color = Colors.grey
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect, borderPaint);

      // Текст "Loading image..."
      final textStyle = ui.TextStyle(
        color: Colors.grey.shade700,
        fontSize: 12,
      );
      final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.center);
      final builder = ui.ParagraphBuilder(paragraphStyle)..pushStyle(textStyle);
      builder.addText("Loading image...");
      final paragraph = builder.build();
      paragraph.layout(ui.ParagraphConstraints(width: width));
      final textOffset = Offset(
        offset.dx,
        offset.dy + (height - paragraph.height) / 2,
      );
      canvas.drawParagraph(paragraph, textOffset);
    }
  }
}
