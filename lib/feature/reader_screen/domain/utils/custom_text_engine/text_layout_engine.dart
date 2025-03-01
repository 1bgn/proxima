// text_layout_engine.dart
//
// Промышленная реализация движка AdvancedLayoutEngine,
// поддерживающая ParagraphBlock.maxWidth и сохраняющая пробелы между словами.
// Если paragraph.maxWidth != null, то effectiveWidth = globalMaxWidth * paragraph.maxWidth.

import 'dart:math' as math;
import 'inline_elements.dart';
import 'paragraph_block.dart';
import 'line_layout.dart';

class AdvancedLayoutEngine {
  final List<ParagraphBlock> paragraphs;
  final double globalMaxWidth;
  final double lineSpacing;
  final CustomTextAlign globalTextAlign;
  final bool allowSoftHyphens;
  final int columns;
  final double columnSpacing;
  final double pageHeight;

  AdvancedLayoutEngine({
    required this.paragraphs,
    required this.globalMaxWidth,
    required this.lineSpacing,
    required this.globalTextAlign,
    required this.allowSoftHyphens,
    required this.columns,
    required this.columnSpacing,
    required this.pageHeight,
  });

  /// Выполняет полный layout и возвращает многостраничную раскладку (MultiColumnPagedLayout).
  MultiColumnPagedLayout layoutAll() {
    // 1. Разбиваем абзацы в строки
    final layout = _layoutAllParagraphs();
    // 2. Разбиваем строки на страницы/колонки
    var multi = _buildMultiColumnPages(layout);
    // 3. Простая (заглушка) логика сирот/вдов
    multi = _applyWidowOrphanControl(multi, layout);
    return multi;
  }

  /// Шаг 1: Разбивает все абзацы в один список строк (LineLayout).
  CustomTextLayout _layoutAllParagraphs() {
    final allLines = <LineLayout>[];
    final paragraphIndexOfLine = <int>[];
    double totalHeight = 0.0;

    for (int pIndex = 0; pIndex < paragraphs.length; pIndex++) {
      final para = paragraphs[pIndex];
      final lines = _layoutSingleParagraph(para);

      // Запоминаем, к какому абзацу относятся эти строки
      for (int i = 0; i < lines.length; i++) {
        paragraphIndexOfLine.add(pIndex);
      }
      allLines.addAll(lines);

      // Подсчёт виртуальной высоты абзаца (с учётом lineSpacing)
      double paraHeight = 0.0;
      for (int i = 0; i < lines.length; i++) {
        paraHeight += lines[i].height;
        if (i < lines.length - 1) {
          paraHeight += lineSpacing;
        }
      }
      totalHeight += paraHeight;
      if (pIndex < paragraphs.length - 1) {
        totalHeight += para.paragraphSpacing;
      }
    }

    return CustomTextLayout(
      lines: allLines,
      totalHeight: totalHeight,
      paragraphIndexOfLine: paragraphIndexOfLine,
    );
  }

