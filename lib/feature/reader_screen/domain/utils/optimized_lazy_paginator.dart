import 'asset_fb2_loader.dart';
import 'custom_text_engine/line_layout.dart';
import 'custom_text_engine/paragraph_block.dart';
import 'custom_text_engine/text_layout_engine.dart';

class OptimizedLazyPaginator {
  final AssetFB2Loader loader;
  final int chunkSize;
  CustomTextLayout? get fullLayout => _fullLayout;

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

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // Загружаем все абзацы
    _allParagraphs = await loader.loadAllParagraphs();
    // Первоначальный layout
    await _buildLayout();
  }

  /// Метод, который пересчитывает layout (например, при изменении размеров).
  Future<void> relayout() async {
    // Если ещё не загружены абзацы, выходим
    if (_allParagraphs == null) return;
    await _buildLayout();
  }

  Future<void> _buildLayout() async {
    final engine = AdvancedLayoutEngine(
      paragraphs: _allParagraphs!,
      globalMaxWidth: globalMaxWidth,
      lineSpacing: lineSpacing,
      globalTextAlign: CustomTextAlign.left, // упрощённо
      allowSoftHyphens: allowSoftHyphens,
      columns: columns,
      columnSpacing: columnSpacing,
      pageHeight: pageHeight,
    );
    // Разбиваем на строки (без формирования мультистраничной структуры)
    _fullLayout = engine.layoutParagraphsOnly();
    // Рассчитываем страницы на основе строк
    _pageOffsets = _buildPageOffsets(_fullLayout!.lines, _fullLayout!.paragraphIndexOfLine, _allParagraphs!);
    _totalPages = _pageOffsets!.length;
  }

  int get totalPages => _totalPages;

  Future<MultiColumnPage> getPage(int pageIndex) async {
    // Если ещё не были загружены данные
    if (!_inited || _fullLayout == null || _pageOffsets == null) {
      return MultiColumnPage(
        columns: [],
        pageWidth: globalMaxWidth,
        pageHeight: pageHeight,
        columnWidth: 10,
        columnSpacing: columnSpacing,
      );
    }

    if (pageIndex < 0 || pageIndex >= _totalPages) {
      return MultiColumnPage(
        columns: [],
        pageWidth: globalMaxWidth,
        pageHeight: pageHeight,
        columnWidth: 10,
        columnSpacing: columnSpacing,
      );
    }

    final start = _pageOffsets![pageIndex];
    final end = (pageIndex == _totalPages - 1)
        ? _fullLayout!.lines.length
        : _pageOffsets![pageIndex + 1];
    final linesForPage = _fullLayout!.lines.sublist(start, end);

    return _buildMultiColumnPage(linesForPage);
  }

  List<int> _buildPageOffsets(
      List<LineLayout> lines, List<int> pIndex, List<ParagraphBlock> paras) {
    final result = <int>[];
    if (lines.isEmpty) {
      result.add(0);
      return result;
    }
    int curLine = 0;
    double used = 0.0;
    result.add(0);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lh = line.height;
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
      // проверка на конец секции
      final paraIdx = pIndex[i];
      if (paraIdx >= 0 && paraIdx < paras.length) {
        if (paras[paraIdx].isSectionEnd && line.width == 0 && line.height == 0) {
          if (i != 0) {
            curLine = i;
            result.add(curLine);
            used = 0;
          }
        }
      }
    }
    return result;
  }

  MultiColumnPage _buildMultiColumnPage(List<LineLayout> lines) {
    final totalSpacing = columnSpacing * (columns - 1);
    final colWidth = (globalMaxWidth - totalSpacing) / columns;

    var colHeights = List<double>.filled(columns, 0);
    var cols = List.generate(columns, (_) => <LineLayout>[]);

    int col = 0;
    for (final line in lines) {
      final needed = (cols[col].isEmpty)
          ? line.height
          : colHeights[col] + lineSpacing + line.height;
      if (needed <= pageHeight) {
        if (cols[col].isNotEmpty) {
          colHeights[col] += lineSpacing;
        }
        cols[col].add(line);
        colHeights[col] += line.height;
      } else {
        col++;
        if (col >= columns) {
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
