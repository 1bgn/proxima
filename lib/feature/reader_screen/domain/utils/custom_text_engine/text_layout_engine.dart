// text_layout_engine.dart
import 'dart:math' as math;

import 'inline_elements.dart';
import 'paragraph_block.dart';
import 'line_layout.dart';

/// AdvancedLayoutEngine разбивает абзацы на строки и формирует многостраничную раскладку.
/// Для корректного разделения по секциям необходимо использовать layoutAll(), который учитывает
/// маркер конца секции (isSectionEnd == true). Если абзац с выравниванием right (например, text-author)
/// не начинается с новой строки, перед ним добавляется пустой блок, чтобы гарантировать, что он будет с новой строки.
class AdvancedLayoutEngine {
  final List<ParagraphBlock> paragraphs;
  final double globalMaxWidth;       // Максимальная ширина для всего текста
  double lineSpacing;                // Межстрочный интервал
  final CustomTextAlign globalTextAlign; // Глобальное выравнивание (если параграф не указал иное)
  final bool allowSoftHyphens;       // Разрешить мягкие переносы
  final int columns;                 // Количество колонок на странице
  double columnSpacing;              // Промежуток между колонками
  final double pageHeight;           // Высота одной страницы

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

  /// Метод layoutAll() собирает полную многостраничную раскладку, учитывая разрывы страниц между секциями.
  MultiColumnPagedLayout layoutAll() {
    // 1. Сначала разбиваем все абзацы на строки (LineLayout).
    final layout = _layoutAllParagraphs();
    // 2. Затем группируем строки по секциям и формируем страницы (колонки).
    final multi = _buildPagesWithSectionBreaks(layout);
    return multi;
  }

  /// Если нужно только получить набор строк (LineLayout) без формирования страниц,
  /// используйте данный метод.
  CustomTextLayout layoutParagraphsOnly() {
    return _layoutAllParagraphs();
  }

