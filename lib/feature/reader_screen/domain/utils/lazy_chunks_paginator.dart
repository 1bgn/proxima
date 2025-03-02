// lazy_chunks_paginator.dart
import 'custom_text_engine/line_layout.dart';
import 'custom_text_engine/paragraph_block.dart';
import 'custom_text_engine/text_layout_engine.dart';
import 'lru_cache.dart';
import 'asset_fb2_loader.dart';

import 'dart:math' as math;

class LazyChunksPaginator {
  final AssetFB2Loader loader;
  final int chunkSize;

  double globalMaxWidth;
  double lineSpacing;
  double pageHeight;
  int columns;
  double columnSpacing;
  bool allowSoftHyphens;

  final LruCache<int, List<ParagraphBlock>> _paragraphsCache;
  final LruCache<int, CustomTextLayout> _layoutCache;
  final LruCache<int, List<int>> _offsetsCache;

  bool _inited = false;
  int _totalParagraphs = 0;
  int _totalChunks = 0;

  LazyChunksPaginator({
    required this.loader,
    required this.chunkSize,
    required this.globalMaxWidth,
    required this.lineSpacing,
    required this.pageHeight,
    required this.columns,
    required this.columnSpacing,
    required this.allowSoftHyphens,
    int lruCapacity = 3,
  })  : _paragraphsCache = LruCache<int, List<ParagraphBlock>>(lruCapacity),
        _layoutCache = LruCache<int, CustomTextLayout>(lruCapacity),
        _offsetsCache = LruCache<int, List<int>>(lruCapacity);

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    await loader.init();
    _totalParagraphs = loader.countParagraphs();
    _totalChunks = (_totalParagraphs / chunkSize).ceil();
  }

  Future<int> computeTotalPages() async {
    await init();
    int sum = 0;
    for (int i = 0; i < _totalChunks; i++) {
      final pc = await _getChunkPageCount(i);
      sum += pc;
    }
    return sum;
  }

  Future<MultiColumnPage> getPage(int globalPageIndex) async {
    await init();
    int sumPages = 0;
    int chunkIndex = 0;
    int localIndex = 0;
    for (int c = 0; c < _totalChunks; c++) {
      final pc = await _getChunkPageCount(c);
      if (sumPages + pc > globalPageIndex) {
        chunkIndex = c;
        localIndex = globalPageIndex - sumPages;
        break;
      }
      sumPages += pc;
    }
    final offsets = await _ensureOffsets(chunkIndex);
    final layout = _layoutCache.get(chunkIndex)!;
    if (localIndex < 0 || localIndex >= offsets.length) {
      return MultiColumnPage(
        columns: [],
        pageWidth: globalMaxWidth,
        pageHeight: pageHeight,
        columnWidth: 1,
        columnSpacing: columnSpacing,
      );
    }
    final start = offsets[localIndex];
    final end = (localIndex == offsets.length - 1)
        ? layout.lines.length
        : offsets[localIndex + 1];
    final needed = layout.lines.sublist(start, end);
    return _buildPage(needed);
  }

  Future<int> _getChunkPageCount(int cIndex) async {
    final offs = await _ensureOffsets(cIndex);
    return offs.length;
  }

  /// Изменённый метод _ensureOffsets принимает также paragraphIndexOfLine.
  Future<List<int>> _ensureOffsets(int cIndex) async {
    List<ParagraphBlock>? paras = _paragraphsCache.get(cIndex);
    if (paras == null) {
      paras = await loader.loadChunk(cIndex, chunkSize);
      _paragraphsCache.put(cIndex, paras);
    }
    CustomTextLayout? layout = _layoutCache.get(cIndex);
    if (layout == null) {
      final engine = AdvancedLayoutEngine(
        paragraphs: paras,
        globalMaxWidth: globalMaxWidth,
        lineSpacing: lineSpacing,
        globalTextAlign: CustomTextAlign.left,
        allowSoftHyphens: allowSoftHyphens,
        columns: 1,
        columnSpacing: 0,
        pageHeight: pageHeight,
      );
      layout = engine.layoutParagraphsOnly();
      _layoutCache.put(cIndex, layout);
    }
    List<int>? offs = _offsetsCache.get(cIndex);
    if (offs == null) {
      // Используем обновлённую версию _buildOffsets, которая учитывает startNewPage
      offs = _buildOffsets(layout.lines, layout.paragraphIndexOfLine, paras);
      _offsetsCache.put(cIndex, offs);
    }
    return offs;
  }

  /// Метод построения оффсетов с учетом свойства startNewPage в ParagraphBlock.
  /// Метод построения оффсетов с учетом свойства isSectionEnd в ParagraphBlock.
  List<int> _buildOffsets(List<LineLayout> lines, List<int> paragraphIndexOfLine, List<ParagraphBlock> paras) {
    final result = <int>[];
    if (lines.isEmpty) {
      result.add(0);
      return result;
    }
    int curLine = 0;
    double used = 0;
    result.add(0);
    for (int i = 0; i < lines.length; i++) {
      // Если текущая строка принадлежит параграфу, помеченному как конец секции,
      // форсируем разрыв страницы.
      final paraIndex = paragraphIndexOfLine[i];
      if (paras[paraIndex].isSectionEnd) { // изменено: вместо startNewPage используем isSectionEnd
        if (i != 0) {
          curLine = i;
          result.add(curLine);
          used = lines[i].height; // для маркера обычно равен 0
          continue;
        }
      }
      final lh = lines[i].height;
      if (i == curLine) {
        used = lh;
      } else {
        final need = used + lineSpacing + lh;
        if (need <= pageHeight) {
          used = need;
        } else {
          curLine = i;
          result.add(curLine);
          used = lh;
        }
      }
    }
    return result;
  }


  MultiColumnPage _buildPage(List<LineLayout> lines) {
    final cols = <List<LineLayout>>[];
    final totalSpacing = columnSpacing * (columns - 1);
    final colWidth = (globalMaxWidth - totalSpacing) / columns;
    int idx = 0;
    while (idx < lines.length) {
      if (cols.length == columns) break;
      final colLines = <LineLayout>[];
      double usedH = 0;
      while (idx < lines.length) {
        final line = lines[idx];
        final lh = line.height;
        if (colLines.isEmpty) {
          colLines.add(line);
          usedH = lh;
          idx++;
        } else {
          final need = usedH + lineSpacing + lh;
          if (need <= pageHeight) {
            colLines.add(line);
            usedH = need;
            idx++;
          } else {
            break;
          }
        }
      }
      cols.add(colLines);
    }
    return MultiColumnPage(
      columns: cols,
      pageWidth: globalMaxWidth,
      pageHeight: pageHeight,
      columnWidth: colWidth,
      columnSpacing: columnSpacing,
    );
  }
}
