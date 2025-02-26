/// text_layout_engine.dart
///
/// Основной движок верстки (AdvancedLayoutEngine).
///  1. Раскладывает параграфы в строки (LineLayout).
///  2. Разбивает на страницы и колонки.
///  3. Применяет (упрощённо) логику сирот и вдов.
///  4. Учитывает переноси по \u00AD (мягкий перенос).
///
/// Можно расширять логику для полноценного BiDi,
/// более сложного justify, и т.д.

import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'inline_elements.dart';
import 'paragraph_block.dart';
import 'line_layout.dart';

/// Основной класс-движок, который всё разбивает.
class AdvancedLayoutEngine {
  final List<ParagraphBlock> paragraphs;

  /// Ширина для верстки (например, ширина экрана или контейнера).
  final double globalMaxWidth;

  /// Межстрочный интервал.
  final double lineSpacing;

  /// Глобальное выравнивание, если в абзаце [textAlign] = null.
  final CustomTextAlign globalTextAlign;

  /// Разрешаем ли переносы по мягкому переносу (\u00AD).
  final bool allowSoftHyphens;

  /// Количество колонок на странице.
  final int columns;

  /// Расстояние между колонками.
  final double columnSpacing;

  /// Высота «страницы».
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

  /// Выполнить полный layout, вернув многостраничную структуру.
  MultiColumnPagedLayout layoutAll() {
    // 1) Сплошной список строк
    final fullLayout = _layoutAllParagraphs();

    // 2) Разбиваем на страницы / колонки
    var multiPaged = _buildMultiColumnPages(fullLayout);

    // 3) Применяем логику сирот/вдов (упрощённо).
    multiPaged = _applyWidowOrphanControl(multiPaged, fullLayout);

    return multiPaged;
  }

  /// Раскладываем все абзацы в «плоский» список строк.
  CustomTextLayout _layoutAllParagraphs() {
    final lines = <LineLayout2>[];
    final paragraphIndexOfLine = <int>[];
    double totalHeight = 0.0;

    for (int pIndex = 0; pIndex < paragraphs.length; pIndex++) {
      final para = paragraphs[pIndex];
      final paraLines = _layoutSingleParagraph(para);

      // Запоминаем, к какому абзацу относятся эти строки
      for (int i = 0; i < paraLines.length; i++) {
        paragraphIndexOfLine.add(pIndex);
      }

      lines.addAll(paraLines);

      // Считаем суммарную высоту (логическую)
      double localHeight = 0.0;
      for (int i = 0; i < paraLines.length; i++) {
        localHeight += paraLines[i].height;
        if (i < paraLines.length - 1) {
          localHeight += lineSpacing;
        }
      }

      totalHeight += localHeight;
      // Отступ после абзаца
      if (pIndex < paragraphs.length - 1) {
        totalHeight += para.paragraphSpacing;
      }
    }

    return CustomTextLayout(
      lines: lines,
      totalHeight: totalHeight,
      paragraphIndexOfLine: paragraphIndexOfLine,
    );
  }

