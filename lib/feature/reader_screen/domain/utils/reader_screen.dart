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
  OptimizedLazyPaginator? paginator; // делаем paginator опциональным
  bool inited = false;
  int currentPage = 0;
  final PageController pageController = PageController();
  final TextEditingController pageFieldController = TextEditingController();

  // Для отслеживания предыдущих ограничений
  BoxConstraints? lastConstraints;

  @override
  void initState() {
    super.initState();
    _initLoader();
  }

  Future<void> _initLoader() async {
    loader = AssetFB2Loader(
      assetPath: 'assets/book2.fb2',
      hyphenator: Hyphenator(),
    );
    await loader.init();
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

  // Метод обновляет (создаёт новый) paginator при изменении ограничений
  Future<void> _updatePaginator(BoxConstraints constraints) async {
    if (lastConstraints == null ||
        lastConstraints!.maxWidth != constraints.maxWidth ||
        lastConstraints!.maxHeight != constraints.maxHeight) {
      lastConstraints = constraints;
      final newPaginator = OptimizedLazyPaginator(
        loader: loader,
        chunkSize: 200,
        globalMaxWidth: constraints.maxWidth,
        lineSpacing: 4,
        pageHeight: constraints.maxHeight,
        columns: 1,
        columnSpacing: 20,
        allowSoftHyphens: true,
      );
      await newPaginator.init();
      setState(() {
        paginator = newPaginator;
      });
    }
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
    if (!inited) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
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
      body: Container(
        padding: EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _updatePaginator(constraints);
            if (paginator == null) {
              return const Center(child: CircularProgressIndicator());
            }
            // Оборачиваем PageView.builder в Padding
            return PageView.builder(
              controller: pageController,
              onPageChanged: (index) {
                setState(() {
                  currentPage = index;
                  pageFieldController.text = '$index';
                });
              },
              itemBuilder: (context, index) {
                return FutureBuilder(
                  future: paginator!.getPage(index),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final page = snapshot.data as MultiColumnPage;
                    return SinglePageView(
                      page: page,
                      lineSpacing: paginator!.lineSpacing,
                      allowSoftHyphens: paginator!.allowSoftHyphens,
                    );
                  },
                );
              },
            );
          },
        ),
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
      // базовая координата колонки
      final colX = offset.dx + colIndex * (colWidth + spacing);
      double dy = offset.dy;

      for (int lineI = 0; lineI < colLines.length; lineI++) {
        final line = colLines[lineI];
        final lineTop = dy;
        double dx;

        // Если для этого блока задан containerAlignment (то есть, его абзац имел maxWidth),
        // вычисляем effectiveWidth и containerLeft.
        if (line.containerOffset != 0) {
          // Предполагается, что если containerOffset != 0,
          // то в ParagraphBlock был задан maxWidth, и effectiveWidth = globalMaxWidth * maxWidth.
          // Здесь globalMaxWidth (или colWidth) – полная ширина, а effectiveWidth – ширина контейнера.
          final effectiveWidth = colWidth * line.containerOffsetFactor;
          // Для right: контейнерный левый край = colX + (colWidth - effectiveWidth)
          final containerLeft = colX + (colWidth - effectiveWidth);
          switch (line.textAlign) {
            case CustomTextAlign.left:
              dx = containerLeft;
              break;
            case CustomTextAlign.right:
              dx = containerLeft + (effectiveWidth - line.width);
              break;
            case CustomTextAlign.center:
              dx = containerLeft + (effectiveWidth - line.width) / 2;
              break;
            case CustomTextAlign.justify:
              dx = containerLeft;
              break;
          }
        } else {
          // Если нет containerAlignment (то есть блок занимает всю ширину),
          // рассчитываем dx по обычной схеме:
          final extraSpace = colWidth - line.width;
          final isRTL = (line.textDirection == CustomTextDirection.rtl);
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
        }

        // Отрисовка inline-элементов строки с учетом justify
        int gapCount = 0;
        if (line.textAlign == CustomTextAlign.justify && line.elements.length > 1) {
          for (int i = 0; i < line.elements.length - 1; i++) {
            final e1 = line.elements[i];
            final e2 = line.elements[i + 1];
            if (e1 is TextInlineElement && e2 is TextInlineElement) {
              gapCount++;
            }
          }
        }

        for (int eIndex = 0; eIndex < line.elements.length; eIndex++) {
          final elem = line.elements[eIndex];
          final baselineShift = line.baseline - elem.baseline;
          final elemOffset = Offset(dx, lineTop + baselineShift);

          double gapExtra = 0.0;
          if (line.textAlign == CustomTextAlign.justify &&
              gapCount > 0 &&
              eIndex < line.elements.length - 1) {
            final nextElem = line.elements[eIndex + 1];
            if (elem is TextInlineElement && nextElem is TextInlineElement) {
              gapExtra = (colWidth - line.width) / gapCount;
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

