import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:proxima_reader/feature/reader_screen/domain/model/styled_element.dart';

class ContentBlock {
  final BlockType type;

  // Для текста
  final InlineSpan? textSpan;
  // или вы можете хранить список StyledTextBlock,
  // в итоге превращая их в TextSpan при необходимости

  // Для изображения
  final Uint8List? imageData;    // Сырые байты, если берём из FB2 (base64)
  final double? desiredWidth;    // Желаемая ширина
  final double? desiredHeight;   // Желаемая высота (или null, если подстраивается)

  ContentBlock.text(this.textSpan)
      : type = BlockType.text,
        imageData = null,
        desiredWidth = null,
        desiredHeight = null;

  ContentBlock.image(
      this.imageData, {
        this.desiredWidth,
        this.desiredHeight,
      })  : type = BlockType.image,
        textSpan = null;
}