// fb2_paginator.dart
import 'package:flutter/material.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/line_layout.dart';
import 'dart:math' as math;



import 'custom_text_engine/paragraph_block.dart';
import 'custom_text_engine/text_layout_engine.dart';
import 'fb2_parser.dart'; // чтобы знать, что такое ChapterData

/// Класс, который собирает единый MultiColumnPagedLayout по всем главам,
/// гарантируя, что каждая глава начинается с новой страницы.
class FB2Paginator {
  final double globalMaxWidth;
  final double lineSpacing;
  final CustomTextAlign globalTextAlign;
  final bool allowSoftHyphens;
  final int columns;
  final double columnSpacing;
  final double pageHeight;

  FB2Paginator({
    required this.globalMaxWidth,
    required this.lineSpacing,
    required this.globalTextAlign,
    required this.allowSoftHyphens,
    required this.columns,
    required this.columnSpacing,
    required this.pageHeight,
  });

  /// Формирует единый многостраничный layout по всем главам.
  MultiColumnPagedLayout layoutAllChapters(List<ChapterData> chapters) {
    final allPages = <MultiColumnPage>[];

    for (int i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      // Вызываем движок для этой главы
      final engine = AdvancedLayoutEngine(
        paragraphs: chapter.paragraphs,
        globalMaxWidth: globalMaxWidth,
        lineSpacing: lineSpacing,
        globalTextAlign: globalTextAlign,
        allowSoftHyphens: allowSoftHyphens,
        columns: columns,
        columnSpacing: columnSpacing,
        pageHeight: pageHeight,
      );
      final chapterLayout = engine.layoutAll();
      final chapterPages = chapterLayout.pages;

      if (chapterPages.isNotEmpty) {
        // Если это не первая глава, то начинаем с новой страницы
        // => просто дополняем список страниц,
        // т.к. каждая layoutAll() сама начинает с pageIndex=0.
        allPages.addAll(chapterPages);
      }
    }

    return MultiColumnPagedLayout(allPages);
  }
}
