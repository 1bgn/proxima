// // large_book_paginator.dart
//
// import 'custom_text_engine/line_layout.dart';
// import 'custom_text_engine/paragraph_block.dart';
// import 'custom_text_engine/text_layout_engine.dart';
//
// import 'dart:math' as math;
//
// /// Предположим, вы хотите:
// ///  1) Один раз получить «сплошной» список строк (LineLayout) на всю книгу.
// ///  2) Сохранить «pageOffsets» — индексы начала каждой страницы.
// ///  3) Позволять быстро переходить к странице N.
// ///
// /// При этом ваш текущий text_layout_engine.dart возвращает MultiColumnPagedLayout.
// /// Но мы хотим «сырые» строки (CustomTextLayout).
// /// -> добавляем публичный метод layoutParagraphsOnly().
// /// Вам нужно в вашем AdvancedLayoutEngine:
// ///    CustomTextLayout layoutParagraphsOnly() => _layoutAllParagraphs();
// ///
// /// Тогда LargeBookPaginator вызывает engine.layoutParagraphsOnly()
// /// и сам вручную разбивает на страницы.
//
// class LargeBookPaginator {
//   // Параметры, аналогичные движку
//   double globalMaxWidth;
//   double lineSpacing;
//   final CustomTextAlign globalTextAlign;
//   bool allowSoftHyphens;
//   int columns;
//   double columnSpacing;
//   double pageHeight;
//
//   final List<ParagraphBlock> paragraphs;
//
//   // Храним "плоский" список строк
//   late CustomTextLayout _flatLayout;
//
//   // Массив pageOffsets[n] = индекс строки, с которой начинается страница n
//   final List<int> pageOffsets = [];
//   int totalPages = 0;
//
//   LargeBookPaginator({
//     required this.paragraphs,
//     required this.globalMaxWidth,
//     required this.lineSpacing,
//     required this.globalTextAlign,
//     required this.allowSoftHyphens,
//     required this.columns,
//     required this.columnSpacing,
//     required this.pageHeight,
//   });
//
//   /// Выполняем раскладку абзацев «в плоский вид» (без колонок).
//   /// Затем сами считаем постраничное деление (pageOffsets).
//   void layoutWholeBook() {
//     final engine = AdvancedLayoutEngine(
//       paragraphs: paragraphs,
//       globalMaxWidth: globalMaxWidth,
//       lineSpacing: lineSpacing,
//       globalTextAlign: globalTextAlign,
//       allowSoftHyphens: allowSoftHyphens,
//       columns: columns,
//       columnSpacing: columnSpacing,
//       pageHeight: pageHeight,
//     );
//
//     // В text_layout_engine.dart добавлен public метод layoutParagraphsOnly(),
//     // который возвращает CustomTextLayout (список LineLayout).
//     _flatLayout = engine.layoutParagraphsOnly();
//
//     // Теперь _flatLayout.lines хранит все строки целой книги (без колоночной разбивки).
//     _buildPageOffsets(_flatLayout.lines);
//   }
//
//   int get pageCount => totalPages;
//
//   /// Получаем MultiColumnPage для страницы [pageIndex].
//   /// То есть внутри мы берём нужный блок строк (start..end) и разбиваем на колонки,
//   /// повторяя (упрощённо) логику, которая в движке.
//   MultiColumnPage getPage(int pageIndex) {
//     if (pageIndex < 0 || pageIndex >= totalPages) {
//       // Пустая
//       return MultiColumnPage(
//         columns: [],
//         pageWidth: globalMaxWidth,
//         pageHeight: pageHeight,
//         columnWidth: 1,
//         columnSpacing: columnSpacing,
//       );
//     }
//
//     final start = pageOffsets[pageIndex];
//     final end = (pageIndex == totalPages - 1)
//         ? _flatLayout.lines.length
//         : pageOffsets[pageIndex + 1];
//     final linesForPage = _flatLayout.lines.sublist(start, end);
//
//     // Разбиваем linesForPage по колонкам
//     return _buildColumns(linesForPage);
//   }
//
//   // ----------------------------------------------------------------------------
//   // Вспомогательные методы:
//
//   /// Простое деление массива строк на страницы по высоте [pageHeight].
//   void _buildPageOffsets(List<LineLayout> lines) {
//     pageOffsets.clear();
//     if (lines.isEmpty) {
//       pageOffsets.add(0);
//       totalPages = 1;
//       return;
//     }
//     int currentLine = 0;
//     double usedHeight = 0.0;
//
//     pageOffsets.add(0); // первая страница с 0-й строки
//     for (int i = 0; i < lines.length; i++) {
//       final line = lines[i];
//       if (i == currentLine) {
//         usedHeight = line.height;
//       } else {
//         final needed = usedHeight + lineSpacing + line.height;
//         if (needed <= pageHeight) {
//           usedHeight = needed;
//         } else {
//           // новая страница
//           currentLine = i;
//           pageOffsets.add(currentLine);
//           usedHeight = line.height;
//         }
//       }
//     }
//     totalPages = pageOffsets.length;
//   }
//
//   /// Разбиваем linesForPage на колонки, аналогично _buildMultiColumnPages,
//   /// только для одной страницы.
//   MultiColumnPage _buildColumns(List<LineLayout> linesForPage) {
//     final totalColsSpacing = columnSpacing * (columns - 1);
//     final colWidth = (globalMaxWidth - totalColsSpacing) / columns;
//
//     final pageCols = <List<LineLayout>>[];
//     int idx = 0;
//
//     while (idx < linesForPage.length) {
//       if (pageCols.length == columns) break;
//       final colLines = <LineLayout>[];
//       double usedHeight = 0.0;
//
//       while (idx < linesForPage.length) {
//         final line = linesForPage[idx];
//         final lineHeight = line.height;
//         if (colLines.isEmpty) {
//           colLines.add(line);
//           usedHeight = lineHeight;
//           idx++;
//         } else {
//           final needed = usedHeight + lineSpacing + lineHeight;
//           if (needed <= pageHeight) {
//             colLines.add(line);
//             usedHeight = needed;
//             idx++;
//           } else {
//             break;
//           }
//         }
//       }
//
//       pageCols.add(colLines);
//     }
//
//     return MultiColumnPage(
//       columns: pageCols,
//       pageWidth: globalMaxWidth,
//       pageHeight: pageHeight,
//       columnWidth: colWidth,
//       columnSpacing: columnSpacing,
//     );
//   }
// }
