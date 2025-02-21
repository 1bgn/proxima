// fb2_parser.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:xml/xml.dart';
import 'package:flutter/painting.dart';

enum BlockType {
  text,
  image,
  pageBreak,
}

/// Модель блока контента
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
    double topSpacing = 0.0,
    double bottomSpacing = 0.0,
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
    required Uint8List imageData,
    required double width,
    required double height,
    double topSpacing = 0.0,
    double bottomSpacing = 0.0,
  }) {
    return ContentBlock(
      type: BlockType.image,
      imageData: imageData,
      width: width,
      height: height,
      topSpacing: topSpacing,
    );
  }
}

// Если нужно добавлять \u00AD:
class Hyphenator {
  String hyphenate(String text) {
    // Тут вставляйте \u00AD при необходимости,
    // например, используя словарь.
    return text;
  }
}

final _hyphenator = Hyphenator();

extension _XmlFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

Future<List<ContentBlock>> parseFb2(String fb2String) async {
  final document = XmlDocument.parse(fb2String);

  final imagesMap = _parseBinary(document);
  final bodyEl = document.findAllElements('body').firstOrNull;
  if (bodyEl == null) return [];

  final blocks = <ContentBlock>[];
  await _parseBody(bodyEl, blocks, imagesMap, topLevel: true);
  return blocks;
}

Map<String, Uint8List> _parseBinary(XmlDocument doc) {
  final result = <String, Uint8List>{};
  final bins = doc.findAllElements('binary');
  for (final bin in bins) {
    final id = bin.getAttribute('id');
    if (id == null) continue;
    final base64String = bin.text.replaceAll(RegExp(r'\s+'), '');
    if (base64String.isEmpty) continue;

    try {
      final bytes = Uint8List.fromList(const Base64Decoder().convert(base64String));
      result[id] = bytes;
    } catch (_) {}
  }
  return result;
}

Future<void> _parseBody(XmlElement el, List<ContentBlock> blocks, Map<String, Uint8List> imagesMap, {bool topLevel = false}) async {
  // Если <section> (новая глава?), вставим pageBreak
  if (topLevel && el.name.local == 'section') {
    blocks.add(ContentBlock.pageBreak());
  }

  for (final node in el.children) {
    if (node is XmlElement) {
      switch (node.name.local) {
        case 'section':
          blocks.add(ContentBlock.pageBreak());
          await _parseBody(node, blocks, imagesMap, topLevel: false);
          break;

        case 'title':
          final t = node.text.trim();
          if (t.isNotEmpty) {
            blocks.add(_styledBlock(
              text: t,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF000000)),
              align: TextAlign.center,
              topSpacing: 8,
              bottomSpacing: 8,
            ));
          }
          break;

        case 'subtitle':
          final st = node.text.trim();
          if (st.isNotEmpty) {
            blocks.add(_styledBlock(
              text: st,
              style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Color(0xFF000000)),
              align: TextAlign.center,
              topSpacing: 6,
              bottomSpacing: 6,
            ));
          }
          break;

        case 'p':
          final ptxt = node.text.trim();
          if (ptxt.isNotEmpty) {
            blocks.add(_styledBlock(
              text: ptxt,
              style: const TextStyle(fontSize: 16, color: Color(0xFF000000)),
              align: TextAlign.left,
              topSpacing: 4,
              bottomSpacing: 4,
            ));
          }
          break;

        case 'epigraph':
          for (final ptag in node.findAllElements('p')) {
            final etxt = ptag.text.trim();
            if (etxt.isNotEmpty) {
              blocks.add(_styledBlock(
                text: etxt,
                style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Color(0xFF000000)),
                align: TextAlign.center,
                topSpacing: 4,
                bottomSpacing: 4,
              ));
            }
          }
          break;

        case 'image':
          final ib = await _buildImage(node, imagesMap);
          if (ib != null) {
            blocks.add(ib);
          }
          break;
      }
    }
  }
}

ContentBlock _styledBlock({
  required String text,
  required TextStyle style,
  required TextAlign align,
  double topSpacing = 0,
  double bottomSpacing = 0,
}) {
  final hyphText = _hyphenator.hyphenate(text);
  final span = TextSpan(text: hyphText, style: style);
  return ContentBlock.text(
    textSpan: span,
    textAlign: align,
    topSpacing: topSpacing,
    bottomSpacing: bottomSpacing,
  );
}

Future<ContentBlock?> _buildImage(XmlElement node, Map<String, Uint8List> imagesMap) async {
  final href = node.getAttribute('xlink:href')
      ?? node.getAttribute('href')
      ?? node.getAttribute('l:href')
      ?? node.getAttribute('{http://www.w3.org/1999/xlink}href');
  if (href == null) return null;

  final id = href.startsWith('#') ? href.substring(1) : href;
  final bytes = imagesMap[id];
  if (bytes == null) return null;

  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width.toDouble();
    final h = frame.image.height.toDouble();

    return ContentBlock.image(
      imageData: bytes,
      width: w,
      height: h,
      topSpacing: 8,
      bottomSpacing: 8,
    );
  } catch (_) {
    return null;
  }
}
