// lazy_chunks_paginator.dart
import 'asset_fb2_loader.dart';
import 'custom_text_engine/line_layout.dart';
import 'custom_text_engine/paragraph_block.dart';

import 'dart:math' as math;

import 'custom_text_engine/text_layout_engine.dart';

/// Оптимизированный ленивый пагинатор, который:
/// 1) Загружает весь документ (loadAllParagraphs) для формирования
///    глобальной раскладки строк (CustomTextLayout), без зависимости от chunkSize.
/// 2) На основе строк формирует массив offsets (начало каждой страницы).
/// 3) При запросе getPage(...) быстро выдаёт нужную страницу, уже не завися от chunkSize.
class OptimizedLazyPaginator {
  final AssetFB2Loader loader;
  final int chunkSize; // используется только для UI, а не для вычисления разрывов страниц

  double globalMaxWidth;
  double lineSpacing;
  double pageHeight;
  int columns;
  double columnSpacing;
  bool allowSoftHyphens;

  bool _inited = false;
  List<ParagraphBlock>? _allParagraphs;
  CustomTextLayout? _fullLayout;
  List<int>? _pageOffsets;
  int _totalPages = 0;

  OptimizedLazyPaginator({
    required this.loader,
    required this.chunkSize,
    required this.globalMaxWidth,
    required this.lineSpacing,
    required this.pageHeight,
    required this.columns,
    required this.columnSpacing,
    required this.allowSoftHyphens,
  });

  /// Инициализация: грузим полный документ, строим одноколоночный layout,
  /// рассчитываем offsets страниц. chunkSize не используется для расчёта разрывов.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // Загружаем все абзацы (весь документ)
    _allParagraphs = await loader.loadAllParagraphs();

    // Строим одноколоночный layout
    final engine = AdvancedLayoutEngine(
      paragraphs: _allParagraphs!,
      globalMaxWidth: globalMaxWidth,
      lineSpacing: lineSpacing,
      globalTextAlign: CustomTextAlign.left, // упрощённо
      allowSoftHyphens: allowSoftHyphens,
      columns: 1,
      columnSpacing: 0,
      pageHeight: pageHeight,
    );
    _fullLayout = engine.layoutParagraphsOnly();

    // Рассчитываем глобальные offsets
    _pageOffsets = _buildPageOffsets(_fullLayout!.lines, _fullLayout!.paragraphIndexOfLine, _allParagraphs!);
    _totalPages = _pageOffsets!.length;
  }

  int get totalPages => _totalPages;

  /// Возвращает страницу (MultiColumnPage) с columns>1, используя нужный фрагмент строк.
  Future<MultiColumnPage> getPage(int pageIndex) async {
    await init();
    if (pageIndex<0 || pageIndex>= _totalPages) {
      // пустая страница
      return MultiColumnPage(
        columns: [],
        pageWidth: globalMaxWidth,
        pageHeight: pageHeight,
        columnWidth: 10,
        columnSpacing: columnSpacing,
      );
    }
    final start = _pageOffsets![pageIndex];
    final end = (pageIndex == _totalPages-1)
        ? _fullLayout!.lines.length
        : _pageOffsets![pageIndex+1];
    final linesForPage = _fullLayout!.lines.sublist(start, end);

    return _buildMultiColumnPage(linesForPage);
  }

  /// Реальная логика формирования offsets.
  /// Пробегаем строки, учитываем height + lineSpacing, если превышает pageHeight – новая страница.
  /// Также если строка принадлежит абзацу isSectionEnd и сама строка пустая (width=0, height=0),
  /// форсируем разрыв.
  List<int> _buildPageOffsets(List<LineLayout> lines, List<int> pIndex, List<ParagraphBlock> paras) {
    final result = <int>[];
    if (lines.isEmpty) {
      result.add(0);
      return result;
    }
    int curLine = 0;
    double used = 0.0;
    result.add(0); // первая страница – с 0

    for (int i=0; i<lines.length; i++) {
      final line = lines[i];
      final lh = line.height;
      if (i==curLine) {
        used = lh;
      } else {
        final need = used + lineSpacing + lh;
        if (need <= pageHeight) {
          used = need;
        } else {
          // Перенос на новую страницу
          curLine = i;
          result.add(curLine);
          used = lh;
        }
      }
      // Проверяем конец секции
      final paraIdx = pIndex[i];
      if (paraIdx>=0 && paraIdx<paras.length) {
        if (paras[paraIdx].isSectionEnd && line.width==0 && line.height==0) {
          // форсированный разрыв
          if (i!=0) {
            curLine = i;
            result.add(curLine);
            used = 0;
          }
        }
      }
    }
    return result;
  }

  /// Строим одну страницу (MultiColumnPage) из переданного списка строк (linesForPage).
  MultiColumnPage _buildMultiColumnPage(List<LineLayout> lines) {
    final totalSpacing = columnSpacing*(columns-1);
    final colWidth = (globalMaxWidth - totalSpacing)/ columns;

    var colHeights = List<double>.filled(columns, 0);
    var cols = List.generate(columns, (_) => <LineLayout>[]);

    int col=0;
    for (final line in lines) {
      final needed = (cols[col].isEmpty)
          ? line.height
          : colHeights[col] + lineSpacing + line.height;
      if (needed<= pageHeight) {
        if (cols[col].isNotEmpty) colHeights[col]+= lineSpacing;
        cols[col].add(line);
        colHeights[col]+= line.height;
      } else {
        col++;
        if (col>= columns) {
          // Страница заполнена (для одной MultiColumnPage).
          // Если нужно отрисовать *только* одну страницу – на этом остановимся.
          // Но если ваш рендер выводит только 1 страницу = 1 MultiColumnPage,
          // то оставшиеся строки останутся "за бортом".
          break;
        }
        cols[col].add(line);
        colHeights[col] = line.height;
      }
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
