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

/// Класс для загрузки и парсинга FB2‑файла из ассетов.
/// Элементы добавляются в порядке их следования в документе.
/// Теги <section> обрабатываются так, что после их содержимого вставляется специальный
/// ParagraphBlock с isSectionEnd: true, а для текстовых блоков с <emphasis> устанавливается breakable: true.
class AssetFB2Loader {
  final String assetPath;
  final Hyphenator hyphenator;

  bool _initialized = false;
  String? _fb2content;

  /// Итоговый список ParagraphBlock в порядке следования.
  final List<ParagraphBlock> _allParagraphs = [];

  /// Кэш для изображений: id -> Future<ui.Image>
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

    _parseBinaries(doc);

    // Рекурсивно обходим все <body> элементы.
    final bodies = doc.findAllElements('body');
    for (final body in bodies) {
      _parseBody(body);
    }
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
    final bins = doc.descendants.whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'binary');
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
      if (img != null) {
        completer.complete(img);
      } else {
        completer.completeError('Failed to decode image');
      }
    });
    return completer.future;
  }

  /// Рекурсивный обход XML-узлов внутри элемента.
  /// Если встречается <section>, сначала обрабатывается его содержимое,
  /// затем добавляется отдельный ParagraphBlock с isSectionEnd: true.
  void _parseBody(XmlElement elem) {
    for (final node in elem.children) {
      if (node is XmlText && node.text.trim().isEmpty) continue;
      if (node is XmlComment) continue;

      if (node is XmlElement) {
        final localName = node.name.local.toLowerCase();
        if (localName == 'section') {
          // Обрабатываем содержимое секции.
          _parseBody(node);
          // После окончания секции добавляем маркер конца секции.
          _allParagraphs.add(ParagraphBlock(
            inlineElements: [],
            textAlign: null,
            textDirection: CustomTextDirection.ltr,
            firstLineIndent: 0,
            paragraphSpacing: 0,
            minimumLines: 0,
            isSectionEnd: true,
          ));
        } else if (_isBlockElement(localName)) {
          final pb = _parseBlock(node);
          if (pb != null) _allParagraphs.add(pb);
        } else {
          _parseBody(node);
        }
      }
    }
  }

  bool _isBlockElement(String localName) {
    return localName == 'p' ||
        localName == 'empty-line' ||
        localName == 'image' ||
        localName == 'coverpage' ||
        localName == 'annotation' ||
        localName == 'epigraph' ||
        localName == 'poem' ||
        localName == 'title' ||
        localName == 'subtitle' ||
        localName == 'text-author';
  }

  ParagraphBlock? _parseBlock(XmlElement elem) {
    final localName = elem.name.local.toLowerCase();
    if (localName == 'empty-line') {
      return ParagraphBlock(
        inlineElements: [TextInlineElement("\n", StylesConfig.baseText)],
        textAlign: null,
        textDirection: CustomTextDirection.ltr,
        firstLineIndent: 0,
        paragraphSpacing: 10,
        minimumLines: 1,
      );
    } else if (localName == 'coverpage') {
      for (final imageElem in elem.findElements('image')) {
        final pb = _parseParagraph(imageElem, style: StylesConfig.coverImageStyle);
        if (pb != null) return pb;
      }
      return null;
    } else if (localName == 'annotation' ||
        localName == 'poem' ||
        localName == 'text-author') {
      return _parseParagraph(elem, style: StylesConfig.baseText);
    } else if (localName == 'epigraph') {
      // Для эпиграфов разрешаем дробление.
      return _parseParagraph(elem, style: StylesConfig.epigraph)?.copyWith(breakable: true);
    } else if (localName == 'title') {
      final pElems = elem.findElements('p');
      List<ParagraphBlock> blocks = [];
      for (final p in pElems) {
        final pb = _parseParagraph(p, style: StylesConfig.titleFont);
        if (pb != null) {
          blocks.add(pb.copyWith(textAlign: CustomTextAlign.center, firstLineIndent: 0));
        }
      }
      if (blocks.isNotEmpty) {
        final combinedInlines = <InlineElement>[];
        for (var i = 0; i < blocks.length; i++) {
          combinedInlines.addAll(blocks[i].inlineElements);
          if (i < blocks.length - 1) {
            combinedInlines.add(TextInlineElement("\n", StylesConfig.titleFont));
          }
        }
        return ParagraphBlock(
          inlineElements: combinedInlines,
          textAlign: CustomTextAlign.center,
          textDirection: CustomTextDirection.ltr,
          firstLineIndent: 0,
          paragraphSpacing: 10,
          minimumLines: 1,
          maxWidth: null,
        );
      }
      return null;
    } else if (localName == 'subtitle') {
      final pElems = elem.findElements('p');
      List<ParagraphBlock> blocks = [];
      for (final p in pElems) {
        final pb = _parseParagraph(p, style: StylesConfig.subtitleFont);
        if (pb != null) {
          blocks.add(pb.copyWith(textAlign: CustomTextAlign.center, firstLineIndent: 0));
        }
      }
      if (blocks.isNotEmpty) {
        final combinedInlines = <InlineElement>[];
        for (var i = 0; i < blocks.length; i++) {
          combinedInlines.addAll(blocks[i].inlineElements);
          if (i < blocks.length - 1) {
            combinedInlines.add(TextInlineElement("\n", StylesConfig.subtitleFont));
          }
        }
        return ParagraphBlock(
          inlineElements: combinedInlines,
          textAlign: CustomTextAlign.center,
          textDirection: CustomTextDirection.ltr,
          firstLineIndent: 0,
          paragraphSpacing: 10,
          minimumLines: 1,
          maxWidth: null,
        );
      }
      return null;
    } else if (localName == 'p') {
      return _parseParagraph(elem, style: StylesConfig.baseText)?.copyWith(
        textAlign: CustomTextAlign.left,
        firstLineIndent: 20,
      );
    } else if (localName == 'image') {
      return _parseParagraph(elem, style: StylesConfig.baseText)?.copyWith(
        textAlign: CustomTextAlign.center,
        firstLineIndent: 0,
      );
    } else {
      return _parseParagraph(elem, style: StylesConfig.baseText)?.copyWith(
        textAlign: CustomTextAlign.left,
        firstLineIndent: 0,
      );
    }
  }

  /// Парсит XML-элемент в ParagraphBlock.
  /// Если содержимое включает текст с тегами <emphasis>, <i> или <em>,
  /// то для возвращаемого блока устанавливается breakable: true.
  ParagraphBlock? _parseParagraph(XmlElement elem, {TextStyle? style, double? forcedMaxWidth}) {
    final inlines = <InlineElement>[];
    final baseStyle = style ?? StylesConfig.baseText;

    if (elem.name.local.toLowerCase() == 'image' && elem.children.isEmpty) {
      final href = elem.getAttribute('l:href')
          ?? elem.getAttribute('xlink:href')
          ?? elem.getAttribute('href');
      if (href != null && href.startsWith('#')) {
        final id = href.substring(1);
        if (_imageCache.containsKey(id)) {
          final fut = _imageCache[id]!;
          inlines.add(ImageFutureInlineElement(
            future: fut,
            desiredWidth: null,
            desiredHeight: null,
            minHeight: 100,
          ));
        }
      }
    } else {
      void visit(XmlNode node, TextStyle currentStyle) {
        if (node is XmlText) {
          final raw = node.text.replaceAll(RegExp(r'\s+'), ' ');
          if (raw.isNotEmpty) {
            final hy = hyphenator.hyphenate(raw);
            inlines.add(TextInlineElement(hy, currentStyle));
          }
        } else if (node is XmlElement) {
          final tag = node.name.local.toLowerCase();
          if (tag == 'b' || tag == 'strong') {
            final newStyle = currentStyle.copyWith(fontWeight: FontWeight.bold);
            for (final child in node.children) {
              visit(child, newStyle);
            }
          } else if (tag == 'i' || tag == 'em' || tag == 'emphasis') {
            // При обработке тега emphasis задаём курсив и помечаем, что блок можно дробить.
            final newStyle = currentStyle.copyWith(fontStyle: FontStyle.italic,);
            for (final child in node.children) {
              visit(child, newStyle);
            }
          } else if (tag == 'image') {
            final href = node.getAttribute('l:href')
                ?? node.getAttribute('xlink:href')
                ?? node.getAttribute('href');
            if (href != null && href.startsWith('#')) {
              final id = href.substring(1);
              if (_imageCache.containsKey(id)) {
                final fut = _imageCache[id]!;
                inlines.add(ImageFutureInlineElement(
                  future: fut,
                  desiredWidth: null,
                  desiredHeight: null,
                  minHeight: 100,
                ));
              }
            }
          } else {
            for (final child in node.children) {
              visit(child, currentStyle);
            }
          }
        }
      }
      for (final child in elem.children) {
        visit(child, baseStyle);
      }
    }
    if (inlines.isEmpty) return null;

    // Если хотя бы один inline-элемент имеет курсив, помечаем блок как breakable.
    bool isBreakable = false;
    for (final inline in inlines) {
      if (inline is TextInlineElement && inline.style.fontStyle == FontStyle.italic) {
        isBreakable = true;
        break;
      }
    }
    return ParagraphBlock(
      inlineElements: inlines,
      textAlign: null,
      textDirection: CustomTextDirection.ltr,
      firstLineIndent: 0,
      paragraphSpacing: 10,
      minimumLines: 1,
      maxWidth: forcedMaxWidth,
      breakable: isBreakable,
    );
  }
}
