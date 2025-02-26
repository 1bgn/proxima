// large_book_paginator.dart

import 'custom_text_engine/line_layout.dart';
import 'custom_text_engine/paragraph_block.dart';
import 'custom_text_engine/text_layout_engine.dart';

/// Класс, который раскладывает всю книгу (список ParagraphBlock) и
/// хранит в массиве offsets начало каждой страницы, чтобы можно было быстро
/// прыгать к странице N без полного пересчёта.
class LargeBookPaginator {
  final List<ParagraphBlock> paragraphs;
  final double globalMaxWidth;
  final double lineSpacing;
  final CustomTextAlign globalTextAlign;
  final bool allowSoftHyphens;
  final int columns;
  final double columnSpacing;
  final double pageHeight;

  // Результат раскладки (все строки).
  late CustomTextLayout _flatLayout;

  // Массив с индексами строк, с которых начинается каждая страница.
  // pageOffsets[0] = 0 (начинается с 0-й строки),
  // pageOffsets[1] = индекс строки, с которой начинается 2-я страница, и т.д.
  final List<int> pageOffsets = [];

  // Общее число страниц:
  int totalPages = 0;

  LargeBookPaginator({
    required this.paragraphs,
    required this.globalMaxWidth,
    required this.lineSpacing,
    required this.globalTextAlign,
    required this.allowSoftHyphens,
    required this.columns,
    required this.columnSpacing,
    required this.pageHeight,
  });

  /// Раскладываем книгу, формируем offsets.
  void layoutWholeBook() {
    final engine = AdvancedLayoutEngine(
      paragraphs: paragraphs,
      globalMaxWidth: globalMaxWidth,
      lineSpacing: lineSpacing,
      globalTextAlign: globalTextAlign,
      allowSoftHyphens: allowSoftHyphens,
      columns: columns,
      columnSpacing: columnSpacing,
      pageHeight: pageHeight,
    );

    // но! engine.layoutAll() возвращает готовые страницы => memory heavy
    // В большом тексте pages могут занимать много памяти (храним все LineLayout).
    // Для "ленивого" подхода нужно ещё глубже переписывать.

    final layout = engine.layoutAll();
    _flatLayout = CustomTextLayout(
      lines: layout.lines, // <- В реальности, lines: ...,
      totalHeight: layout.totalHeight,
      paragraphIndexOfLine: layout.paragraphIndexOfLine,
    );

    // Но layoutAll() уже вернул MultiColumnPagedLayout (layout.pages).
    // Можем просто взять layout.pages.length => totalPages.
    final totalP = layout.pages.length;
    totalPages = totalP;

    // Заполним pageOffsets:
    pageOffsets.clear();
    int accum = 0;
    for (int i = 0; i < totalP; i++) {
      pageOffsets.add(accum);
      // Узнаём, сколько строк в i-й странице
      final page = layout.pages[i];
      int pageLines = 0;
      for (final col in page.columns) {
        pageLines += col.length;
      }
      accum += pageLines;
    }
    // pageOffsets[n] = индекс строки, с которой начинается страница n.
  }

  /// Получить количество страниц
  int get pageCount => totalPages;

  /// Быстрый переход к странице [pageIndex].
  /// Возвращает список LineLayout, которые нужно рендерить на этой странице, разбитые по колонкам.
  /// NB: по сути, мы восстанавливаем columns, lineSpacing, etc. => упрощённо воспроизводим _buildMultiColumnPages для одной страницы.
  MultiColumnPage getPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= totalPages) {
      // Возвращаем пустую?
      return MultiColumnPage(
        columns: [],
        pageWidth: globalMaxWidth,
        pageHeight: pageHeight,
        columnWidth: (globalMaxWidth - columnSpacing * (columns - 1)) / columns,
        columnSpacing: columnSpacing,
      );
    }

    final startLineIndex = pageOffsets[pageIndex];
    int endLineIndex = (pageIndex == totalPages - 1)
        ? _flatLayout.lines.length
        : pageOffsets[pageIndex + 1];

    final lines = _flatLayout.lines.sublist(startLineIndex, endLineIndex);

    // Теперь разбиваем lines по колонкам
    // (повторяем логику _buildMultiColumnPages, но только для одной "page").
    final colWidth = (globalMaxWidth - columnSpacing * (columns - 1)) / columns;
    final pageColumns = <List<LineLayout>>[];
    int localIndex = 0;
    while (localIndex < lines.length) {
      if (pageColumns.length == columns) break; // все колонки

      final colLines = <LineLayout>[];
      double usedHeight = 0.0;
      while (localIndex < lines.length) {
        final line = lines[localIndex];
        final lineHeight = line.height;
        if (colLines.isEmpty) {
          colLines.add(line);
          usedHeight = lineHeight;
          localIndex++;
        } else {
          final needed = usedHeight + lineSpacing + lineHeight;
          if (needed <= pageHeight) {
            colLines.add(line);
            usedHeight = needed;
            localIndex++;
          } else {
            break;
          }
        }
      }
      pageColumns.add(colLines);
    }

    return MultiColumnPage(
      columns: pageColumns,
      pageWidth: globalMaxWidth,
      pageHeight: pageHeight,
      columnWidth: colWidth,
      columnSpacing: columnSpacing,
    );
  }
}
