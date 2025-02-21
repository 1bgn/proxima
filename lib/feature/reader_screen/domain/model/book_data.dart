import 'package:flutter/material.dart';
import 'package:proxima_reader/feature/reader_screen/domain/model/styled_element.dart';

import 'decoded_xml.dart';

class BookData{
  final DecodedXml decodedXml;
  final BoxConstraints size;
  final int countWordsInBook;
  final double devicePixelRatio;
  late final List<StyledElement> _originalElements;

  BookData({required this.decodedXml, required this.size, required this.devicePixelRatio,required this.countWordsInBook}){
    _originalElements = List.from(decodedXml.elements);

  }
  void resetElements() {
    decodedXml.elements.clear();
    decodedXml.elements.addAll(List.from(_originalElements));
}
}