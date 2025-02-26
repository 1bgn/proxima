// lib/custom_text_engine/paragraph_block.dart

import 'inline_elements.dart';

/// Тип выравнивания (на уровне абзаца).
enum CustomTextAlign {
  left,
  right,
  center,
  justify,
}

/// Абзац (параграф).
class ParagraphBlock {
  final List<InlineElement> inlineElements;

  /// Если [textAlign] = null, используем глобальное выравнивание движка.
  final CustomTextAlign? textAlign;

  /// Направление (RTL или LTR).
  final CustomTextDirection textDirection;

  /// Отступ первой строки (в пикселях).
  final double firstLineIndent;

  /// Отступ после абзаца.
  final double paragraphSpacing;

  /// Минимальное число строк в абзаце (для сирот/вдов).
  final int minimumLines;

  ParagraphBlock({
    required this.inlineElements,
    this.textAlign,
    this.textDirection = CustomTextDirection.ltr,
    this.firstLineIndent = 0.0,
    this.paragraphSpacing = 0.0,
    this.minimumLines = 2,
  });
}
