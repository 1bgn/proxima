// fb2_reader_screen.dart
import 'package:flutter/material.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/paginator.dart';
import 'dart:math' as math;

// Важно: проверьте правильный путь к этим файлам
import 'custom_text_engine/inline_elements.dart';
import 'custom_text_engine/line_layout.dart';
import 'custom_text_engine/paragraph_block.dart';
import 'custom_text_engine/text_layout_engine.dart';

import 'fb2_parser.dart';
import 'hyphenator.dart';

// Примерный вариант экрана чтения
class FB2ReaderScreen extends StatefulWidget {
  const FB2ReaderScreen({Key? key}) : super(key: key);

  @override
  State<FB2ReaderScreen> createState() => _FB2ReaderScreenState();
}

class _FB2ReaderScreenState extends State<FB2ReaderScreen> {
  List<ChapterData>? _chapters;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initParsing();
  }

  Future<void> _initParsing() async {
    try {
      // Создаем парсер, сразу в нём создаём Hyphenator
      final parser = FB2Parser(Hyphenator());
      final chapters = await parser.parseFB2FromAssets('assets/book.fb2');
      setState(() {
        _chapters = chapters;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Ошибка при парсинге: $e\n$st');
      setState(() {
        _chapters = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // без appBar, если не нужно
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_chapters == null || _chapters!.isEmpty)
          ? const Center(child: Text('Нет глав'))
          : LayoutBuilder(
        builder: (ctx, constraints) {
          final screenWidth = constraints.maxWidth;
          final screenHeight = constraints.maxHeight;

          // Выполняем пагинацию
          final paginator = FB2Paginator(
            globalMaxWidth: screenWidth,
            lineSpacing: 4.0,
            globalTextAlign: CustomTextAlign.left,
            allowSoftHyphens: true,
            columns: 1,
            columnSpacing: 20.0,
            pageHeight: screenHeight,
          );
          final multiLayout = paginator.layoutAllChapters(_chapters!);

          if (multiLayout.pages.isEmpty) {
            return const Center(child: Text('Пусто'));
          }

          // Показываем постранично
          return PageView.builder(
            itemCount: multiLayout.pages.length,
            itemBuilder: (context, pageIndex) {
              return _SinglePageView(
                multiLayout: multiLayout,
                pageIndex: pageIndex,
                width: screenWidth,
                pageHeight: screenHeight,
                lineSpacing: 4.0,
                textAlign: CustomTextAlign.left,
                allowSoftHyphens: true,
                columns: 1,
                columnSpacing: 20.0,
              );
            },
          );
        },
      ),
    );
  }
}

/// Простейший виджет, отрисовывающий одну страницу (pageIndex)
class _SinglePageView extends LeafRenderObjectWidget {
  final MultiColumnPagedLayout multiLayout;
  final int pageIndex;

  final double width;
  final double pageHeight;
  final double lineSpacing;
  final CustomTextAlign textAlign;
  final bool allowSoftHyphens;
  final int columns;
  final double columnSpacing;

  const _SinglePageView({
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
    return _SinglePageRenderObject(
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
  void updateRenderObject(BuildContext context, covariant _SinglePageRenderObject renderObject) {
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

class _SinglePageRenderObject extends RenderBox {
  MultiColumnPagedLayout _multiLayout;
  int _pageIndex;
  double _width;
  double _pageHeight;
  double _lineSpacing;
  CustomTextAlign _textAlign;
  bool _allowSoftHyphens;
  int _columns;
  double _columnSpacing;

  _SinglePageRenderObject({
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
      final tp = TextPainter(
        text: const TextSpan(text: 'Нет такой страницы'),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, offset);
      return;
    }

    final page = _multiLayout.pages[_pageIndex];

    for (int colI = 0; colI < page.columns.length; colI++) {
      final colLines = page.columns[colI];
      final colX = offset.dx + colI * (page.columnWidth + page.columnSpacing);
      double dy = offset.dy;

      for (int lineI = 0; lineI < colLines.length; lineI++) {
        final line = colLines[lineI];
        final lineTop = dy;
        double dx = colX;
        final extraSpace = page.columnWidth - line.width;

        // Считаем количество «пробелов» для justify
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

        // Определяем dx по выравниванию
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

        // Рисуем элементы строки
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

          // Отрисовка элемента
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
