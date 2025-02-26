// asset_fb2_loader.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart';
import 'package:flutter/material.dart';
import 'custom_text_engine/inline_elements.dart';
import 'custom_text_engine/paragraph_block.dart';

import 'hyphenator.dart';
import 'styles_config.dart';

class AssetFB2Loader {
  final String assetPath;
  final Hyphenator hyphenator;

  bool _initialized = false;
  String? _fb2content;
  final List<ParagraphBlock> _allParagraphs = [];
  final Map<String, Future<ui.Image>> _imageCache = {};

  AssetFB2Loader({
    required this.assetPath,
    required this.hyphenator,
  });

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _fb2content = await rootBundle.loadString(assetPath);
    final doc = XmlDocument.parse(_fb2content!);
    print("Fewfgew");

    _parseBinaries(doc);
    _parseAllParagraphs(doc);
  }

  int countParagraphs() => _allParagraphs.length;

  Future<List<ParagraphBlock>> loadChunk(int chunkIndex, int chunkSize) async {

    await init();
    final start = chunkIndex * chunkSize;
    if (start >= _allParagraphs.length) return [];
    final end = (start + chunkSize).clamp(0, _allParagraphs.length);
    return _allParagraphs.sublist(start, end);
  }

  void _parseBinaries(XmlDocument doc) {
    final bins = doc.findAllElements('binary');
    for (final bin in bins) {
      final id = bin.getAttribute('id');
      if (id == null) continue;
      final b64 = bin.innerText.trim();
      final data = base64.decode(b64);
      _imageCache[id] = _decodeImage(data);
    }
  }

  Future<ui.Image> _decodeImage(Uint8List data) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(data, (img) {
      if (img != null) completer.complete(img);
      else completer.completeError('Failed to decode image');
    });
    return completer.future;
  }

  void _parseAllParagraphs(XmlDocument doc) {

    final body = doc.findAllElements('body').isNotEmpty ? doc.findAllElements('body').first : null;
    if (body == null) return;
    // Обрабатываем расширенные теги:
    for (final tag in ['annotation', 'epigraph', 'empgraph']) {
      for (final elem in body.findElements(tag)) {
        _processSectionLike(elem, tag);
      }
    }
    for (final poem in body.findElements('poem')) {
      _processPoem(poem);
    }
    // Обрабатываем стандартные <p>
    final pElems = body.findElements('p').toList();
    for (final p in pElems) {
      final pb = _parseParagraph(p, style: StylesConfig.baseText);
      if (pb != null) _allParagraphs.add(pb);
    }
  }

  void _processSectionLike(XmlElement elem, String tag) {
    TextStyle style;
    if (tag == 'annotation') {
      style = StylesConfig.annotation;
    } else if (tag == 'epigraph') {
      style = StylesConfig.epigraph;
    } else if (tag == 'empgraph') {
      style = const TextStyle(fontWeight: FontWeight.w300, fontSize: 16);
    } else {
      style = StylesConfig.baseText;
    }
    for (final p in elem.findElements('p')) {
      final pb = _parseParagraph(p, style: style);
      if (pb != null) _allParagraphs.add(pb);
    }
  }

  void _processPoem(XmlElement poemElem) {
    // Заголовок поэмы
    for (final title in poemElem.findElements('title')) {
      for (final p in title.findElements('p')) {

        final pb = _parseParagraph(p, style: StylesConfig.boldHeader);
        if (pb != null) _allParagraphs.add(pb);
      }
    }
    // Строфы
    for (final stanza in poemElem.findElements('stanza')) {
      for (final p in stanza.findElements('p')) {
        final pb = _parseParagraph(p, style: StylesConfig.epigraph);
        if (pb != null) _allParagraphs.add(pb);
      }
    }
  }

  ParagraphBlock? _parseParagraph(XmlElement elem, {TextStyle? style}) {

    final inlines = <InlineElement>[];
    final baseStyle = style ;
    void visit(XmlNode node, TextStyle currentStyle) {
      if (node is XmlText) {
        final raw = node.text.replaceAll(RegExp(r'\s+'), ' ');
        if (raw.isNotEmpty) {
          final hy = hyphenator.hyphenate(raw);
          inlines.add(TextInlineElement(hy, currentStyle));
        }
      } else if (node is XmlElement) {
        final tag = node.name.local.toLowerCase();
        if (tag == 'strong') {
          final newStyle = currentStyle.copyWith(fontWeight: FontWeight.bold);
          node.children.forEach((child) => visit(child, newStyle));
        } else if (tag == 'emphasis' || tag == 'i') {
          final newStyle = currentStyle.copyWith(fontStyle: FontStyle.italic);
          node.children.forEach((child) => visit(child, newStyle));
        } else if (tag == 'image') {
          final href = node.getAttribute('l:href') ?? node.getAttribute('href');
          if (href != null && href.startsWith('#')) {
            final id = href.substring(1);
            if (_imageCache.containsKey(id)) {
              final fut = _imageCache[id]!;
              inlines.add(ImageFutureInlineElement(
                future: fut,
                desiredWidth: 200,
                desiredHeight: 150,
              ));
            }
          }
        } else {
          node.children.forEach((child) => visit(child, currentStyle));
        }
      }
    }
    elem.children.forEach((child) => visit(child, baseStyle!));
    if (inlines.isEmpty) return null;
    return ParagraphBlock(
      inlineElements: inlines,
      textAlign: null,
      textDirection: CustomTextDirection.ltr,
      firstLineIndent: 0,
      paragraphSpacing: 10,
      minimumLines: 1,
    );
  }
}
