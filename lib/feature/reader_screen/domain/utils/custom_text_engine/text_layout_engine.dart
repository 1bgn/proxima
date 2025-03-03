// text_layout_engine.dart
import 'dart:math' as math;
import 'inline_elements.dart';
import 'paragraph_block.dart';
import 'line_layout.dart';

class AdvancedLayoutEngine {
  final List<ParagraphBlock> paragraphs;
  final double globalMaxWidth;
  double lineSpacing;
  final CustomTextAlign globalTextAlign;
  final bool allowSoftHyphens;
  final int columns;         // Количество колонок
  double columnSpacing;      // Расстояние между колонками
  final double pageHeight;   // Высота страницы (по вертикали)

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
    // Сначала разбиваем абзацы на строки
    final layout = _layoutAllParagraphs();
    // Затем строим многостраничную (и многоколоночную) раскладку,
    // позволяя разбивать абзацы частично при переносе
    var multi = _buildMultiColumnPagesWithParagraphSplitting(layout);
    // Опционально применяем контроль сирот/вдов (не реализован здесь)
    multi = _applyWidowOrphanControl(multi, layout);
    return multi;
  }

  /// Возвращает результат разбиения абзацев на строки (без формирования страниц).
  CustomTextLayout layoutParagraphsOnly() {
    return _layoutAllParagraphs();
  }

  /// Разбивает все абзацы на строки с учётом maxWidth, lineSpacing и пр.
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

      // Если абзац завершается секцией, можно вставить маркер (опционально)
      if (para.isSectionEnd && allLines.isNotEmpty) {
        final markerLine = LineLayout();
        markerLine.width = 0;
        markerLine.height = 0;
        markerLine.maxAscent = 0;
        markerLine.maxDescent = 0;
        allLines.add(markerLine);
        paragraphIndexOfLine.add(pIndex);
      }

      // Подсчитываем суммарную высоту абзаца
      double paraHeight = 0.0;
      for (int i = 0; i < lines.length; i++) {
        paraHeight += lines[i].height;
        if (i < lines.length - 1) {
          paraHeight += lineSpacing;
        }
      }
      totalHeight += paraHeight;

      // Добавляем отступ после абзаца
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

  /// Разбивает один ParagraphBlock на строки (LineLayout) с учётом ограничений по ширине.
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

    // Функция, фиксирующая текущую строку в result
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
      // Блочное изображение переносим на отдельную строку
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
      // Первая строка абзаца: отступ
      if (!isRTL && currentLine.elements.isEmpty && firstLineIndent > 0) {
        currentX += firstLineIndent;
        availableWidth -= firstLineIndent;
      } else if (isRTL && currentLine.elements.isEmpty && firstLineIndent > 0) {
        availableWidth -= firstLineIndent;
      }

      elem.performLayout(availableWidth);
      // Если элемент не влезает в текущую строку
      if (currentX + elem.width > effectiveWidth && currentLine.elements.isNotEmpty) {
        // Попытка мягкого переноса (soft hyphen)
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
            // Простой перенос
            commitLine();
            elem.performLayout(effectiveWidth);
            currentLine.elements.add(elem);
            currentX = elem.width;
            maxAscent = math.max(maxAscent, elem.baseline);
            maxDescent = math.max(maxDescent, elem.height - elem.baseline);
          }
        } else {
          // Простой перенос
          commitLine();
          elem.performLayout(effectiveWidth);
          currentLine.elements.add(elem);
          currentX = elem.width;
          maxAscent = math.max(maxAscent, elem.baseline);
          maxDescent = math.max(maxDescent, elem.height - elem.baseline);
        }
      } else {
        // Элемент помещается в текущую строку
        currentLine.elements.add(elem);
        currentX += elem.width;
        maxAscent = math.max(maxAscent, elem.baseline);
        maxDescent = math.max(maxDescent, elem.height - elem.baseline);
      }
    }

    if (currentLine.elements.isNotEmpty) {
      commitLine();
    }

    // При необходимости разворачиваем строки для RTL
    if (isRTL) {
      for (final line in result) {
        line.elements = line.elements.reversed.toList();
      }
    }
    return result;
  }

  /// Формирует многостраничную/многоколоночную раскладку с частичным переносом абзацев.
  MultiColumnPagedLayout _buildMultiColumnPagesWithParagraphSplitting(CustomTextLayout layout) {
    // Шаг 1: группируем строки по абзацам
    final paragraphsMap = <int, List<LineLayout>>{};
    for (int i = 0; i < layout.lines.length; i++) {
      final pIndex = layout.paragraphIndexOfLine[i];
      paragraphsMap.putIfAbsent(pIndex, () => []).add(layout.lines[i]);
    }
    // Собираем группы (абзацы) в порядке pIndex
    final paragraphGroups = <List<LineLayout>>[];
    final sortedKeys = paragraphsMap.keys.toList()..sort();
    for (final k in sortedKeys) {
      paragraphGroups.add(paragraphsMap[k]!);
    }

    // Параметры для колонок
    final totalColsSpacing = columnSpacing * (columns - 1);
    final columnWidth = (globalMaxWidth - totalColsSpacing) / columns;

    // Структуры для хранения страниц
    final pages = <MultiColumnPage>[];

    // Текущая страница (список колонок), каждая колонка – список LineLayout
    List<List<LineLayout>> currentPageCols = List.generate(columns, (_) => []);
    // Текущие высоты каждой колонки
    final usedHeights = List<double>.filled(columns, 0.0);
    int currentCol = 0; // индекс колонки

    // Функция для завершения текущей страницы и создания новой
    void commitPage() {
      // Добавляем текущую страницу в pages
      final page = MultiColumnPage(
        columns: currentPageCols,
        pageWidth: globalMaxWidth,
        pageHeight: pageHeight,
        columnWidth: columnWidth,
        columnSpacing: columnSpacing,
      );
      pages.add(page);
      // Сбрасываем
      currentPageCols = List.generate(columns, (_) => []);
      for (int i = 0; i < columns; i++) {
        usedHeights[i] = 0.0;
      }
      currentCol = 0;
    }

    // Функция для вставки маркера разрыва абзаца (или страницы)
    LineLayout createBreakMarker(double height) {
      final marker = LineLayout();
      marker.width = 0;
      marker.height = height;
      marker.maxAscent = 0;
      marker.maxDescent = 0;
      return marker;
    }

    // Основной цикл по абзацам
    for (final group in paragraphGroups) {
      int index = 0;
      while (index < group.length) {
        // Начинаем собирать часть абзаца, которая поместится в текущую колонку
        double colUsed = usedHeights[currentCol];
        double partHeight = 0.0;
        final part = <LineLayout>[];

        while (index < group.length) {
          final line = group[index];
          final lineHeight = (part.isEmpty ? 0 : lineSpacing) + line.height;
          if (colUsed + lineHeight <= pageHeight) {
            // Помещаем строку в текущую колонку
            part.add(line);
            colUsed += lineHeight;
            index++;
          } else {
            // Строка не помещается в текущую колонку
            break;
          }
        }

        // Добавляем собранные строки в колонку
        currentPageCols[currentCol].addAll(part);
        usedHeights[currentCol] = colUsed;

        // Если абзац не закончился, значит текущая колонка заполнена
        if (index < group.length) {
          // Переходим к следующей колонке
          currentCol++;
          // Если колонки закончились, завершаем страницу
          if (currentCol >= columns) {
            // Добавим маркер разрыва (например, высотой 10) в конец каждой колонки
            for (int c = 0; c < columns; c++) {
              final marker = createBreakMarker(10);
              currentPageCols[c].add(marker);
            }
            commitPage();
          }
        } else {
          // Абзац закончился, добавляем маркер разрыва абзаца
          // (чтобы визуально отделить от следующего абзаца)
          final marker = createBreakMarker(10);
          currentPageCols[currentCol].add(marker);
          usedHeights[currentCol] += 10;
        }
      }
      // Если после добавления абзаца мы близки к заполнению текущей колонки (например, >95%)
      // или хотим явно отделять абзацы, можно при желании перейти к следующей колонке
      if (usedHeights[currentCol] >= pageHeight * 0.95) {
        currentCol++;
        if (currentCol >= columns) {
          // Завершаем страницу
          commitPage();
        }
      }
    }

    // Если остались незаполненные колонки
    // (или не было необходимости формировать новую страницу)
    // добавляем последнюю страницу
    final nonEmpty = currentPageCols.any((col) => col.isNotEmpty);
    if (nonEmpty) {
      commitPage();
    }

    return MultiColumnPagedLayout(pages);
  }

  MultiColumnPagedLayout _applyWidowOrphanControl(
      MultiColumnPagedLayout multi,
      CustomTextLayout layout,
      ) {
    // Здесь можно реализовать дополнительную логику для контроля сирот/вдов.
    return multi;
  }

  /// Разбивает inline-элементы на токены, сохраняя пробелы.
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

  /// Пытается выполнить мягкий перенос (soft hyphen) для TextInlineElement.
  List<TextInlineElement>? _trySplitBySoftHyphen(TextInlineElement elem, double remainingWidth) {
    final raw = elem.text;
    final positions = <int>[];
    for (int i = 0; i < raw.length; i++) {
      if (raw.codeUnitAt(i) == 0x00AD) {
        positions.add(i);
      }
    }
    if (positions.isEmpty) return null;
    // Ищем позицию переноса, начиная с конца
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
