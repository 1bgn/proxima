// reader_screen.dart
import 'package:flutter/material.dart';
import 'custom_text_engine/inline_elements.dart';
import 'custom_text_engine/line_layout.dart';
import 'custom_text_engine/paragraph_block.dart';
import 'fb2_parser.dart';
import 'hyphenator.dart';
import 'large_book_paginator.dart';

class ReaderScreen extends StatefulWidget {
  final int initialPage; // с какой страницы начать
  const ReaderScreen({Key? key, this.initialPage = 0}) : super(key: key);

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  bool _loading = true;
  bool _layoutDone = false;

  late LargeBookPaginator paginator;
  int currentPage = 0;
  int totalPages = 1; // пока не знаем

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  Future<void> _initLoad() async {
    try {
      // 1) Парсим
      final parser = FB2Parser(Hyphenator());
      final chapters = await parser.parseFB2FromAssets('assets/book.fb2');

      // 2) Склеиваем все параграфы
      final allParagraphs = <ParagraphBlock>[];
      for (final ch in chapters) {
        allParagraphs.addAll(ch.paragraphs);
      }

      // 3) Создаём paginator
      paginator = LargeBookPaginator(
        paragraphs: allParagraphs,
        globalMaxWidth: 400, // заглушка, реально берём из LayoutBuilder
        lineSpacing: 4,
        globalTextAlign: CustomTextAlign.left,
        allowSoftHyphens: true,
        columns: 1,
        columnSpacing: 20,
        pageHeight: 600,
      );

      setState(() {
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Ошибка: $e\n$st');
      setState(() {
        _loading = false;
      });
    }
  }

  void _doLayout(double w, double h) {
    // Пересобираем layout под реальные размеры
    paginator.globalMaxWidth = w;
    paginator.pageHeight = h;
    paginator.layoutWholeBook();
    totalPages = paginator.pageCount;
    // init page
    currentPage = widget.initialPage;
    if (currentPage >= totalPages) {
      currentPage = totalPages - 1;
    }
    _layoutDone = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Чтение FB2'),
        actions: [
          IconButton(
            icon: Icon(Icons.skip_next),
            onPressed: () {
              if (!_layoutDone) return;
              setState(() {
                currentPage = (currentPage + 1).clamp(0, totalPages - 1);
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.skip_previous),
            onPressed: () {
              if (!_layoutDone) return;
              setState(() {
                currentPage = (currentPage - 1).clamp(0, totalPages - 1);
              });
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
        builder: (ctx, constraints) {
          final sw = constraints.maxWidth;
          final sh = constraints.maxHeight;

          if (!_layoutDone) {
            // Один раз делаем layout
            _doLayout(sw, sh);
          }

          // Получаем страницу
          final page = paginator.getPage(currentPage);

          return Column(
            children: [
              Expanded(
                child: SinglePageViewer(
                  page: page,
                  lineSpacing: paginator.lineSpacing,
                  textAlign: paginator.globalTextAlign,
                  allowSoftHyphens: paginator.allowSoftHyphens,
                ),
              ),
              Container(
                color: Colors.grey[200],
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Text('Страница ${currentPage + 1} / $totalPages'),
                    Spacer(),
                    SizedBox(
                      width: 60,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: '№',
                        ),
                        onSubmitted: (val) {
                          final p = int.tryParse(val) ?? 1;
                          setState(() {
                            currentPage = (p - 1).clamp(0, totalPages - 1);
                          });
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        // Пример: go to page from textfield
                      },
                      child: Text('Go'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Отрисовываем одну страницу (MultiColumnPage) используя AdvancedTextRenderObject
/// - Но он умеет рендерить только "первую страницу" из _layoutResult,
///   поэтому сделаем временный движок, или напрямую рисуем.
class SinglePageViewer extends LeafRenderObjectWidget {
  final MultiColumnPage page;
  final double lineSpacing;
  final CustomTextAlign textAlign;
  final bool allowSoftHyphens;

  const SinglePageViewer({
    Key? key,
    required this.page,
    required this.lineSpacing,
    required this.textAlign,
    required this.allowSoftHyphens,
  }) : super(key: key);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return SinglePageRenderObject(
      page: page,
      lineSpacing: lineSpacing,
      textAlign: textAlign,
      allowSoftHyphens: allowSoftHyphens,
    );
  }

  @override
  void updateRenderObject(BuildContext context, covariant SinglePageRenderObject renderObject) {
    renderObject
      ..page = page
      ..lineSpacing = lineSpacing
      ..textAlign = textAlign
      ..allowSoftHyphens = allowSoftHyphens;
  }
}

class SinglePageRenderObject extends RenderBox {
  MultiColumnPage _page;
  double _lineSpacing;
  CustomTextAlign _textAlign;
  bool _allowSoftHyphens;

  SinglePageRenderObject({
    required MultiColumnPage page,
    required double lineSpacing,
    required CustomTextAlign textAlign,
    required bool allowSoftHyphens,
  })  : _page = page,
        _lineSpacing = lineSpacing,
        _textAlign = textAlign,
        _allowSoftHyphens = allowSoftHyphens;

  set page(MultiColumnPage v) {
    if (_page != v) {
      _page = v;
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

  @override
  void performLayout() {
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final colWidth = _page.columnWidth;
    final colSpacing = _page.columnSpacing;

    for (int colIndex = 0; colIndex < _page.columns.length; colIndex++) {
      final colLines = _page.columns[colIndex];
      final colX = offset.dx + colIndex * (colWidth + colSpacing);
      double dy = offset.dy;

      for (int lineIndex = 0; lineIndex < colLines.length; lineIndex++) {
        final line = colLines[lineIndex];
        final lineTop = dy;
        double dx = colX;
        final extraSpace = colWidth - line.width;

        int gapCount = 0;
        if (_textAlign == CustomTextAlign.justify && line.elements.length > 1) {
          for (int e = 0; e < line.elements.length - 1; e++) {
            final e1 = line.elements[e];
            final e2 = line.elements[e + 1];
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
        if (lineIndex < colLines.length - 1) {
          dy += _lineSpacing;
        }
      }
    }
  }
}
