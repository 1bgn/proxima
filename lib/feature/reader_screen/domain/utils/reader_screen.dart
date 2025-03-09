// reader_screen.dart
import 'package:flutter/material.dart';

import 'asset_fb2_loader.dart';
import 'optimized_lazy_paginator.dart';
import 'custom_text_engine/inline_elements.dart';
import 'custom_text_engine/line_layout.dart';
import 'custom_text_engine/text_layout_engine.dart';
import 'custom_text_engine/paragraph_block.dart'; // подключаем нашу новую реализацию
import 'hyphenator.dart';

class ReaderScreen extends StatefulWidget {
  final int startPage;
  final BoxConstraints screenSize;

  const ReaderScreen({
    Key? key,
    this.startPage = 0,
    required this.screenSize,
  }) : super(key: key);

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late AssetFB2Loader loader;
  late OptimizedLazyPaginator paginator;
  bool inited = false;
  int currentPage = 0;
  final PageController pageController = PageController();
  final TextEditingController pageFieldController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    loader = AssetFB2Loader(
      assetPath: 'assets/book.fb2',
      hyphenator: Hyphenator(),
    );

    paginator = OptimizedLazyPaginator(
      loader: loader,
      chunkSize: 200,
      globalMaxWidth: 400,
      lineSpacing: 4,
      pageHeight: widget.screenSize.maxHeight - 86,
      columns: 1,
      columnSpacing: 20,
      allowSoftHyphens: true,
    );

    await loader.init();
    await paginator.init();

    setState(() {
      inited = true;
      currentPage = widget.startPage;
      pageFieldController.text = '$currentPage';
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pageController.hasClients) {
        pageController.jumpToPage(currentPage);
      }
    });
  }

  void _gotoPage(int page) {
    if (page < 0) page = 0;
    setState(() {
      currentPage = page;
      pageFieldController.text = '$page';
    });
    if (pageController.hasClients) {
      pageController.jumpToPage(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FB2 Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () => _gotoPage(currentPage - 1),
          ),
          SizedBox(
            width: 60,
            child: TextField(
              controller: pageFieldController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black, fontSize: 16),
              decoration: const InputDecoration(border: InputBorder.none),
              onSubmitted: (val) {
                final p = int.tryParse(val) ?? currentPage;
                _gotoPage(p);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _gotoPage(currentPage + 1),
          ),
        ],
      ),
      body: !inited
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
        builder: (ctx, constraints) {
          paginator.globalMaxWidth = constraints.maxWidth;
          paginator.pageHeight = constraints.maxHeight;
          return PageView.builder(
            controller: pageController,
            onPageChanged: (index) {
              setState(() {
                currentPage = index;
                pageFieldController.text = '$index';
              });
            },
            itemBuilder: (ctx, index) {
              return FutureBuilder(
                future: paginator.getPage(index),
                builder: (ctx, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final page = snapshot.data as MultiColumnPage;

                  return SinglePageView(
                    page: page,
                    lineSpacing: paginator.lineSpacing,
                    allowSoftHyphens: paginator.allowSoftHyphens,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Кастомный виджет для рендера одной "страницы".
class SinglePageView extends LeafRenderObjectWidget {
  final MultiColumnPage page;
  final double lineSpacing;
  final bool allowSoftHyphens;

  const SinglePageView({
    Key? key,
    required this.page,
    required this.lineSpacing,
    required this.allowSoftHyphens,
  }) : super(key: key);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return SinglePageRenderObj(
      page: page,
      lineSpacing: lineSpacing,
      allowSoftHyphens: allowSoftHyphens,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant SinglePageRenderObj renderObject) {
    renderObject
      ..page = page
      ..lineSpacing = lineSpacing
      ..allowSoftHyphens = allowSoftHyphens;
  }
}

// reader_screen.dart (обрезанный пример, главное - paint)
class SinglePageRenderObj extends RenderBox {
  MultiColumnPage _page;
  double _lineSpacing;
  bool _allowSoftHyphens;

  SinglePageRenderObj({
    required MultiColumnPage page,
    required double lineSpacing,
    required bool allowSoftHyphens,
  })  : _page = page,
        _lineSpacing = lineSpacing,
        _allowSoftHyphens = allowSoftHyphens;

  /// Сеттер для страницы
  set page(MultiColumnPage value) {
    if (_page != value) {
      _page = value;
      markNeedsLayout();
    }
  }

  /// Сеттер для межстрочного интервала
  set lineSpacing(double value) {
    if (_lineSpacing != value) {
      _lineSpacing = value;
      markNeedsLayout();
    }
  }

  /// Сеттер для флага "мягких" переносов
  set allowSoftHyphens(bool value) {
    if (_allowSoftHyphens != value) {
      _allowSoftHyphens = value;
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
    final spacing = _page.columnSpacing;

    for (int colIndex = 0; colIndex < _page.columns.length; colIndex++) {
      final colLines = _page.columns[colIndex];
      final colX = offset.dx + colIndex * (colWidth + spacing);
      double dy = offset.dy;

      for (int lineI = 0; lineI < colLines.length; lineI++) {
        final line = colLines[lineI]; // line is LineLayout
        final lineTop = dy;
        double dx = colX;

        final extraSpace = colWidth - line.width;
        int gapCount = 0;

        // Только если justify
        if (line.textAlign == CustomTextAlign.justify && line.elements.length > 1) {
          for (int e = 0; e < line.elements.length - 1; e++) {
            final e1 = line.elements[e];
            final e2 = line.elements[e + 1];
            if (e1 is TextInlineElement && e2 is TextInlineElement) {
              gapCount++;
            }
          }
        }

        final isRTL = (line.textDirection == CustomTextDirection.rtl);

        // Вычисляем стартовый dx в зависимости от выравнивания
        switch (line.textAlign) {
          case CustomTextAlign.left:
            dx = isRTL ? (colX + extraSpace) : colX;
            break;
          case CustomTextAlign.right:
            dx = isRTL ? colX : (colX + extraSpace);
            break;
          case CustomTextAlign.center:
            dx = colX + extraSpace / 2;
            break;
          case CustomTextAlign.justify:
            dx = colX;
            break;
        }

        for (int e = 0; e < line.elements.length; e++) {
          final elem = line.elements[e];
          final baselineShift = line.baseline - elem.baseline;
          final elemOffset = Offset(dx, lineTop + baselineShift);

          double gapExtra = 0;
          if (line.textAlign == CustomTextAlign.justify &&
              gapCount > 0 &&
              e < line.elements.length - 1) {
            final nextElem = line.elements[e + 1];
            if (elem is TextInlineElement && nextElem is TextInlineElement) {
              gapExtra = extraSpace / gapCount;
            }
          }

          elem.paint(canvas, elemOffset);

          // Если RTL — двигаем dx влево, если LTR — вправо
          dx += isRTL ? -(elem.width + gapExtra) : (elem.width + gapExtra);
        }

        dy += line.height;
        if (lineI < colLines.length - 1) {
          dy += _lineSpacing;
        }
      }
    }
  }
}

