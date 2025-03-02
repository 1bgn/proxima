// custom_text_engine/text_layout_engine.dart
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

  /// Выполняет полный layout и возвращает многостраничную раскладку.
  MultiColumnPagedLayout layoutAll() {
    final layout = _layoutAllParagraphs();
    var multi = _buildMultiColumnPages(layout);
    multi = _applyWidowOrphanControl(multi, layout);
    return multi;
  }

  /// Метод, возвращающий только результат разбиения абзацев на строки.
  CustomTextLayout layoutParagraphsOnly() {
    return _layoutAllParagraphs();
  }

  CustomTextLayout _layoutAllParagraphs() {
    final allLines = <LineLayout>[];
    final paragraphIndexOfLine = <int>[];
    double totalHeight = 0.0;

    for (int pIndex = 0; pIndex < paragraphs.length; pIndex++) {
      final para = paragraphs[pIndex];

      // Отладка: проверяем breakable и isSectionEnd
      if (para.breakable) {
        print("[DEBUG] paragraph $pIndex is breakable (possibly emphasis) ${para.inlineElements}");
      } else {
        print("[DEBUG] paragraph $pIndex is NOT breakable");
      }
      if (para.isSectionEnd) {
        print("[DEBUG] paragraph $pIndex isSectionEnd == true ${para.inlineElements}");
      }

      final lines = _layoutSingleParagraph(para);

      for (int i = 0; i < lines.length; i++) {
        paragraphIndexOfLine.add(pIndex);
      }
      allLines.addAll(lines);

      // Если это конец секции, вставляем "пустую" строку-маркер
      if (para.isSectionEnd && allLines.isNotEmpty) {
        final markerLine = LineLayout();
        markerLine.width = 0;
        markerLine.height = 0;
        markerLine.maxAscent = 0;
        markerLine.maxDescent = 0;
        allLines.add(markerLine);
        paragraphIndexOfLine.add(pIndex);
      }

      double paraHeight = 0.0;
      for (int i = 0; i < lines.length; i++) {
        paraHeight += lines[i].height;
        if (i < lines.length - 1) {
          paraHeight += lineSpacing;
        }
      }
      totalHeight += paraHeight;

      if (pIndex < paragraphs.length - 1) {
        totalHeight += paragraphs[pIndex].paragraphSpacing;
      }
    }

    return CustomTextLayout(
      lines: allLines,
      totalHeight: totalHeight,
      paragraphIndexOfLine: paragraphIndexOfLine,
    );
  }


  /// Разбивает один абзац на строки с учётом paragraph.maxWidth.
  List<LineLayout> _layoutSingleParagraph(ParagraphBlock paragraph) {
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

      if (currentX + elem.width > effectiveWidth && currentLine.elements.isNotEmpty) {
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

  /// Формирует многостраничную/многоколоночную раскладку.
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
          LineLayout line = lines[currentIndex];
          // Если это маркер конца секции (width == 0 && height == 0), страница обрывается резко.
          if (line.width == 0 && line.height == 0) {
            currentIndex++;
            if (colLines.isNotEmpty) {
              break;
            } else {
              continue;
            }
          }
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
              // Если строка не помещается:
              final paraIndex = layout.paragraphIndexOfLine[currentIndex];
              final para = paragraphs[paraIndex];
              // Если это конец секции, страница обрывается резко.
              if (para.isSectionEnd) {
                break;
              }
              // Для остальных, если абзац разрешён к дроблению, пытаемся разбить строку.
              final available = pageHeight - usedHeight - lineSpacing;
              if (para.breakable && available > 0) {
                final splitPair = _splitLine(line, available);
                if (splitPair != null) {
                  colLines.add(splitPair.first);
                  usedHeight = pageHeight; // Заполняем оставшееся пространство.
                  // Остаток строки остаётся для следующей страницы.
                  lines[currentIndex] = splitPair.second;
                }
              }
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
      if (currentIndex >= lines.length) break;
    }
    return MultiColumnPagedLayout(pages);
  }

  /// Пытается разбить строку [line] так, чтобы первая часть умещалась в [availableHeight].
  /// Перебирает inline-элементы и находит индекс для разделения.
  /// Если дробление возможно, возвращает пару LineLayout: (fittingLine, remainingLine); иначе – null.
  _LineSplitPair? _splitLine(LineLayout line, double availableHeight) {
    if (line.elements.length < 2) return null;
    double currentWidth = 0.0;
    double maxAscent = 0.0;
    double maxDescent = 0.0;
    int splitIndex = 0;
    for (int i = 0; i < line.elements.length; i++) {
      final elem = line.elements[i];
      currentWidth += elem.width;
      maxAscent = math.max(maxAscent, elem.baseline);
      maxDescent = math.max(maxDescent, elem.height - elem.baseline);
      final tentativeHeight = maxAscent + maxDescent;
      if (tentativeHeight > availableHeight) {
        splitIndex = i;
        break;
      }
    }
    if (splitIndex <= 0 || splitIndex >= line.elements.length) return null;
    final firstLine = LineLayout();
    firstLine.elements = line.elements.sublist(0, splitIndex);
    firstLine.width = firstLine.elements.fold(0, (sum, e) => sum + e.width);
    firstLine.maxAscent = firstLine.elements.fold(0, (m, e) => math.max(m, e.baseline));
    firstLine.maxDescent = firstLine.elements.fold(0, (m, e) => math.max(m, e.height - e.baseline));
    firstLine.height = firstLine.maxAscent + firstLine.maxDescent;

    final secondLine = LineLayout();
    secondLine.elements = line.elements.sublist(splitIndex);
    secondLine.width = secondLine.elements.fold(0, (sum, e) => sum + e.width);
    secondLine.maxAscent = secondLine.elements.fold(0, (m, e) => math.max(m, e.baseline));
    secondLine.maxDescent = secondLine.elements.fold(0, (m, e) => math.max(m, e.height - e.baseline));
    secondLine.height = secondLine.maxAscent + secondLine.maxDescent;

    return _LineSplitPair(firstLine, secondLine);
  }

  /// Контроль сирот/вдов – упрощённая заглушка.
  MultiColumnPagedLayout _applyWidowOrphanControl(
      MultiColumnPagedLayout multi,
      CustomTextLayout layout) {
    return multi;
  }

  /// Разбивает inline-элементы на токены, сохраняя пробелы.
  /// Для слов добавляет дополнительный пробел в конце для визуального зазора.
  List<InlineElement> _splitTokens(List<InlineElement> elements) {
    final result = <InlineElement>[];
    for (final e in elements) {
      if (e is TextInlineElement) {
        final tokens = e.text.split(RegExp(r'(\s+)'));
        for (final token in tokens) {
          if (token.isEmpty) continue;
          final isWhitespace = token.trim().isEmpty;
          if (isWhitespace) {
            result.add(TextInlineElement(token, e.style));
          } else {
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
        result.add(e);
      }
    }
    return result;
  }

  /// Пытается выполнить мягкий перенос (по символу \u00AD) для TextInlineElement.
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
}

class _LineSplitPair {
  final LineLayout first;
  final LineLayout second;
  _LineSplitPair(this.first, this.second);
}