  // --------------------------------------------------------------------------
  // Шаг 1. Разбивка абзацев на строки
  // --------------------------------------------------------------------------
  CustomTextLayout _layoutAllParagraphs() {
    final allLines = <LineLayout>[];
    final paragraphIndexOfLine = <int>[];
    double totalHeight = 0.0;

    for (int pIndex = 0; pIndex < paragraphs.length; pIndex++) {
      final para = paragraphs[pIndex];

      // Если у абзаца задано right-выравнивание и есть предыдущие строки – начинаем с новой строки
      if (para.textAlign == CustomTextAlign.right && allLines.isNotEmpty) {
        allLines.add(LineLayout());
        paragraphIndexOfLine.add(pIndex);
      }

      // Разбиваем абзац на строки
      final lines = _layoutSingleParagraph(para);

      // Если строк меньше минимального количества, добавляем пустые строки
      if (lines.length < para.minimumLines) {
        final deficit = para.minimumLines - lines.length;
        for (int i = 0; i < deficit; i++) {
          final emptyLine = LineLayout();
          emptyLine.width = 0;
          emptyLine.height = lines.isNotEmpty ? lines.last.height : 20;
          emptyLine.textAlign = para.textAlign ?? globalTextAlign;
          emptyLine.textDirection = para.textDirection;
          lines.add(emptyLine);
        }
      }

      // Добавляем строки абзаца
      for (int i = 0; i < lines.length; i++) {
        paragraphIndexOfLine.add(pIndex);
      }
      allLines.addAll(lines);

      // Добавляем paragraphSpacing, если это не последний абзац
      if (pIndex < paragraphs.length - 1 && para.paragraphSpacing > 0) {
        final spacingLine = LineLayout();
        spacingLine.width = 0;
        spacingLine.height = para.paragraphSpacing;
        spacingLine.textAlign = para.textAlign ?? globalTextAlign;
        spacingLine.textDirection = para.textDirection;
        allLines.add(spacingLine);
        paragraphIndexOfLine.add(pIndex);
      }

      // Подсчёт общей высоты (опционально, если требуется)
      double paraH = 0.0;
      for (int i = 0; i < lines.length; i++) {
        paraH += lines[i].height;
        if (i < lines.length - 1) {
          paraH += lineSpacing;
        }
      }
      totalHeight += paraH;
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


  /// Разбивка одного ParagraphBlock на строки (LineLayout).
  List<LineLayout> _layoutSingleParagraph(ParagraphBlock paragraph) {
    final effectiveWidth = paragraph.maxWidth != null
        ? globalMaxWidth * paragraph.maxWidth!
        : globalMaxWidth;

    final splitted = _splitTokens(paragraph.inlineElements);
    final result = <LineLayout>[];

    var currentLine = LineLayout();
    final isRTL = paragraph.textDirection == CustomTextDirection.rtl;

    // Переменные, используемые в функции, должны быть объявлены раньше
    double currentX = 0.0;
    double maxAscent = 0.0;
    double maxDescent = 0.0;
    bool isFirstLine = true;

    // Функция для применения отступа первой строки (красная строка)
    void applyIndentIfNeeded() {
      if (isFirstLine && !isRTL && paragraph.enableRedLine && paragraph.firstLineIndent > 0) {
        final indentElem = IndentInlineElement(indentWidth: paragraph.firstLineIndent);
        indentElem.performLayout(paragraph.firstLineIndent);
        currentLine.elements.add(indentElem);
        currentX += paragraph.firstLineIndent;
      }
    }

    void commitLine() {
      currentLine.width = currentX;
      currentLine.maxAscent = maxAscent;
      currentLine.maxDescent = maxDescent;
      currentLine.height = maxAscent + maxDescent;
      currentLine.textAlign = paragraph.textAlign ?? globalTextAlign;
      currentLine.textDirection = paragraph.textDirection;

      if (paragraph.maxWidth != null && paragraph.containerAlignment != null) {
        final effectiveWidth = globalMaxWidth * paragraph.maxWidth!;
        final extra = globalMaxWidth - effectiveWidth;
        switch (paragraph.containerAlignment!) {
          case CustomTextAlign.right:
            currentLine.containerOffset = extra; // сдвигаем весь блок вправо
            break;
          case CustomTextAlign.center:
            currentLine.containerOffset = extra / 2;
            break;
          default: // left, justify
            currentLine.containerOffset = 0;
            break;
        }
        // Дополнительно сохраняем фактор, чтобы при отрисовке знать, какой ширины блок
        currentLine.containerOffsetFactor = paragraph.maxWidth!;
      } else {
        currentLine.containerOffset = 0;
        currentLine.containerOffsetFactor = 1.0;
      }

      result.add(currentLine);
      currentLine = LineLayout();
      currentX = 0.0;
      maxAscent = 0.0;
      maxDescent = 0.0;
      isFirstLine = false;
    }




    // Применяем отступ для первой строки, если нужно
    applyIndentIfNeeded();

    for (final elem in splitted) {
      double availableWidth = effectiveWidth - currentX;
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






  /// Шаг 2. Формирование страниц (MultiColumnPagedLayout) с учётом разбиения по секциям:
  /// - Собираем строки в секции (каждый абзац с isSectionEnd == true завершает секцию).
  /// - Каждая секция заканчивается разрывом страницы.
  MultiColumnPagedLayout _buildPagesWithSectionBreaks(CustomTextLayout layout) {
    final lines = layout.lines;
    final pIndexLine = layout.paragraphIndexOfLine;
    final pages = <MultiColumnPage>[];

    // 1. Разбиваем все строки на секции
    final sections = <List<LineLayout>>[];
    var currentSection = <LineLayout>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      currentSection.add(line);

      // Проверяем, относится ли строка к абзацу, у которого isSectionEnd == true
      final paraIndex = pIndexLine[i];
      if (paraIndex >= 0 && paraIndex < paragraphs.length) {
        final para = paragraphs[paraIndex];
        // Если абзац помечен как конец секции,
        // и текущая строка фактически пустая (width=0,height=0), значит это явный маркер
        if (para.isSectionEnd && line.width == 0 && line.height == 0) {
          // Закрываем секцию
          sections.add(currentSection);
          currentSection = <LineLayout>[];
        }
      }
    }
    if (currentSection.isNotEmpty) {
      sections.add(currentSection);
    }

    // 2. Раскладываем секции по страницам, причём каждая секция завершается
    //    принудительным разрывом страницы.
    final totalColSpacing = columnSpacing * (columns - 1);
    final colWidth = (globalMaxWidth - totalColSpacing) / columns;

    var pageCols = List.generate(columns, (_) => <LineLayout>[]);
    var usedHeights = List<double>.filled(columns, 0.0);
    int currentCol = 0;

    /// Сохранить текущие колонки как готовую страницу
    void commitPage() {
      pages.add(MultiColumnPage(
        columns: pageCols,
        pageWidth: globalMaxWidth,
        pageHeight: pageHeight,
        columnWidth: colWidth,
        columnSpacing: columnSpacing,
      ));
      pageCols = List.generate(columns, (_) => <LineLayout>[]);
      usedHeights = List<double>.filled(columns, 0.0);
      currentCol = 0;
    }

    /// Добавить строку (LineLayout) в текущую колонку,
    /// если не влезло — перейти к следующей колонке или странице.
    void addLineToCurrentCol(LineLayout line) {
      final lineHeight = line.height;

      // Если строка сама по себе выше, чем вся страница:
      if (lineHeight > pageHeight) {
        // Отдаём её на новую страницу целиком
        commitPage();
        pageCols[currentCol].add(line);
        usedHeights[currentCol] = lineHeight;
        return;
      }

      // Нужно место с учётом lineSpacing, если колонка не пустая
      final needed = usedHeights[currentCol] == 0.0
          ? lineHeight
          : (usedHeights[currentCol] + lineSpacing + lineHeight);

      if (needed <= pageHeight) {
        // Помещается в текущую колонку
        if (usedHeights[currentCol] > 0.0) {
          usedHeights[currentCol] += lineSpacing;
        }
        pageCols[currentCol].add(line);
        usedHeights[currentCol] += lineHeight;
      } else {
        // Переходим к следующей колонке
        currentCol++;
        if (currentCol >= columns) {
          // Если колонок больше нет — завершаем страницу
          commitPage();
        }
        pageCols[currentCol].add(line);
        usedHeights[currentCol] = lineHeight;
      }
    }

    // Для каждой секции добавляем строки на страницу,
    // затем делаем commitPage() чтобы перейти на новую
    for (final section in sections) {
      for (int i = 0; i < section.length; i++) {
        final line = section[i];
        addLineToCurrentCol(line);
      }
      // Принудительный разрыв страницы в конце секции
      commitPage();
    }

    // Если после последней секции остались не пустые колонки, нужно их сохранить как страницу
    if (pageCols.any((col) => col.isNotEmpty)) {
      commitPage();
    }

    return MultiColumnPagedLayout(pages);
  }

  // --------------------------------------------------------------------------
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // --------------------------------------------------------------------------

  /// Разбивает inline-элементы на токены с учётом пробелов.
  List<InlineElement> _splitTokens(List<InlineElement> elements) {
    final result = <InlineElement>[];
    for (final e in elements) {
      if (e is TextInlineElement) {
        // Разбиваем текст на куски по пробелам (группа пробелов отдельно)
        final tokens = e.text.split(RegExp(r'(\s+)'));
        for (final token in tokens) {
          if (token.isEmpty) continue;

          final isSpace = token.trim().isEmpty;
          if (isSpace) {
            // Это «пробельный» токен
            result.add(TextInlineElement(token, e.style));
          } else {
            // Добавим пробел в конце, если хотим «слово + пробел»
            // (это один из вариантов реализации)
            result.add(TextInlineElement("$token ", e.style));
          }
        }
      } else if (e is InlineLinkElement) {
        // Аналогично, если есть специальный элемент-ссылка
        final tokens = e.text.split(RegExp(r'(\s+)'));
        for (final token in tokens) {
          if (token.isEmpty) continue;
          final isSpace = token.trim().isEmpty;
          if (isSpace) {
            result.add(InlineLinkElement(token, e.style, e.url));
          } else {
            result.add(InlineLinkElement("$token ", e.style, e.url));
          }
        }
      } else {
        // Если какой-то другой элемент (например, изображение) — добавляем как есть
        result.add(e);
      }
    }
    return result;
  }

  /// Попытка разбить слово по мягкому дефису (\u00AD)
  /// Возвращает [левуюЧасть, правуюЧасть], если получилось разорвать,
  /// или null, если не нашли валидной позиции для переноса.
  List<TextInlineElement>? _trySplitBySoftHyphen(TextInlineElement elem, double remainingWidth) {
    final raw = elem.text;
    final positions = <int>[];
    for (int i = 0; i < raw.length; i++) {
      // код \u00AD == 0x00AD
      if (raw.codeUnitAt(i) == 0x00AD) {
        positions.add(i);
      }
    }
    if (positions.isEmpty) return null;

    // Перебираем позиции мягкого дефиса с конца (чтобы найти максимально поздний перенос)
    for (int i = positions.length - 1; i >= 0; i--) {
      final idx = positions[i];
      // Убедимся, что это не последний символ
      if (idx < raw.length - 1) {
        final leftPart = raw.substring(0, idx) + '-';
        final rightPart = raw.substring(idx + 1);
        // Проверим, влезает ли левая часть в оставшееся место
        final testElem = TextInlineElement(leftPart, elem.style);
        testElem.performLayout(remainingWidth);
        if (testElem.width <= remainingWidth) {
          // Возвращаем пару: [леваяЧасть, праваяЧасть]
          final leftover = TextInlineElement(rightPart, elem.style);
          return [testElem, leftover];
        }
      }
    }
    return null;
  }
}

/// CustomTextLayout — результат разбиения на строки (без учёта страниц).
class CustomTextLayout {
  final List<LineLayout> lines;
  final double totalHeight;
  final List<int> paragraphIndexOfLine;

  CustomTextLayout({
    required this.lines,
    required this.totalHeight,
    required this.paragraphIndexOfLine,
  });
}

/// MultiColumnPagedLayout — результат уже постраничной разбивки
/// (несколько страниц, каждая страница состоит из columns).
class MultiColumnPagedLayout {
  final List<MultiColumnPage> pages;

  MultiColumnPagedLayout(this.pages);
}

/// MultiColumnPage — одна страница с несколькими колонками.
class MultiColumnPage {
  final List<List<LineLayout>> columns;
  final double pageWidth;
  final double pageHeight;
  final double columnWidth;
  final double columnSpacing;

  MultiColumnPage({
    required this.columns,
    required this.pageWidth,
    required this.pageHeight,
    required this.columnWidth,
    required this.columnSpacing,
  });
}
