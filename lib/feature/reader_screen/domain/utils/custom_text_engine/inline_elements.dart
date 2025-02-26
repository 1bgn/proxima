/// inline_elements.dart
///
/// Содержит базовые классы «инлайновых» элементов: текст, ссылка, изображение.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Определяет направление текста (LTR / RTL).
enum CustomTextDirection {
  ltr,
  rtl,
}

/// Тип отображения изображения: блочное (block) или инлайновое (inline).
enum ImageDisplayMode {
  inline,
  block,
}

/// Базовый класс для любого «инлайнового» элемента.
abstract class InlineElement {
  /// Итоговая ширина элемента после layout.
  double width = 0.0;

  /// Итоговая высота элемента после layout.
  double height = 0.0;

  /// Позиция базовой линии (baseline) относительно верхнего края элемента.
  /// Для текста — обычно ascent, для изображений может быть равной [height].
  double baseline = 0.0;

  /// Прямоугольники для выделения (selection).
  List<Rect> selectionRects = [];

  /// Вычисляет размеры (width/height/baseline) элемента при заданной максимальной ширине.
  void performLayout(double maxWidth);

  /// Отрисовывает элемент на [canvas] по координатам [offset].
  void paint(ui.Canvas canvas, Offset offset);

  /// Возвращает интерактивные зоны (например, для клика по ссылке).
  /// По умолчанию — пусто.
  List<Rect> getInteractiveRects(Offset offset) => [];
}

/// Текстовый элемент.
class TextInlineElement extends InlineElement {
  final String text;
  final TextStyle style;

  ui.Paragraph? _paragraph;

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
    _paragraph = paragraph;

    width = paragraph.maxIntrinsicWidth;
    height = paragraph.height;
    final metrics = paragraph.computeLineMetrics();
    if (metrics.isNotEmpty) {
      baseline = metrics.first.ascent;
    } else {
      baseline = height;
    }

    // Заполним selectionRects
    selectionRects = [];
    if (text.isNotEmpty) {
      final boxes = paragraph.getBoxesForRange(0, text.length);
      for (final box in boxes) {
        final rect = Rect.fromLTWH(box.left, box.top, box.right - box.left, box.bottom - box.top);
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

/// Ссылка (inline). Аналогична TextInlineElement, но при paint добавляем подчёркивание.
class InlineLinkElement extends TextInlineElement {
  final String url;

  InlineLinkElement(String text, TextStyle style, this.url) : super(text, style);

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    super.paint(canvas, offset);
    if (_paragraph != null) {
      final linkColor = style.color ?? Colors.blue;
      final paint = Paint()..color = linkColor;
      for (final r in selectionRects) {
        final shifted = r.shift(offset);
        final underlineRect = Rect.fromLTWH(shifted.left, shifted.bottom - 1, shifted.width, 1);
        canvas.drawRect(underlineRect, paint);
      }
    }
  }
}

/// Изображение (inline / block).
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
    if (mode == ImageDisplayMode.block) {
      final w = (desiredWidth > maxWidth) ? maxWidth : desiredWidth;
      width = w;
      height = desiredHeight;
      baseline = height;
    } else {
      final w = (desiredWidth > maxWidth) ? maxWidth : desiredWidth;
      width = w;
      height = desiredHeight;
      baseline = height;
    }
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(offset.dx, offset.dy, width, height);
    canvas.drawImageRect(image, srcRect, dstRect, Paint());
  }
}
