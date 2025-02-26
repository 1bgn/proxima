// fb2_reader_widget.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/line_layout.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/paragraph_block.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/hyphenator.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/paginator.dart';
import 'dart:async';

import 'custom_text_engine/inline_elements.dart';
import 'fb2_parser.dart';


/// Экран (Widget) без AppBar, который загружает FB2 из assets,
/// парсит, верстает и отображает постранично.
class FB2ReaderScreen extends StatefulWidget {
  const FB2ReaderScreen({Key? key}) : super(key: key);

  @override
  State<FB2ReaderScreen> createState() => _FB2ReaderScreenState();
}

class _FB2ReaderScreenState extends State<FB2ReaderScreen> {
  Future<MultiColumnPagedLayout>? _layoutFuture;

  // Можно хранить отладочно ещё общее число страниц
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _layoutFuture = _buildPagedLayout();
  }

  /// Асинхронная сборка раскладки
  Future<MultiColumnPagedLayout> _buildPagedLayout() async {
    // 1) Создаем парсер
    final parser = FB2Parser(Hyphenator());
    // 2) Парсим главы
    final chapters = await parser.parseFB2FromAssets('assets/book.fb2');
    // 3) Настраиваем «пагинатор»
    final paginator = FB2Paginator(
      globalMaxWidth: 300, // заглушка, актуальные размеры возьмём из LayoutBuilder
      lineSpacing: 4.0,
      globalTextAlign: CustomTextAlign.left,
      allowSoftHyphens: true,
      columns: 1,
      columnSpacing: 20,
      pageHeight: 400,
    );
    // Собираем layout (но здесь ширина/высота стоит заглушкой)
    // NB: В реальности, нам нужно знать реальную ширину/высоту из LayoutBuilder,
    //     поэтому окончательный layout стоит строить уже в build().
    final multiLayout = paginator.layoutAllChapters(chapters);
    return multiLayout;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;

        return FutureBuilder<MultiColumnPagedLayout>(
          future: _layoutFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final multiLayout = snapshot.data!;
            final totalPages = multiLayout.pages.length;
            _pageCount = totalPages;

            if (totalPages == 0) {
              return const Center(child: Text("Нет страниц"));
            }

            // Строим PageView, где каждая страница -> виджет,
            // умеющий рендерить нужный pageIndex.
            return PageView.builder(
              itemCount: totalPages,
              itemBuilder: (context, index) {
                // Собираем все параграфы, но отрисовываем только нужную страницу
                // (ниже покажем кастомный AdvancedTextWidgetWithPageIndex)
                return AdvancedTextWidgetWithPageIndex(
                  multiLayout: multiLayout,
                  pageIndex: index,
                  width: maxWidth,
                  pageHeight: maxHeight,
                  lineSpacing: 4.0,
                  textAlign: CustomTextAlign.left,
                  allowSoftHyphens: true,
                  columns: 1,
                  columnSpacing: 20.0,
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Пример виджета, который умеет рендерить конкретную страницу (pageIndex)
/// из готового MultiColumnPagedLayout.
class AdvancedTextWidgetWithPageIndex extends LeafRenderObjectWidget {
  final MultiColumnPagedLayout multiLayout;
  final int pageIndex;

  final double width;
  final double pageHeight;
  final double lineSpacing;
  final CustomTextAlign textAlign;
  final bool allowSoftHyphens;
  final int columns;
  final double columnSpacing;

  const AdvancedTextWidgetWithPageIndex({
    Key? key,
    required this.multiLayout,
    required this.pageIndex,
    required this.width,
    required this.pageHeight,
    required this.lineSpacing,
    required this.textAlign,
    required this.allowSoftHyphens,
    required this.columns,
    required this.columnSpacing,
  }) : super(key: key);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return AdvancedTextWithPagesRenderObject(
      multiLayout: multiLayout,
      pageIndex: pageIndex,
      width: width,
      pageHeight: pageHeight,
      lineSpacing: lineSpacing,
      textAlign: textAlign,
      allowSoftHyphens: allowSoftHyphens,
      columns: columns,
      columnSpacing: columnSpacing,
    );
  }

  @override
  void updateRenderObject(BuildContext context, covariant AdvancedTextWithPagesRenderObject renderObject) {
    renderObject
      ..multiLayout = multiLayout
      ..pageIndex = pageIndex
      ..width = width
      ..pageHeight = pageHeight
      ..lineSpacing = lineSpacing
      ..textAlign = textAlign
      ..allowSoftHyphens = allowSoftHyphens
      ..columns = columns
      ..columnSpacing = columnSpacing;
  }
}

/// Специализированный RenderObject, который рендерит конкретную страницу (pageIndex).
class AdvancedTextWithPagesRenderObject extends RenderBox {
  MultiColumnPagedLayout _multiLayout;
  int _pageIndex;
  double _width;
  double _pageHeight;
  double _lineSpacing;
  CustomTextAlign _textAlign;
  bool _allowSoftHyphens;
  int _columns;
  double _columnSpacing;

  AdvancedTextWithPagesRenderObject({
    required MultiColumnPagedLayout multiLayout,
    required int pageIndex,
    required double width,
    required double pageHeight,
    required double lineSpacing,
    required CustomTextAlign textAlign,
    required bool allowSoftHyphens,
    required int columns,
    required double columnSpacing,
  })  : _multiLayout = multiLayout,
        _pageIndex = pageIndex,
        _width = width,
        _pageHeight = pageHeight,
        _lineSpacing = lineSpacing,
        _textAlign = textAlign,
        _allowSoftHyphens = allowSoftHyphens,
        _columns = columns,
        _columnSpacing = columnSpacing;

  set multiLayout(MultiColumnPagedLayout val) {
    if (_multiLayout != val) {
      _multiLayout = val;
      markNeedsLayout();
    }
  }

  set pageIndex(int val) {
    if (_pageIndex != val) {
      _pageIndex = val;
      markNeedsLayout();
    }
  }

  set width(double val) {
    if (_width != val) {
      _width = val;
      markNeedsLayout();
    }
  }

  set pageHeight(double val) {
    if (_pageHeight != val) {
      _pageHeight = val;
      markNeedsLayout();
    }
  }

  set lineSpacing(double val) {
    if (_lineSpacing != val) {
      _lineSpacing = val;
      markNeedsLayout();
    }
  }

  set textAlign(CustomTextAlign val) {
    if (_textAlign != val) {
      _textAlign = val;
      markNeedsLayout();
    }
  }

  set allowSoftHyphens(bool val) {
    if (_allowSoftHyphens != val) {
      _allowSoftHyphens = val;
      markNeedsLayout();
    }
  }

  set columns(int val) {
    if (_columns != val) {
      _columns = val;
      markNeedsLayout();
    }
  }

  set columnSpacing(double val) {
    if (_columnSpacing != val) {
      _columnSpacing = val;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    // Ширину ставим как минимум нужную, но не больше constraints.maxWidth
    final cWidth = constraints.maxWidth.isFinite
        ? math.min(_width, constraints.maxWidth)
        : _width;

    final cHeight = constraints.maxHeight.isFinite
        ? math.min(_pageHeight, constraints.maxHeight)
        : _pageHeight;

    size = Size(cWidth, cHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;

    if (_pageIndex < 0 || _pageIndex >= _multiLayout.pages.length) {
      // Нет такой страницы
      // Можно вывести «Пусто»
      final textPainter = TextPainter(
        text: const TextSpan(text: "Нет данных"),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, offset);
      return;
    }

    final page = _multiLayout.pages[_pageIndex];
    // См. как в AdvancedTextRenderObject: рисуем все колонки
    for (int colI = 0; colI < page.columns.length; colI++) {
      final colLines = page.columns[colI];
      final colX = offset.dx + colI * (page.columnWidth + page.columnSpacing);
      double dy = offset.dy;

      for (int lineI = 0; lineI < colLines.length; lineI++) {
        final line = colLines[lineI];
        final lineTop = dy;
        double dx = colX;
        final extraSpace = page.columnWidth - line.width;

        // Количество «пробелов» для justify
        int gapCount = 0;
        if (_textAlign == CustomTextAlign.justify && line.elements.length > 1) {
          for (int eIndex = 0; eIndex < line.elements.length - 1; eIndex++) {
            final e1 = line.elements[eIndex];
            final e2 = line.elements[eIndex + 1];
            if (e1 is TextInlineElement && e2 is TextInlineElement) {
              gapCount++;
            }
          }
        }

        // Определяем смещение dx по выравниванию
        switch (_textAlign) {
          case CustomTextAlign.left:
            dx = colX;
            break;
          case CustomTextAlign.right:
            dx = colX + extraSpace;
            break;
          case CustomTextAlign.center:
            dx = colX + extraSpace / 2;
            break;
          case CustomTextAlign.justify:
            dx = colX;
            break;
        }

        // Рисуем каждый InlineElement
        for (int eIndex = 0; eIndex < line.elements.length; eIndex++) {
          final elem = line.elements[eIndex];
          final baselineShift = line.baseline - elem.baseline;
          final elemOffset = Offset(dx, lineTop + baselineShift);

          double gapExtra = 0.0;
          if (_textAlign == CustomTextAlign.justify && gapCount > 0 && eIndex < line.elements.length - 1) {
            final nextElem = line.elements[eIndex + 1];
            if (elem is TextInlineElement && nextElem is TextInlineElement) {
              gapExtra = extraSpace / gapCount;
            }
          }

          // Рисуем сам элемент
          elem.paint(canvas, elemOffset);

          dx += elem.width + gapExtra;
        }

        dy += line.height;
        if (lineI < colLines.length - 1) {
          dy += _lineSpacing;
        }
      }
    }
  }
}
