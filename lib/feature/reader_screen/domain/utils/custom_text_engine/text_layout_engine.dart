// lib/custom_text_engine/text_layout_engine.dart
//
// Раскладывает абзацы в строки, обрабатывает пробелы, пунктуацию и мягкие переносы.

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

  MultiColumnPagedLayout layoutAll() {
    final layout = _layoutAllParagraphs();
    var multi = _buildMultiColumnPages(layout);
    multi = _applyWidowOrphanControl(multi, layout);
    return multi;
  }

  /// Абзацы -> строки
  CustomTextLayout _layoutAllParagraphs() {
    final allLines = <LineLayout>[];
    final paragraphIndexOfLine = <int>[];
    double totalHeight = 0.0;

    for (int pIndex = 0; pIndex < paragraphs.length; pIndex++) {
      final para = paragraphs[pIndex];
      final lines = _layoutSingleParagraph(para);

      for (int i = 0; i < lines.length; i++) {
        paragraphIndexOfLine.add(pIndex);
      }
      allLines.addAll(lines);

      // Подсчёт высоты
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

  /// Абзац -> строки
  List<LineLayout> _layoutSingleParagraph(ParagraphBlock paragraph) {
    // Главное – корректное разбиение на токены.
    final splitted = _splitTokens(paragraph.inlineElements);

    final result = <LineLayout>[];
    var currentLine = LineLayout();

    bool isRTL = paragraph.textDirection == CustomTextDirection.rtl;
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
      if (elem is ImageInlineElement && elem.mode == ImageDisplayMode.block) {
        // Блочная картинка
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
      if (!isRTL && currentLine.elements.isEmpty && firstLineIndent > 0) {
        currentX += firstLineIndent;
        availableWidth -= firstLineIndent;
      } else if (isRTL && currentLine.elements.isEmpty && firstLineIndent > 0) {
        availableWidth -= firstLineIndent;
      }

      elem.performLayout(availableWidth);

      // Не влезает -> перенос
      if (currentX + elem.width > globalMaxWidth && currentLine.elements.isNotEmpty) {
        // Попытка разорвать по \u00AD
        if (elem is TextInlineElement && allowSoftHyphens) {
          final splitted2 = _trySplitBySoftHyphen(elem, globalMaxWidth - currentX);
          if (splitted2 != null) {
            final leftPart = splitted2[0];
            final rightPart = splitted2[1];

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
        // помещается
        currentLine.elements.add(elem);
        currentX += elem.width;
        maxAscent = math.max(maxAscent, elem.baseline);
        maxDescent = math.max(maxDescent, elem.height - elem.baseline);
      }
    }

    if (currentLine.elements.isNotEmpty) {
      commitLine();
    }

    // RTL -> разворот
    if (isRTL) {
      for (final line in result) {
        line.elements = line.elements.reversed.toList();
      }
    }

    return result;
  }

  /// Шаг 2: строки -> страницы/колонки
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

      if (currentIndex >= lines.length) break;
    }

    return MultiColumnPagedLayout(pages);
  }

  /// Шаг 3: сироты/вдовы – упрощённо
  MultiColumnPagedLayout _applyWidowOrphanControl(
      MultiColumnPagedLayout multi,
      CustomTextLayout layout,
      ) {
    // Пока не реализуем откат строк
    return multi;
  }

  /// Собираем конечные токены (слова, пробелы, пунктуация),
  /// причём для удобства добавим «пробел» автоматически в конец каждого токена, кроме уже явно пробела.
  List<InlineElement> _splitTokens(List<InlineElement> elements) {
    final result = <InlineElement>[];

    for (final elem in elements) {
      if (elem is TextInlineElement) {
        final splitted = _extractTokens(elem.text);
        for (final tok in splitted) {
          if (tok.isEmpty) continue;

          // Если сам tok – это пробел или набор пробелов, добавляем как есть
          // Иначе добавим "tok + " "
          // Но, чтобы не было двойных пробелов после запятых,
          // сделаем логику:
          final isWhitespace = tok.trim().isEmpty;
          if (isWhitespace) {
            // Это чистый пробел
            result.add(TextInlineElement(tok, elem.style));
          } else {
            // Это слово/пунктуация
            // добавим пробел позади, чтобы гарантированно разделять со следующим токеном
            result.add(TextInlineElement("$tok ", elem.style));
          }
        }
      } else if (elem is InlineLinkElement) {
        final splitted = _extractTokens(elem.text);
        for (final tok in splitted) {
          if (tok.isEmpty) continue;

          final isWhitespace = tok.trim().isEmpty;
          if (isWhitespace) {
            result.add(InlineLinkElement(tok, elem.style, elem.url));
          } else {
            result.add(InlineLinkElement("$tok ", elem.style, elem.url));
          }
        }
      } else {
        // Изображения / etc
        result.add(elem);
      }
    }

    return result;
  }

  /// Выделяем слова, пробелы, пунктуацию
  /// 1) Вставляем пробелы вокруг пунктуации
  /// 2) split (r'(\s+)')
  List<String> _extractTokens(String text) {
    // Вставим пробелы вокруг знаков препинания
    final punctuationRegex = RegExp(r'([,.!?;:()\[\]{}…])');
    final spaced = text.replaceAllMapped(punctuationRegex, (m) {
      final p = m.group(1)!;
      // ставим пробел до и после
      return ' $p ';
    });

    // Разбиваем, включая пробелы
    final tokens = spaced.split(RegExp(r'(\s+)'));
    return tokens;
  }

  /// Мягкий перенос
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
