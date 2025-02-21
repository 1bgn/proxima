// fb2_parser.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:xml/xml.dart';
import 'hyphenator.dart'; // <-- подключаем ваш Hyphenator

enum BlockType {
  text,
  image,
}

class ContentBlock {
  final BlockType type;
  final InlineSpan? textSpan;
  final Uint8List? imageData;
  final double? desiredWidth;
  final double? desiredHeight;

  ContentBlock.text(this.textSpan)
      : type = BlockType.text,
        imageData = null,
        desiredWidth = null,
        desiredHeight = null;

  ContentBlock.image(this.imageData, {this.desiredWidth, this.desiredHeight})
      : type = BlockType.image,
        textSpan = null;
}

/// Инициализируем ваш кастомный Hyphenator
final Hyphenator _hyphenator = Hyphenator();

/// Пример парсера FB2:
/// - Собирает картинки из <binary>
/// - Ищет <body>, внутри <p>, <title>, <subtitle>, <epigraph>, <image>, ...
/// - Для текстовых элементов вызывает `_hyphenateText`
/// - Возвращает список ContentBlock
List<ContentBlock> parseFb2(String fb2Content) {
  final document = XmlDocument.parse(fb2Content);

  // 1) Собираем id -> bytes для картинок
  final imagesMap = _parseBinaryImages(document);

  // 2) Берём первый <body> (если есть)
  final bodyElement = document.findAllElements('body').isEmpty
      ? null
      : document.findAllElements('body').first;
  if (bodyElement == null) return [];

  // 3) Рекурсивно обходим содержимое <body> (условно, как <section>)
  return _parseBodyElement(bodyElement, imagesMap);
}

Map<String, Uint8List> _parseBinaryImages(XmlDocument doc) {
  final imagesMap = <String, Uint8List>{};
  final binaries = doc.findAllElements('binary');
  for (final bin in binaries) {
    final id = bin.getAttribute('id');
    if (id == null) continue;

    // base64 текст может быть многострочным, убираем \s
    final base64Text = bin.text.replaceAll(RegExp(r'\s+'), '');
    if (base64Text.isEmpty) continue;

    try {
      final bytes = base64.decode(base64Text);
      imagesMap[id] = bytes;
    } catch (_) {
      // ignore
    }
  }
  return imagesMap;
}

/// Рекурсивный обход тэгов внутри <body> (или <section>)
List<ContentBlock> _parseBodyElement(XmlElement element, Map<String, Uint8List> imagesMap) {
  final blocks = <ContentBlock>[];

  for (final node in element.children) {
    if (node is XmlElement) {
      switch (node.name.local) {
        case 'title':
          blocks.addAll(_parseTitle(node));
          break;
        case 'subtitle':
          blocks.addAll(_parseSubtitle(node));
          break;
        case 'p':
          final text = node.text;
          blocks.add(_buildParagraphBlock(text));
          break;
        case 'image':
          final imgBlock = _buildImageBlock(node, imagesMap);
          if (imgBlock != null) blocks.add(imgBlock);
          break;
        case 'epigraph':
          blocks.addAll(_parseEpigraph(node));
          break;
        case 'section':
        // рекурсивно
          blocks.addAll(_parseBodyElement(node, imagesMap));
          break;
      // ...
        default:
        // Можно добавить <poem>, <empty-line>, etc.
          break;
      }
    }
  }

  return blocks;
}

/// <title> -> обычно <p>, но иногда просто текст
List<ContentBlock> _parseTitle(XmlElement titleEl) {
  final blocks = <ContentBlock>[];
  final ps = titleEl.findAllElements('p');
  if (ps.isEmpty) {
    // Прямой текст
    final txt = titleEl.text.trim();
    if (txt.isNotEmpty) {
      blocks.add(_buildStyledBlock(txt, const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)));
    }
  } else {
    // Несколько <p>
    for (final p in ps) {
      final txt = p.text.trim();
      if (txt.isNotEmpty) {
        blocks.add(_buildStyledBlock(txt, const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)));
      }
    }
  }
  return blocks;
}

/// <subtitle> -> стилизуем чуть менее крупно
List<ContentBlock> _parseSubtitle(XmlElement subEl) {
  final txt = subEl.text.trim();
  if (txt.isEmpty) return [];
  return [
    _buildStyledBlock(txt, const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))
  ];
}

/// <epigraph> -> <p> (курсив)
List<ContentBlock> _parseEpigraph(XmlElement epigraphEl) {
  final blocks = <ContentBlock>[];
  for (final p in epigraphEl.findAllElements('p')) {
    final txt = p.text.trim();
    if (txt.isNotEmpty) {
      blocks.add(_buildStyledBlock(txt, const TextStyle(
        fontSize: 16, fontStyle: FontStyle.italic,
      )));
    }
  }
  return blocks;
}

/// Простая обёртка для обычных абзацев
ContentBlock _buildParagraphBlock(String text) {
  // Вызываем hyphenate
  final hyphText = _hyphenator.hyphenate(text.trim());
  final span = TextSpan(
    text: hyphText,
    style: const TextStyle(fontSize: 16, color: Color(0xFF000000)),
  );
  return ContentBlock.text(span);
}

/// Обёртка, позволяющая задать стиль (например, для title, subtitle)
ContentBlock _buildStyledBlock(String text, TextStyle style) {
  final hyphText = _hyphenator.hyphenate(text);
  final span = TextSpan(
    text: hyphText,
    style: style,
  );
  return ContentBlock.text(span);
}

/// Собираем картинку (если есть bytes)
ContentBlock? _buildImageBlock(XmlElement imageEl, Map<String, Uint8List> imagesMap) {
  final href = imageEl.getAttribute('xlink:href')
      ?? imageEl.getAttribute('href')
      ?? imageEl.getAttribute('l:href')
      ?? imageEl.getAttribute('{http://www.w3.org/1999/xlink}href');
  if (href == null) return null;
  final id = href.startsWith('#') ? href.substring(1) : href;
  final bytes = imagesMap[id];
  if (bytes == null) return null;
  return ContentBlock.image(bytes, desiredWidth: 200, desiredHeight: 200);
}
