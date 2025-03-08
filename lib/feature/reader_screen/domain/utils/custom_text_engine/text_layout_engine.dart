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
  final int columns;         // Кол-во колонок
  double columnSpacing;      // Пробел между колонками
  final double pageHeight;   // Высота страницы

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
    // Сначала разбиваем абзацы на строки:
    final layout = _layoutAllParagraphs();
    // Затем формируем многостраничную раскладку,
    // где разрыв страницы строго после завершения секции
    return _buildPagesWithSectionBreaks(layout);
  }

  /// Только результат разбивки абзацев на строки (без построения страниц).
  CustomTextLayout layoutParagraphsOnly() {
    return _layoutAllParagraphs();
  }

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

      // Мы не делаем принудительный перенос здесь – просто собираем все строки.
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

  /// Разбиваем один ParagraphBlock на строки (LineLayout).
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
      // Если блочное изображение, переносим на отдельную строку
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
      // Первая строка – учитываем отступ
      if (!isRTL && currentLine.elements.isEmpty && firstLineIndent > 0) {
        currentX += firstLineIndent;
        availableWidth -= firstLineIndent;
      } else if (isRTL && currentLine.elements.isEmpty && firstLineIndent > 0) {
        availableWidth -= firstLineIndent;
      }

      elem.performLayout(availableWidth);
      // Не влезает в строку – перенос
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

    // RTL – разворачиваем строки
    if (isRTL) {
      for (final line in result) {
        line.elements = line.elements.reversed.toList();
      }
    }
    return result;
  }

  /// Собственно построение многостраничной/многоколоночной раскладки.
  /// 1) Группируем строки в секции (до isSectionEnd).
  /// 2) Каждую секцию последовательно раскладываем на страницы/колонки.
  /// 3) После секции – форсированный разрыв страницы.
  MultiColumnPagedLayout _buildPagesWithSectionBreaks(CustomTextLayout layout) {
    final lines = layout.lines;
    final pIndexLine = layout.paragraphIndexOfLine;

    // Группируем строки в списки (секции).
    final sections = <List<LineLayout>>[];
    var currentSec = <LineLayout>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      currentSec.add(line);
      // Проверяем, не является ли абзац концом секции
      final paraIndex = pIndexLine[i];
      if (paraIndex >= 0 && paraIndex < paragraphs.length) {
        final para = paragraphs[paraIndex];
        if (para.isSectionEnd && line.width == 0 && line.height == 0) {
          // Мы достигли конца секции – фиксируем
          sections.add(currentSec);
          currentSec = <LineLayout>[];
        }
      }
    }
    // Если остались строки вне секции (не законченные isSectionEnd), добавим их как одну секцию.
    if (currentSec.isNotEmpty) {
      sections.add(currentSec);
    }

    final pages = <MultiColumnPage>[];

    // Рассчитываем ширину колонки
    final totalColSpacing = columnSpacing * (columns - 1);
    final colWidth = (globalMaxWidth - totalColSpacing) / columns;

    // Текущая страница (список колонок)
    var pageCols = List.generate(columns, (_) => <LineLayout>[]);
    var usedHeights = List.filled(columns, 0.0);
    int currentCol = 0;

    // Функция завершения текущей страницы
    void commitPage() {
      pages.add(MultiColumnPage(
        columns: pageCols,
        pageWidth: globalMaxWidth,
        pageHeight: pageHeight,
        columnWidth: colWidth,
        columnSpacing: columnSpacing,
      ));
      pageCols = List.generate(columns, (_) => <LineLayout>[]);
      usedHeights = List.filled(columns, 0.0);
      currentCol = 0;
    }

    // Функция для добавления строки (LineLayout) в текущую колонку
    // с учётом дробления, если строка очень большая (теоретически).
    void addLineToCurrentCol(LineLayout line) {
      final needed = (usedHeights[currentCol] == 0.0)
          ? line.height
          : (usedHeights[currentCol] + lineSpacing + line.height);
      if (needed <= pageHeight) {
        // Помещаем строку в текущую колонку
        if (usedHeights[currentCol] > 0.0) {
          usedHeights[currentCol] += lineSpacing;
        }
        pageCols[currentCol].add(line);
        usedHeights[currentCol] += line.height;
      } else {
        // Строка не помещается
        // Теоретически можно делать построчное «дробление» внутри одной строки,
        // но обычно LineLayout – уже минимальная единица вывода.
        // Поэтому просто переходим к новой колонке/странице
        currentCol++;
        if (currentCol >= columns) {
          commitPage();
        }
        // Добавляем строку на новую колонку/новую страницу
        pageCols[currentCol].add(line);
        usedHeights[currentCol] = line.height;
      }
    }

    // Основной цикл по секциям
    for (int sIndex = 0; sIndex < sections.length; sIndex++) {
      final section = sections[sIndex];
      // Внутри секции заполняем текущую страницу/колонки,
      // если большие абзацы не влезают, дробим их на нескольких колонках/страницах,
      // но без окончания секции.
      for (int i = 0; i < section.length; i++) {
        final line = section[i];
        addLineToCurrentCol(line);
      }
      // Секция закончена – значит, форсированно завершаем страницу,
      // даже если осталось свободное пространство.
      commitPage();
    }

    // Если по каким-то причинам осталась пустая страница,
    // её можно удалять или оставлять. В данном случае, если текущие колонки пусты,
    // значит мы закончили чётко на секции. Если не пусты – commitPage().
    final isNonEmpty = pageCols.any((col) => col.isNotEmpty);
    if (isNonEmpty) {
      commitPage();
    }

    return MultiColumnPagedLayout(pages);
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
