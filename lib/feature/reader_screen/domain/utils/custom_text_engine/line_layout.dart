// line_layout.dart
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/paragraph_block.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/text_layout_engine.dart';

import 'inline_elements.dart';

// line_layout.dart (или где у вас располагается LineLayout)
import 'inline_elements.dart';

import 'inline_elements.dart';
import 'inline_elements.dart';


class LineLayout {
  List<InlineElement> elements = [];
  double width = 0;
  double height = 0;
  double maxAscent = 0;
  double maxDescent = 0;
  bool isSectionEnd = false;
  CustomTextAlign textAlign = CustomTextAlign.left;
  CustomTextDirection textDirection = CustomTextDirection.ltr;
  // Новое свойство для хранения коэффициента контейнерного смещения
  double containerOffset = 0;
  double containerOffsetFactor = 1.0; // По умолчанию 1.0 (то есть весь доступный width)

  double get baseline => maxAscent;

  LineLayout();

  LineLayout.withParams({
    required this.elements,
    required this.width,
    required this.height,
    required this.maxAscent,
    required this.maxDescent,
    this.isSectionEnd = false,
    this.textAlign = CustomTextAlign.left,
    this.textDirection = CustomTextDirection.ltr,
    this.containerOffset = 0,
    this.containerOffsetFactor = 1.0,
  });

  LineLayout copyWith({
    List<InlineElement>? elements,
    double? width,
    double? height,
    double? maxAscent,
    double? maxDescent,
    bool? isSectionEnd,
    CustomTextAlign? textAlign,
    CustomTextDirection? textDirection,
    double? containerOffset,
    double? containerOffsetFactor,
  }) {
    return LineLayout.withParams(
      elements: elements ?? this.elements,
      width: width ?? this.width,
      height: height ?? this.height,
      maxAscent: maxAscent ?? this.maxAscent,
      maxDescent: maxDescent ?? this.maxDescent,
      isSectionEnd: isSectionEnd ?? this.isSectionEnd,
      textAlign: textAlign ?? this.textAlign,
      textDirection: textDirection ?? this.textDirection,
      containerOffset: containerOffset ?? this.containerOffset,
      containerOffsetFactor: containerOffsetFactor ?? this.containerOffsetFactor,
    );
  }
}






class MultiColumnPagedLayout {
  final List<MultiColumnPage> pages;

  MultiColumnPagedLayout(this.pages);
}
