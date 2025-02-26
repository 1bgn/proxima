import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/inline_elements.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/line_layout.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/paragraph_block.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class AdvancedReaderWidget extends LeafRenderObjectWidget {
  final MultiColumnPagedLayout multiPaged;
  final int pageIndex; // какую страницу показать
  final double lineSpacing;
  final CustomTextAlign textAlign;
  final bool allowSoftHyphens;
  final int columns;
  final double columnSpacing;
  final double pageHeight;

  const AdvancedReaderWidget({
    Key? key,
    required this.multiPaged,
    this.pageIndex = 0,
    this.lineSpacing = 4.0,
    this.textAlign = CustomTextAlign.left,
    this.allowSoftHyphens = true,
    this.columns = 1,
    this.columnSpacing = 20.0,
    required this.pageHeight,
  }) : super(key: key);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return AdvancedReaderRenderObject(
      multiPaged: multiPaged,
      pageIndex: pageIndex,
      lineSpacing: lineSpacing,
      textAlign: textAlign,
      allowSoftHyphens: allowSoftHyphens,
      columns: columns,
      columnSpacing: columnSpacing,
      pageHeight: pageHeight,
    );
  }

  @override
  void updateRenderObject(BuildContext context, AdvancedReaderRenderObject renderObject) {
    renderObject
      ..multiPaged = multiPaged
      ..pageIndex = pageIndex
      ..lineSpacing = lineSpacing
      ..textAlign = textAlign
      ..allowSoftHyphens = allowSoftHyphens
      ..columns = columns
      ..columnSpacing = columnSpacing
      ..pageHeight = pageHeight;
  }
}

class AdvancedReaderRenderObject extends RenderBox {
  MultiColumnPagedLayout _multiPaged;
  int _pageIndex;
  double _lineSpacing;
  CustomTextAlign _textAlign;
  bool _allowSoftHyphens;
  int _columns;
  double _columnSpacing;
  double _pageHeight;

  AdvancedReaderRenderObject({
    required MultiColumnPagedLayout multiPaged,
    required int pageIndex,
    required double lineSpacing,
    required CustomTextAlign textAlign,
    required bool allowSoftHyphens,
    required int columns,
    required double columnSpacing,
    required double pageHeight,
  })  : _multiPaged = multiPaged,
        _pageIndex = pageIndex,
        _lineSpacing = lineSpacing,
        _textAlign = textAlign,
        _allowSoftHyphens = allowSoftHyphens,
        _columns = columns,
        _columnSpacing = columnSpacing,
        _pageHeight = pageHeight;

  set multiPaged(MultiColumnPagedLayout value) {
    if (_multiPaged != value) {
      _multiPaged = value;
      markNeedsLayout();
    }
  }

  set pageIndex(int value) {
    if (_pageIndex != value) {
      _pageIndex = value;
      markNeedsPaint();
    }
  }

  set lineSpacing(double value) {
    if (_lineSpacing != value) {
      _lineSpacing = value;
      markNeedsLayout();
    }
  }

  set textAlign(CustomTextAlign value) {
    if (_textAlign != value) {
      _textAlign = value;
      markNeedsLayout();
    }
  }

  set allowSoftHyphens(bool value) {
    if (_allowSoftHyphens != value) {
      _allowSoftHyphens = value;
      markNeedsLayout();
    }
  }

  set columns(int value) {
    if (_columns != value) {
      _columns = value;
      markNeedsLayout();
    }
  }

  set columnSpacing(double value) {
    if (_columnSpacing != value) {
      _columnSpacing = value;
      markNeedsLayout();
    }
  }

  set pageHeight(double value) {
    if (_pageHeight != value) {
      _pageHeight = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    // Ширину берём по constraints.
    final cWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : 300.0;

    final cHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : _pageHeight;

    size = Size(cWidth, cHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;

    if (_pageIndex >= _multiPaged.pages.length) {
      return;
    }

    final page = _multiPaged.pages[_pageIndex];
    // Рисуем колонки
    for (int colI = 0; colI < page.columns.length; colI++) {
      final colLines = page.columns[colI];
      final colX = offset.dx + colI * (page.columnWidth + page.columnSpacing);
      double dy = offset.dy;

      for (int lineI = 0; lineI < colLines.length; lineI++) {
        final line = colLines[lineI];
        final lineTop = dy;
        double dx = colX;
        final extraSpace = page.columnWidth - line.width;

        // Для justify
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

        // Смещение dx по align
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
