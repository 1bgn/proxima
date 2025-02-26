// advanced_text_widget_page.dart

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'paragraph_block.dart';
import 'inline_elements.dart';
import 'line_layout.dart';
import 'text_layout_engine.dart';

/// Виджет, аналогичный AdvancedTextWidget, но с поддержкой pageIndex:
///   - Он не строит заново весь layout
///   - Вместо этого сам создаёт AdvancedLayoutEngine,
///     сохраняет результат и рендерит нужную страницу.
class AdvancedTextWidgetWithPageIndex extends LeafRenderObjectWidget {
  final List<ParagraphBlock> paragraphs;
  final double width;
  final double lineSpacing;
  final CustomTextAlign textAlign;
  final bool allowSoftHyphens;
  final int columns;
  final double columnSpacing;
  final double pageHeight;
  final int pageIndex;

  const AdvancedTextWidgetWithPageIndex({
    Key? key,
    required this.paragraphs,
    required this.width,
    required this.pageHeight,
    this.lineSpacing = 4.0,
    this.textAlign = CustomTextAlign.left,
    this.allowSoftHyphens = true,
    this.columns = 1,
    this.columnSpacing = 20.0,
    this.pageIndex = 0,
  }) : super(key: key);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return AdvancedTextPageRenderObject(
      paragraphs: paragraphs,
      width: width,
      lineSpacing: lineSpacing,
      textAlign: textAlign,
      allowSoftHyphens: allowSoftHyphens,
      columns: columns,
      columnSpacing: columnSpacing,
      pageHeight: pageHeight,
      pageIndex: pageIndex,
    );
  }

  @override
  void updateRenderObject(BuildContext context, covariant AdvancedTextPageRenderObject renderObject) {
    renderObject
      ..paragraphs = paragraphs
      ..width = width
      ..lineSpacing = lineSpacing
      ..textAlign = textAlign
      ..allowSoftHyphens = allowSoftHyphens
      ..columns = columns
      ..columnSpacing = columnSpacing
      ..pageHeight = pageHeight
      ..pageIndex = pageIndex;
  }
}

class AdvancedTextPageRenderObject extends RenderBox {
  List<ParagraphBlock> _paragraphs;
  double _width;
  double _lineSpacing;
  CustomTextAlign _textAlign;
  bool _allowSoftHyphens;
  int _columns;
  double _columnSpacing;
  double _pageHeight;
  int _pageIndex;

  MultiColumnPagedLayout? _layout;

  AdvancedTextPageRenderObject({
    required List<ParagraphBlock> paragraphs,
    required double width,
    required double lineSpacing,
    required CustomTextAlign textAlign,
    required bool allowSoftHyphens,
    required int columns,
    required double columnSpacing,
    required double pageHeight,
    required int pageIndex,
  })  : _paragraphs = paragraphs,
        _width = width,
        _lineSpacing = lineSpacing,
        _textAlign = textAlign,
        _allowSoftHyphens = allowSoftHyphens,
        _columns = columns,
        _columnSpacing = columnSpacing,
        _pageHeight = pageHeight,
        _pageIndex = pageIndex;

  set paragraphs(List<ParagraphBlock> v) {
    if (_paragraphs != v) {
      _paragraphs = v;
      markNeedsLayout();
    }
  }

  set width(double v) {
    if (_width != v) {
      _width = v;
      markNeedsLayout();
    }
  }

  set lineSpacing(double v) {
    if (_lineSpacing != v) {
      _lineSpacing = v;
      markNeedsLayout();
    }
  }

  set textAlign(CustomTextAlign v) {
    if (_textAlign != v) {
      _textAlign = v;
      markNeedsLayout();
    }
  }

  set allowSoftHyphens(bool v) {
    if (_allowSoftHyphens != v) {
      _allowSoftHyphens = v;
      markNeedsLayout();
    }
  }

  set columns(int v) {
    if (_columns != v) {
      _columns = v;
      markNeedsLayout();
    }
  }

  set columnSpacing(double v) {
    if (_columnSpacing != v) {
      _columnSpacing = v;
      markNeedsLayout();
    }
  }

  set pageHeight(double v) {
    if (_pageHeight != v) {
      _pageHeight = v;
      markNeedsLayout();
    }
  }

  set pageIndex(int v) {
    if (_pageIndex != v) {
      _pageIndex = v;
      markNeedsPaint();
    }
  }

  @override
  void performLayout() {
    final cWidth = constraints.maxWidth.isFinite
        ? math.min(_width, constraints.maxWidth)
        : _width;
    final cHeight = constraints.maxHeight.isFinite
        ? math.min(_pageHeight, constraints.maxHeight)
        : _pageHeight;

    final engine = AdvancedLayoutEngine(
      paragraphs: _paragraphs,
      globalMaxWidth: cWidth,
      lineSpacing: _lineSpacing,
      globalTextAlign: _textAlign,
      allowSoftHyphens: _allowSoftHyphens,
      columns: _columns,
      columnSpacing: _columnSpacing,
      pageHeight: _pageHeight,
    );
    _layout = engine.layoutAll();

    size = Size(cWidth, cHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_layout == null) return;
    if (_pageIndex < 0 || _pageIndex >= _layout!.pages.length) return;

    final canvas = context.canvas;
    final page = _layout!.pages[_pageIndex];

    for (int colI = 0; colI < page.columns.length; colI++) {
      final colLines = page.columns[colI];
      final colX = offset.dx + colI * (page.columnWidth + page.columnSpacing);
      double dy = offset.dy;

      for (int lineI = 0; lineI < colLines.length; lineI++) {
        final line = colLines[lineI];
        final lineTop = dy;
        double dx = colX;
        final extraSpace = page.columnWidth - line.width;

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