  /// Шаг 1.1: Разбивает один абзац на строки, учитывая paragraph.maxWidth.
  List<LineLayout> _layoutSingleParagraph(ParagraphBlock paragraph) {
    // Если maxWidth не задан, используем globalMaxWidth.
    final effectiveWidth = paragraph.maxWidth != null
        ? globalMaxWidth * paragraph.maxWidth!
        : globalMaxWidth;

    final splitted = _splitTokens(paragraph.inlineElements);
    final result = <LineLayout>[];
    var currentLine = LineLayout();

    final isRTL = paragraph.textDirection == CustomTextDirection.rtl;
    double firstLineIndent = paragraph.firstLineIndent;
    double currentX = 0.0;
    double maxAscent = 0.0;
    double maxDescent = 0.0;

    void commitLine() {
      currentLine.width = currentX;
      currentLine.maxAscent = maxAscent;
      currentLine.maxDescent = maxDescent;
      currentLine.height = maxAscent + maxDescent;
      result.add(currentLine);

      currentLine = LineLayout();
      currentX = 0.0;
      maxAscent = 0.0;
      maxDescent = 0.0;
      firstLineIndent = 0.0;
    }

    // Проходимся по токенам (inline-элементам).
    for (final elem in splitted) {
      // Если блочное изображение, переносим на отдельную строку.
      if (elem is ImageInlineElement && elem.mode == ImageDisplayMode.block) {
        if (currentLine.elements.isNotEmpty) {
          commitLine();
        }
        elem.performLayout(effectiveWidth);
        currentLine.elements.add(elem);
        currentX = elem.width;
        maxAscent = math.max(maxAscent, elem.baseline);
        maxDescent = math.max(maxDescent, elem.height - elem.baseline);
        commitLine();
        continue;
      }

      double availableWidth = effectiveWidth - currentX;
      if (!isRTL && currentLine.elements.isEmpty && firstLineIndent > 0) {
        currentX += firstLineIndent;
        availableWidth -= firstLineIndent;
      } else if (isRTL && currentLine.elements.isEmpty && firstLineIndent > 0) {
        availableWidth -= firstLineIndent;
      }

      elem.performLayout(availableWidth);

      // Если не помещается
      if (currentX + elem.width > effectiveWidth && currentLine.elements.isNotEmpty) {
        // Пытаемся выполнить мягкий перенос (\u00AD)
        if (elem is TextInlineElement && allowSoftHyphens) {
          final splittedPair = _trySplitBySoftHyphen(elem, effectiveWidth - currentX);
          if (splittedPair != null) {
            final leftPart = splittedPair[0];
            final rightPart = splittedPair[1];

            leftPart.performLayout(effectiveWidth - currentX);
            currentLine.elements.add(leftPart);
            currentX += leftPart.width;
            maxAscent = math.max(maxAscent, leftPart.baseline);
            maxDescent = math.max(maxDescent, leftPart.height - leftPart.baseline);
            commitLine();

            rightPart.performLayout(effectiveWidth);
            currentLine.elements.add(rightPart);
            currentX = rightPart.width;
            maxAscent = math.max(maxAscent, rightPart.baseline);
            maxDescent = math.max(maxDescent, rightPart.height - rightPart.baseline);
          } else {
            // Целиком переносим на новую строку
            commitLine();
            elem.performLayout(effectiveWidth);
            currentLine.elements.add(elem);
            currentX = elem.width;
            maxAscent = math.max(maxAscent, elem.baseline);
            maxDescent = math.max(maxDescent, elem.height - elem.baseline);
          }
        } else {
          commitLine();
          elem.performLayout(effectiveWidth);
          currentLine.elements.add(elem);
          currentX = elem.width;
          maxAscent = math.max(maxAscent, elem.baseline);
          maxDescent = math.max(maxDescent, elem.height - elem.baseline);
        }
      } else {
        // Помещается в текущую строку
        currentLine.elements.add(elem);
        currentX += elem.width;
        maxAscent = math.max(maxAscent, elem.baseline);
        maxDescent = math.max(maxDescent, elem.height - elem.baseline);
      }
    }

    if (currentLine.elements.isNotEmpty) {
      commitLine();
    }

    if (isRTL) {
      for (final line in result) {
        line.elements = line.elements.reversed.toList();
      }
    }
    return result;
  }

