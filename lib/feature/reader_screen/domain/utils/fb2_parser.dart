// fb2_parser.dart

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:xml/xml.dart';
import 'package:flutter/painting.dart';
import 'hyphenator.dart';

enum BlockType {
  text,
  image,
  pageBreak,
}

class ContentBlock {
  final BlockType type;
  final InlineSpan? textSpan;
  final TextAlign textAlign;
  final double topSpacing;
  final double bottomSpacing;

  final Uint8List? imageData;
  final double? width;
  final double? height;

  ContentBlock({
    required this.type,
    this.textSpan,
    this.textAlign = TextAlign.left,
    this.topSpacing = 0.0,
    this.bottomSpacing = 0.0,
    this.imageData,
    this.width,
    this.height,
  });

  factory ContentBlock.pageBreak() => ContentBlock(type: BlockType.pageBreak);

  factory ContentBlock.text({
    required InlineSpan textSpan,
    TextAlign textAlign = TextAlign.left,
    double topSpacing = 0,
    double bottomSpacing = 0,
  }) {
    return ContentBlock(
      type: BlockType.text,
      textSpan: textSpan,
      textAlign: textAlign,
      topSpacing: topSpacing,
      bottomSpacing: bottomSpacing,
    );
  }

  factory ContentBlock.image({
    required Uint8List? imageData,
    required double width,
    required double height,
    double topSpacing = 0,
    double bottomSpacing = 0,
  }) {
    return ContentBlock(
      type: BlockType.image,
      imageData: imageData,
      width: width,
      height: height,
      topSpacing: topSpacing,
      bottomSpacing: bottomSpacing,
    );
  }
}

final _hyphenator = Hyphenator();

extension XmlFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

Future<List<ContentBlock>> parseFb2(String fb2String) async {
  final doc = XmlDocument.parse(fb2String);
  final bodyEl = doc.findAllElements('body').firstOrNull;
  if (bodyEl == null) return [];

  final blocks = <ContentBlock>[];
  _parseBodyElement(bodyEl, blocks, true);
  return blocks;
}

void _parseBodyElement(XmlElement el, List<ContentBlock> blocks, bool isTopLevel) {
  // Если начало <section>, добавляем разрыв страницы
  if (isTopLevel && el.name.local == 'section') {
    blocks.add(ContentBlock.pageBreak());
  }

  for (final node in el.children) {
    if (node is XmlElement) {
      switch (node.name.local) {
        case 'section':
          blocks.add(ContentBlock.pageBreak());
          _parseBodyElement(node, blocks, false);
          break;

        case 'title':
          final t = _cleanText(node.text);
          if (t.isNotEmpty) {
            // Заголовок всегда начинается с новой страницы
            blocks.add(ContentBlock.pageBreak());
            blocks.add(_makeTextBlock(t, 22, FontWeight.bold, TextAlign.center, 8, 8));
          }
          break;

        case 'subtitle':
          final st = _cleanText(node.text);
          if (st.isNotEmpty) {
            // Подзаголовок также с новой строки
            blocks.add(ContentBlock.pageBreak());
            blocks.add(_makeTextBlock(st, 18, FontWeight.w400, TextAlign.center, 6, 6, italic: true));
          }
          break;

        case 'p':
          final p = _cleanText(node.text);
          if (p.isNotEmpty) {
            blocks.add(_makeTextBlock(p, 16, FontWeight.w400, TextAlign.left, 4, 4));
          }
          break;

      // Дополнительные теги (например, epigraph) можно добавить аналогично.
      }
    }
  }
}

String _cleanText(String raw) {
  final r = raw.replaceAll('\n', ' ');
  final c = r.replaceAll(RegExp(r'\s+'), ' ');
  return c.trim();
}

ContentBlock _makeTextBlock(String text, double fontSize, FontWeight weight, TextAlign align, double topSpacing, double bottomSpacing, {bool italic = false}) {
  final hyphText = _hyphenator.hyphenate(text);
  final style = TextStyle(
    fontSize: fontSize,
    fontWeight: weight,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    color: const Color(0xFF000000),
    height: 1.3,
  );
  return ContentBlock.text(
    textSpan: TextSpan(text: hyphText, style: style),
    textAlign: align,
    topSpacing: topSpacing,
    bottomSpacing: bottomSpacing,
  );
}
