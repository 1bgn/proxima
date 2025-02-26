// // paginator.dart
// import 'package:flutter/material.dart';
// import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/paragraph_block.dart';
// import 'custom_text_engine/advanced_text_widget.dart';
// import 'custom_text_engine/line_layout.dart';
//
// import 'custom_text_engine/text_layout_engine.dart';
// import 'fb2_parser.dart';
//
// /// Класс, который формирует общий MultiColumnPagedLayout по всем главам,
// /// начиная каждую главу с новой страницы (по сути, «склейка» раскладок глав).
// class FB2Paginator {
//   final double globalMaxWidth;
//   final double lineSpacing;
//   final CustomTextAlign globalTextAlign;
//   final bool allowSoftHyphens;
//   final int columns;
//   final double columnSpacing;
//   final double pageHeight;
//
//   FB2Paginator({
//     required this.globalMaxWidth,
//     required this.lineSpacing,
//     required this.globalTextAlign,
//     required this.allowSoftHyphens,
//     required this.columns,
//     required this.columnSpacing,
//     required this.pageHeight,
//   });
//
//   MultiColumnPagedLayout layoutAllChapters(List<ChapterData> chapters) {
//     final allPages = <MultiColumnPage>[];
//
//     for (final chapter in chapters) {
//       final engine = AdvancedLayoutEngine(
//         paragraphs: chapter.paragraphs,
//         globalMaxWidth: globalMaxWidth,
//         lineSpacing: lineSpacing,
//         globalTextAlign: globalTextAlign,
//         allowSoftHyphens: allowSoftHyphens,
//         columns: columns,
//         columnSpacing: columnSpacing,
//         pageHeight: pageHeight,
//       );
//       final chapterLayout = engine.layoutAll();
//       allPages.addAll(chapterLayout.pages);
//     }
//
//     return MultiColumnPagedLayout(allPages);
//   }
// }