  /// Шаг 2: Разбивает строки на многостраничную/многоколоночную структуру.
  MultiColumnPagedLayout _buildMultiColumnPages(CustomTextLayout layout) {
    final lines = layout.lines;
    final pages = <MultiColumnPage>[];

    final totalColsSpacing = columnSpacing * (columns - 1);
    final colWidth = (globalMaxWidth - totalColsSpacing) / columns;

    int currentIndex = 0;
    while (currentIndex < lines.length) {
      final pageColumns = <List<LineLayout>>[];

      for (int col = 0; col < columns; col++) {
        final colLines = <LineLayout>[];
        double usedHeight = 0.0;

        while (currentIndex < lines.length) {
          final line = lines[currentIndex];
          final lineHeight = line.height;
          if (colLines.isEmpty) {
            colLines.add(line);
            usedHeight = lineHeight;
            currentIndex++;
          } else {
            final needed = usedHeight + lineSpacing + lineHeight;
            if (needed <= pageHeight) {
              colLines.add(line);
              usedHeight = needed;
              currentIndex++;
            } else {
              break;
            }
          }
        }
        pageColumns.add(colLines);
        if (currentIndex >= lines.length) break;
      }

      final page = MultiColumnPage(
        columns: pageColumns,
        pageWidth: globalMaxWidth,
        pageHeight: pageHeight,
        columnWidth: colWidth,
        columnSpacing: columnSpacing,
      );
      pages.add(page);

      if (currentIndex >= lines.length) {
        break;
      }
    }

    return MultiColumnPagedLayout(pages);
  }

  /// Шаг 3: Контроль сирот/вдов (заглушка).
  MultiColumnPagedLayout _applyWidowOrphanControl(
      MultiColumnPagedLayout multi,
      CustomTextLayout layout,
      ) {
    // В реальном решении требуется более сложная логика пересчёта строк,
    // здесь лишь оставлен пример (заглушка).
    return multi;
  }

  /// Разбивает inline-элементы на токены, **сохраняя пробелы**.
  /// Для слов добавляем дополнительный пробел в конце ("$token "),
  /// чтобы между словами в итоге оставался визуальный зазор.
  List<InlineElement> _splitTokens(List<InlineElement> elements) {
    final result = <InlineElement>[];

    for (final e in elements) {
      if (e is TextInlineElement) {
        final tokens = e.text.split(RegExp(r'(\s+)'));
        for (final token in tokens) {
          if (token.isEmpty) continue;
          final isWhitespace = token.trim().isEmpty;
          if (isWhitespace) {
            // Сохраняем пробельный токен как есть
            result.add(TextInlineElement(token, e.style));
          } else {
            // Добавляем слово с дополнительным пробелом
            result.add(TextInlineElement("$token ", e.style));
          }
        }
      } else if (e is InlineLinkElement) {
        final tokens = e.text.split(RegExp(r'(\s+)'));
        for (final token in tokens) {
          if (token.isEmpty) continue;
          final isWhitespace = token.trim().isEmpty;
          if (isWhitespace) {
            result.add(InlineLinkElement(token, e.style, e.url));
          } else {
            result.add(InlineLinkElement("$token ", e.style, e.url));
          }
        }
      } else {
        // Изображения и т.д.
        result.add(e);
      }
    }

    return result;
  }

  /// Пытается выполнить мягкий перенос (по символу \u00AD).
  List<TextInlineElement>? _trySplitBySoftHyphen(TextInlineElement elem, double remainingWidth) {
    final raw = elem.text;
    final positions = <int>[];
    for (int i = 0; i < raw.length; i++) {
      if (raw.codeUnitAt(i) == 0x00AD) {
        positions.add(i);
      }
    }
    if (positions.isEmpty) return null;

    for (int i = positions.length - 1; i >= 0; i--) {
      final idx = positions[i];
      if (idx < raw.length - 1) {
        // leftPart + '-' + leftover
        final leftPart = raw.substring(0, idx) + '-';
        final rightPart = raw.substring(idx + 1);

        final testElem = TextInlineElement(leftPart, elem.style);
        testElem.performLayout(remainingWidth);
        if (testElem.width <= remainingWidth) {
          final leftover = TextInlineElement(rightPart, elem.style);
          return [testElem, leftover];
        }
      }
    }
    return null;
  }

  /// Упрощённая функция, если нужно только список строк.
  CustomTextLayout layoutParagraphsOnly() {
    return _layoutAllParagraphs();
  }
}
