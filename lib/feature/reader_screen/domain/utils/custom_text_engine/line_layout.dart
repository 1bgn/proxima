// line_layout.dart
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/paragraph_block.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/text_layout_engine.dart';

import 'inline_elements.dart';

// line_layout.dart (или где у вас располагается LineLayout)
import 'inline_elements.dart';

import 'inline_elements.dart';
import 'inline_elements.dart';



class LineLayout {
  // Внутренние inline-элементы, которые составляют строку
  List<InlineElement> elements = [];

  // Общая ширина и высота строки
  double width = 0;
  double height = 0;

  // Асцент/десцент для вычисления baseline
  double maxAscent = 0;
  double maxDescent = 0;

  // Признак конца секции (если нужно отделить особой логикой)
  bool isSectionEnd = false;

  // Добавим поля для выравнивания:
  CustomTextAlign textAlign = CustomTextAlign.left;
  CustomTextDirection textDirection = CustomTextDirection.ltr;

  // Удобный геттер
  double get baseline => maxAscent;

  // Конструктор по умолчанию (если нужно)
  LineLayout();

  // Можем добавить конструктор с инициализацией
  LineLayout.withParams({
    required this.elements,
    required this.width,
    required this.height,
    required this.maxAscent,
    required this.maxDescent,
    this.isSectionEnd = false,
    this.textAlign = CustomTextAlign.left,
    this.textDirection = CustomTextDirection.ltr,
  });

  // Метод-копия, если нужен
  LineLayout copyWith({
    List<InlineElement>? elements,
    double? width,
    double? height,
    double? maxAscent,
    double? maxDescent,
    bool? isSectionEnd,
    CustomTextAlign? textAlign,
    CustomTextDirection? textDirection,
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
    );
  }
}





class MultiColumnPagedLayout {
  final List<MultiColumnPage> pages;

  MultiColumnPagedLayout(this.pages);
}
