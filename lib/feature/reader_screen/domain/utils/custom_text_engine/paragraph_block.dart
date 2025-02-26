/// paragraph_block.dart
///
/// Описание абзаца и связанных с ним настроек.

import 'inline_elements.dart';

/// Тип выравнивания (на уровне абзаца).
enum CustomTextAlign {
  left,
  right,
  center,
  justify,
}

/// Параграф (абзац).
class ParagraphBlock {
  /// Набор инлайновых элементов (текст, ссылки, изображения).
  final List<InlineElement> inlineElements;

  /// Если null, используем глобальное выравнивание движка.
  final CustomTextAlign? textAlign;

  /// Направление текста.
  final CustomTextDirection textDirection;

  /// Отступ (в пикселях) у первой строки.
  final double firstLineIndent;

  /// Отступ (в пикселях) после абзаца.
  final double paragraphSpacing;

  /// Минимальное число строк в абзаце (учёт сирот/вдов).
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
