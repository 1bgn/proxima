// line_layout.dart
import 'inline_elements.dart';

class LineLayout {
  List<InlineElement> elements = [];
  double width = 0;
  double height = 0;
  double maxAscent = 0;
  double maxDescent = 0;

  // Новый флаг для обозначения конца секции
  bool isSectionEnd = false;

  double get baseline => maxAscent;
}
class CustomTextLayout {
  final List<LineLayout> lines;
  final double totalHeight;
  final List<int> paragraphIndexOfLine;

  CustomTextLayout({
    required this.lines,
    required this.totalHeight,
    required this.paragraphIndexOfLine,
  });
}

class MultiColumnPage {
  final List<List<LineLayout>> columns;
  final double pageWidth;
  final double pageHeight;
  final double columnWidth;
  final double columnSpacing;

  MultiColumnPage({
    required this.columns,
    required this.pageWidth,
    required this.pageHeight,
    required this.columnWidth,
    required this.columnSpacing,
  });
}

class MultiColumnPagedLayout {
  final List<MultiColumnPage> pages;

  MultiColumnPagedLayout(this.pages);
}
