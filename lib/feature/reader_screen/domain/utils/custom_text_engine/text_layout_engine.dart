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
  final double globalMaxWidth;
  double lineSpacing;
  final CustomTextAlign globalTextAlign;
  final bool allowSoftHyphens;
  final int columns;         // количество колонок на странице
  double columnSpacing;      // промежуток между колонками
  final double pageHeight;   // высота страницы

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
    final layout = _layoutAllParagraphs();
    // Для корректного разделения по секциям обязательно используем этот метод:
    final multi = _buildPagesWithSectionBreaks(layout);
    return multi;
  }

  /// Метод, возвращающий только разбиение абзацев на строки (без формирования страниц).
  CustomTextLayout layoutParagraphsOnly() {
    return _layoutAllParagraphs();
  }

  /// --- Шаг 1. Разбивка абзацев на строки ---
  CustomTextLayout _layoutAllParagraphs() {
    final allLines = <LineLayout>[];
    final paragraphIndexOfLine = <int>[];
    double totalHeight = 0.0;

    for (int pIndex = 0; pIndex < paragraphs.length; pIndex++) {
      final para = paragraphs[pIndex];

      // Если параграф имеет выравнивание right (например, text-author),
      // а предыдущий блок не завершён, вставляем пустой блок, чтобы начать с новой строки.
      if (para.textAlign == CustomTextAlign.right && allLines.isNotEmpty) {
        allLines.add(LineLayout());
        paragraphIndexOfLine.add(pIndex);
      }

      final lines = _layoutSingleParagraph(para);
      for (int i = 0; i < lines.length; i++) {
        paragraphIndexOfLine.add(pIndex);
      }
      allLines.addAll(lines);

      double paraH = 0.0;
      for (int i = 0; i < lines.length; i++) {
        paraH += lines[i].height;
        if (i < lines.length - 1) {
          paraH += lineSpacing;
        }
      }
      totalHeight += paraH;
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

  /// Разбивка одного ParagraphBlock на строки.
  List<LineLayout> _layoutSingleParagraph(ParagraphBlock paragraph) {
    final effectiveWidth = paragraph.maxWidth != null
        ? globalMaxWidth * paragraph.maxWidth!
        : globalMaxWidth;

    // Разбиваем inline-элементы на «токены»
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

  /// --- Шаг 2. Построение многостраничной раскладки с разделением по секциям ---
  /// Группируем строки в секции: каждая секция заканчивается абзацем с isSectionEnd == true (обычно это пустая строка).
  MultiColumnPagedLayout _buildPagesWithSectionBreaks(CustomTextLayout layout) {
    final lines = layout.lines;
    final pIndexLine = layout.paragraphIndexOfLine;
    final pages = <MultiColumnPage>[];

    // Группируем строки по секциям.
    final sections = <List<LineLayout>>[];
    var currentSection = <LineLayout>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      currentSection.add(line);
      final paraIndex = pIndexLine[i];
      if (paraIndex >= 0 && paraIndex < paragraphs.length) {
        final para = paragraphs[paraIndex];

        // Если абзац помечен как конец секции и строка является пустым маркером.
        if (para.isSectionEnd && line.width == 0 && line.height == 0) {

          print("brebreber");
          sections.add(currentSection);
          currentSection = <LineLayout>[];
        }
      }
    }
    if (currentSection.isNotEmpty) {
      sections.add(currentSection);
    }

    // Построение страниц: каждая секция завершается разрывом страницы.
    final totalColSpacing = columnSpacing * (columns - 1);
    final colWidth = (globalMaxWidth - totalColSpacing) / columns;

    var pageCols = List.generate(columns, (_) => <LineLayout>[]);
    var usedHeights = List<double>.filled(columns, 0.0);
    int currentCol = 0;

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

    void addLineToCurrentCol(LineLayout line) {
      // Если строка (например, с изображением) слишком высокая, переносим её на новую страницу.
      if (line.height > pageHeight) {
        commitPage();
        pageCols[currentCol].add(line);
        usedHeights[currentCol] = line.height;
        return;
      }
      final needed = (usedHeights[currentCol] == 0.0)
          ? line.height
          : (usedHeights[currentCol] + lineSpacing + line.height);
      if (needed <= pageHeight) {
        if (usedHeights[currentCol] > 0.0) usedHeights[currentCol] += lineSpacing;
        pageCols[currentCol].add(line);
        usedHeights[currentCol] += line.height;
      } else {
        currentCol++;
        if (currentCol >= columns) {
          commitPage();
        }
        pageCols[currentCol].add(line);
        usedHeights[currentCol] = line.height;
      }
    }

    // Основной цикл: для каждой секции добавляем строки, затем завершаем страницу.
    for (int s = 0; s < sections.length; s++) {
      final section = sections[s];
      for (int i = 0; i < section.length; i++) {
        final line = section[i];
        final paraIdx = pIndexLine[i];
        addLineToCurrentCol(line);
      }
      commitPage(); // форсированный разрыв после секции
    }

    if (pageCols.any((col) => col.isNotEmpty)) {
      commitPage();
    }

    return MultiColumnPagedLayout(pages);
  }

  /// --- Вспомогательные методы ---
  /// Разбивает inline-элементы на «токены», сохраняя пробелы.
  List<InlineElement> _splitTokens(List<InlineElement> elements) {
    final result = <InlineElement>[];
    for (final e in elements) {
      if (e is TextInlineElement) {
        final tokens = e.text.split(RegExp(r'(\s+)'));
        for (final token in tokens) {
          if (token.isEmpty) continue;
          final isSpace = token.trim().isEmpty;
          if (isSpace) {
            result.add(TextInlineElement(token, e.style));
          } else {
            result.add(TextInlineElement("$token ", e.style));
          }
        }
      } else if (e is InlineLinkElement) {
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
        result.add(e);
      }
    }
    return result;
  }

  /// Мягкий перенос по символу \u00AD (soft hyphen).
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
