/// line_layout.dart
///
/// Описание структуры строки (LineLayout), результата раскладки (CustomTextLayout),
/// а также многостраничной модели.

import 'inline_elements.dart';

/// Описание одной строки, состоящей из нескольких [InlineElement].
class LineLayout {
  /// Список элементов в строке.
   List<InlineElement> elements = [];

  /// Итоговая ширина строки.
  double width = 0.0;

  /// Итоговая высота строки = maxAscent + maxDescent.
  double height = 0.0;

  /// Макс. ascent среди элементов.
  double maxAscent = 0.0;

  /// Макс. descent среди элементов.
  double maxDescent = 0.0;

  /// Baseline = [maxAscent].
  double get baseline => maxAscent;
}

/// Результат раскладки «в один плоский список строк».
class CustomTextLayout {
  /// Все строки (LineLayout).
  final List<LineLayout> lines;

  /// Общая «виртуальная» высота (без учёта реальных страниц).
  final double totalHeight;

  /// У каждой строки храним индекс её абзаца, чтобы при желании учитывать сироты/вдов.
  final List<int> paragraphIndexOfLine;

  CustomTextLayout({
    required this.lines,
    required this.totalHeight,
    required this.paragraphIndexOfLine,
  });
}

/// Описание одной «страницы» с несколькими колонками.
class MultiColumnPage {
  /// Список колонок. Каждая колонка — список строк.
  final List<List<LineLayout>> columns;

  /// Ширина всей страницы.
  final double pageWidth;

  /// Высота страницы.
  final double pageHeight;

  /// Ширина одной колонки.
  final double columnWidth;

  /// Пробел между колонками.
  final double columnSpacing;

  MultiColumnPage({
    required this.columns,
    required this.pageWidth,
    required this.pageHeight,
    required this.columnWidth,
    required this.columnSpacing,
  });
}

/// Итоговый результат разбиения на страницы (многоколоночный).
class MultiColumnPagedLayout {
  /// Все страницы (каждая содержит несколько колонок).
  final List<MultiColumnPage> pages;

  MultiColumnPagedLayout(this.pages);
}
