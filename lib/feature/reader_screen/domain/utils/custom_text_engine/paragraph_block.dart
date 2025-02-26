// paragraph_block.dart
import 'inline_elements.dart';

enum CustomTextAlign {
  left,
  right,
  center,
  justify,
}

class ParagraphBlock {
  final List<InlineElement> inlineElements;
  final CustomTextAlign? textAlign;
  final CustomTextDirection textDirection;
  final double firstLineIndent;
  final double paragraphSpacing;
  final int minimumLines;
  final double? maxWidth; // если задано – доля от глобальной ширины

  ParagraphBlock({
    required this.inlineElements,
    this.textAlign,
    this.textDirection = CustomTextDirection.ltr,
    this.firstLineIndent = 0.0,
    this.paragraphSpacing = 0.0,
    this.minimumLines = 1,
    this.maxWidth,
  });
}
