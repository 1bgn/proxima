// custom_text_engine/paragraph_block.dart
import 'inline_elements.dart';

enum CustomTextAlign {
  left,
  right,
  center,
  justify,
}

/// Абзац (параграф).
// custom_text_engine/paragraph_block.dart

/// Абзац (параграф).
// custom_text_engine/paragraph_block.dart

/// Абзац (параграф).
// custom_text_engine/paragraph_block.dart

class ParagraphBlock {
  final List<InlineElement> inlineElements;
  final CustomTextAlign? textAlign;
  final CustomTextDirection textDirection;
  final double firstLineIndent;
  final double paragraphSpacing;
  final int minimumLines;
  final double? maxWidth; // если задан, то считается, что блок занимает globalMaxWidth * maxWidth
  final bool isSectionEnd;
  final bool breakable;
  final bool enableRedLine;
  // Новое свойство для выравнивания всего блока в контейнере
  final CustomTextAlign? containerAlignment;

  ParagraphBlock({
    required this.inlineElements,
    this.textAlign,
    this.textDirection = CustomTextDirection.ltr,
    this.firstLineIndent = 0.0,
    this.paragraphSpacing = 0.0,
    this.minimumLines = 1,
    this.maxWidth,
    this.isSectionEnd = false,
    this.breakable = false,
    this.enableRedLine = true,
    this.containerAlignment, // если не задано, по умолчанию считается left
  });

  ParagraphBlock copyWith({
    List<InlineElement>? inlineElements,
    CustomTextAlign? textAlign,
    CustomTextDirection? textDirection,
    double? firstLineIndent,
    double? paragraphSpacing,
    int? minimumLines,
    double? maxWidth,
    bool? isSectionEnd,
    bool? breakable,
    bool? enableRedLine,
    CustomTextAlign? containerAlignment,
  }) {
    return ParagraphBlock(
      inlineElements: inlineElements ?? this.inlineElements,
      textAlign: textAlign ?? this.textAlign,
      textDirection: textDirection ?? this.textDirection,
      firstLineIndent: firstLineIndent ?? this.firstLineIndent,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      minimumLines: minimumLines ?? this.minimumLines,
      maxWidth: maxWidth ?? this.maxWidth,
      isSectionEnd: isSectionEnd ?? this.isSectionEnd,
      breakable: breakable ?? this.breakable,
      enableRedLine: enableRedLine ?? this.enableRedLine,
      containerAlignment: containerAlignment ?? this.containerAlignment,
    );
  }
}