  /// Раскладываем один абзац в строки.
  List<LineLayout2> _layoutSingleParagraph(ParagraphBlock paragraph) {
    final splitted = _splitBySpaces(paragraph.inlineElements);

    bool isRTL = paragraph.textDirection == CustomTextDirection.rtl;
    double firstLineIndent = paragraph.firstLineIndent;

    final result = <LineLayout2>[];
    var currentLine = LineLayout2();
    double currentX = 0.0;
    double maxAscent = 0.0;
    double maxDescent = 0.0;

    void commitLine() {
      currentLine.width = currentX;
      currentLine.maxAscent = maxAscent;
      currentLine.maxDescent = maxDescent;
      currentLine.height = maxAscent + maxDescent;
      result.add(currentLine);

      currentLine = LineLayout2();
      currentX = 0.0;
      maxAscent = 0.0;
      maxDescent = 0.0;

      // Со второй строки отступ не нужен
      firstLineIndent = 0.0;
    }

    for (final elem in splitted) {
      // Блочная картинка => отдельная строка
      if (elem is ImageInlineElement && elem.mode == ImageDisplayMode.block) {
        if (currentLine.elements.isNotEmpty) {
          commitLine();
        }
        elem.performLayout(globalMaxWidth);
        currentLine.elements.add(elem);
        currentX = elem.width;
        maxAscent = math.max(maxAscent, elem.baseline);
        maxDescent = math.max(maxDescent, elem.height - elem.baseline);
        commitLine();
        continue;
      }

      double availableWidth = globalMaxWidth - currentX;
      // Учет отступа первой строки
      if (!isRTL && currentLine.elements.isEmpty && firstLineIndent > 0) {
        currentX += firstLineIndent;
        availableWidth -= firstLineIndent;
      } else if (isRTL && currentLine.elements.isEmpty && firstLineIndent > 0) {
        availableWidth -= firstLineIndent;
      }

      elem.performLayout(availableWidth);

      if (currentX + elem.width > globalMaxWidth && currentLine.elements.isNotEmpty) {
        // перенос
        if (elem is TextInlineElement && allowSoftHyphens) {
          final splittedPair = _trySplitBySoftHyphen(elem, globalMaxWidth - currentX);
          if (splittedPair != null) {
            final leftPart = splittedPair[0];
            final rightPart = splittedPair[1];
            leftPart.performLayout(globalMaxWidth - currentX);

            currentLine.elements.add(leftPart);
            currentX += leftPart.width;
            maxAscent = math.max(maxAscent, leftPart.baseline);
            maxDescent = math.max(maxDescent, leftPart.height - leftPart.baseline);
            commitLine();

            rightPart.performLayout(globalMaxWidth);
            currentLine.elements.add(rightPart);
            currentX = rightPart.width;
            maxAscent = math.max(maxAscent, rightPart.baseline);
            maxDescent = math.max(maxDescent, rightPart.height - rightPart.baseline);
          } else {
            commitLine();
            elem.performLayout(globalMaxWidth);
            currentLine.elements.add(elem);
            currentX = elem.width;
            maxAscent = math.max(maxAscent, elem.baseline);
            maxDescent = math.max(maxDescent, elem.height - elem.baseline);
          }
        } else {
          commitLine();
          elem.performLayout(globalMaxWidth);
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

    // RTL => реверс элементов в каждой строке
    if (isRTL) {
      for (final line in result) {
       reverseListInPlace( line.elements);
      }
    }

    return result;
  }
  void reverseListInPlace<T>(List<T> list) {
    for (int i = 0, j = list.length - 1; i < j; i++, j--) {
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }
  /// Разбиваем в итоге на страницы и колонки.
  MultiColumnPagedLayout _buildMultiColumnPages(CustomTextLayout layout) {
    final lines = layout.lines;
    final pages = <MultiColumnPage>[];

    final totalColumnSpacing = columnSpacing * (columns - 1);
    final colWidth = (globalMaxWidth - totalColumnSpacing) / columns;

    int currentLineIndex = 0;
    while (currentLineIndex < lines.length) {
      final pageColumns = <List<LineLayout2>>[];

      for (int col = 0; col < columns; col++) {
        final colLines = <LineLayout2>[];
        double usedHeight = 0.0;

        while (currentLineIndex < lines.length) {
          final line = lines[currentLineIndex];
          final lineHeight = line.height;
          if (colLines.isEmpty) {
            colLines.add(line);
            usedHeight = lineHeight;
            currentLineIndex++;
          } else {
            final needed = usedHeight + lineSpacing + lineHeight;
            if (needed <= pageHeight) {
              colLines.add(line);
              usedHeight = needed;
              currentLineIndex++;
            } else {
              break;
            }
          }
        }

        pageColumns.add(colLines);
        if (currentLineIndex >= lines.length) {
          break;
        }
      }

      final page = MultiColumnPage(
        columns: pageColumns,
        pageWidth: globalMaxWidth,
        pageHeight: pageHeight,
        columnWidth: colWidth,
        columnSpacing: columnSpacing,
      );
      pages.add(page);

      if (currentLineIndex >= lines.length) {
        break;
      }
    }

    return MultiColumnPagedLayout(pages);
  }

  /// Контроль сирот/вдов (упрощённо).
  MultiColumnPagedLayout _applyWidowOrphanControl(
      MultiColumnPagedLayout multiPaged,
      CustomTextLayout layout,
      ) {
    // В реальном решении нужно сложный откат и пересчёт.
    // Здесь — лишь заглушка, которая возвращает без изменений.
    return multiPaged;
  }

  /// Разбиваем элементы абзаца по пробелам и т.д., чтобы проще укладывать.
  List<InlineElement> _splitBySpaces(List<InlineElement> elements) {
    final result = <InlineElement>[];
    for (final e in elements) {
      if (e is TextInlineElement) {
        final tokens = e.text.split(RegExp(r'(\s+)'));
        for (final token in tokens) {
          if (token.isEmpty) continue;
          result.add(TextInlineElement(token, e.style));
        }
      } else if (e is InlineLinkElement) {
        final tokens = e.text.split(RegExp(r'(\s+)'));
        for (final token in tokens) {
          if (token.isEmpty) continue;
          result.add(InlineLinkElement(token, e.style, e.url));
        }
      } else {
        result.add(e);
      }
    }
    return result;
  }

  /// Пытаемся разорвать слово по \u00AD (soft hyphen).
  List<TextInlineElement>? _trySplitBySoftHyphen(
      TextInlineElement elem,
      double remainingWidth,
      ) {
    final raw = elem.text;
    final positions = <int>[];
    for (int i = 0; i < raw.length; i++) {
      if (raw.codeUnitAt(i) == 0x00AD) {
        positions.add(i);
      }
    }
    if (positions.isEmpty) return null;

    // Перебираем с конца
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
