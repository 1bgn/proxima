// paragraph_block.dart
import 'inline_elements.dart';

enum CustomTextAlign {
  left,
  right,
  center,
  justify,
}



/// Абзац (параграф).
class ParagraphBlock {
  final List<InlineElement> inlineElements;
  final CustomTextAlign? textAlign;
  final CustomTextDirection textDirection;
  final double firstLineIndent;
  final double paragraphSpacing;
  final int minimumLines;
  final double? maxWidth;
  final bool startNewPage; // Флаг, что этот блок требует начала новой страницы

  ParagraphBlock({
    required this.inlineElements,
    this.textAlign,
    this.textDirection = CustomTextDirection.ltr,
    this.firstLineIndent = 0.0,
    this.paragraphSpacing = 0.0,
    this.minimumLines = 1,
    this.maxWidth,
    this.startNewPage = false,
  });

  ParagraphBlock copyWith({
    List<InlineElement>? inlineElements,
    CustomTextAlign? textAlign,
    CustomTextDirection? textDirection,
    double? firstLineIndent,
    double? paragraphSpacing,
    int? minimumLines,
    double? maxWidth,
    bool? startNewPage,
  }) {
    return ParagraphBlock(
      inlineElements: inlineElements ?? this.inlineElements,
      textAlign: textAlign ?? this.textAlign,
      textDirection: textDirection ?? this.textDirection,
      firstLineIndent: firstLineIndent ?? this.firstLineIndent,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      minimumLines: minimumLines ?? this.minimumLines,
      maxWidth: maxWidth ?? this.maxWidth,
      startNewPage: startNewPage ?? this.startNewPage,
    );
  }
}
