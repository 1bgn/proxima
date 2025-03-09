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

/// Inline-элемент, обозначающий конец секции
class SectionBreakInlineElement extends InlineElement {
  @override
  void performLayout(double maxWidth) {
    width = 0;
    height = 0;
    baseline = 0;
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {}
}

/// Inline-элемент для изображений, использующий декодированный ui.Image
class ImageInlineElement extends InlineElement {
  final ui.Image image;
  final double desiredWidth;
  final double desiredHeight;
  final ImageDisplayMode mode;

  ImageInlineElement({
    required this.image,
    required this.desiredWidth,
    required this.desiredHeight,
    this.mode = ImageDisplayMode.inline,
  });

  @override
  void performLayout(double maxWidth) {
    double scale = 1.0;
    if (desiredWidth > maxWidth) {
      scale = maxWidth / desiredWidth;
    }
    width = desiredWidth * scale;
    height = desiredHeight * scale;
    baseline = height;
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(offset.dx, offset.dy, width, height);
    canvas.drawImageRect(image, srcRect, dstRect, Paint());
  }
}

/// Простой FB2-парсер, позволяющий обрабатывать <epigraph>:
/// 1) Не превращает весь epigraph в один блок, а рекурсивно извлекает вложенные <p>, <text-author> и т.п.
/// 2) Добавляет два ParagraphBlock: один для <p>, другой для <text-author>.
class AssetFB2Loader {
  final String assetPath;
  final Hyphenator hyphenator;

  bool _initialized = false;
  String? _fb2Content;

  final List<ParagraphBlock> _allParagraphs = [];
  final Map<String, ui.Image> _decodedImages = {};

  AssetFB2Loader({
    required this.assetPath,
    required this.hyphenator,
  });

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _fb2Content = await rootBundle.loadString(assetPath);
    final doc = XmlDocument.parse(_fb2Content!);

    // 1. Сначала декодируем <binary> => _decodedImages
    await _parseBinaries(doc);

    // 2. Идём по всем <body> и обрабатываем рекурсивно
    final bodies = doc.findAllElements('body');
    for (final body in bodies) {
      _processNode(body);
    }
  }

  /// Возвращает список всех абзацев
  Future<List<ParagraphBlock>> loadAllParagraphs() async {
    await init();
    return List.unmodifiable(_allParagraphs);
  }

  /// Возвращает часть абзацев для ленивого отображения
  Future<List<ParagraphBlock>> loadChunk(int chunkIndex, int chunkSize) async {
    await init();
    final start = chunkIndex * chunkSize;
    if (start >= _allParagraphs.length) return [];
    final end = (start + chunkSize).clamp(0, _allParagraphs.length);
    return _allParagraphs.sublist(start, end);
  }

  /// Декодируем <binary>
  Future<void> _parseBinaries(XmlDocument doc) async {
    final binaries = doc.findAllElements('binary');
    for (final bin in binaries) {
      final id = bin.getAttribute('id');
      if (id == null) continue;
      final b64 = bin.text.trim();
      final data = base64.decode(b64);
      final image = await _decodeImage(data);
      _decodedImages[id] = image;
    }
  }

  Future<ui.Image> _decodeImage(Uint8List data) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(data, (image) {
      if (image != null) {
        completer.complete(image);
      } else {
        completer.completeError('Failed to decode image');
      }
    });
    return completer.future;
  }

  /// Рекурсивный обход FB2-тегов
  void _processNode(XmlNode node) {
    if (node is XmlElement) {
      final tag = node.name.local.toLowerCase();

      if (tag == 'section') {
        // Вложенные узлы
        for (final child in node.children) {
          _processNode(child);
        }
        // Маркер конца секции
        _allParagraphs.add(
          ParagraphBlock(
            inlineElements: [SectionBreakInlineElement()],
            isSectionEnd: true,
            breakable: false,
          ),
        );
      }
      else if (tag == 'empty-line') {
        // Пустая строка
        _allParagraphs.add(
          ParagraphBlock(
            inlineElements: [TextInlineElement("\n", StylesConfig.baseText)],
            paragraphSpacing: 10,
            breakable: false,
            minimumLines: 1
          ),
        );
      }
      else if (tag == 'epigraph') {
        // КЛЮЧЕВОЙ момент: не делаем из epigraph один абзац,
        // а разбираем каждого дочернего блочного ребёнка по отдельности
        _parseEpigraph(node);
      }
      else if (_isBlockElement(tag)) {
        // Прочие блочные элементы (<p>, <text-author>, <subtitle> и т.д.)
        final blocks = _parseBlockOrMulti(node);
        _allParagraphs.addAll(blocks);
      }
      else {
        // Рекурсивный обход
        for (final child in node.children) {
          _processNode(child);
        }
      }
    }
  }

  bool _isBlockElement(String tag) {
    const blockTags = {
      'p',
      'image',
      'coverpage',
      'annotation',
      'epigraph',
      'poem',
      'title',
      'subtitle',
      'text-author',
    };
    return blockTags.contains(tag);
  }

  /// Рекурсивно обходим детей epigraph,
  /// если встречаем блочные элементы (p, text-author и т.д.), создаём ParagraphBlock
  void _parseEpigraph(XmlElement epigraphNode) {
    double? epigraphMaxWidth;

    epigraphMaxWidth = 0.7;

    CustomTextAlign? epigraphContainerAlignment;

    epigraphContainerAlignment = CustomTextAlign.right;
    for (final child in epigraphNode.children) {
      if (child is XmlElement) {
        final childTag = child.name.local.toLowerCase();
        if (_isBlockElement(childTag)) {
          // Получаем блоки для дочернего элемента
          final blocks = _parseBlockOrMulti(child);
          // Передаем родительские параметры, если они не заданы в самом блоке
          for (final b in blocks) {
            _allParagraphs.add(
              b.copyWith(
                breakable: true,
                paragraphSpacing: 5,
                enableRedLine: false,
                // Если у блока не задан maxWidth, наследуем от epigraph
                maxWidth: b.maxWidth ?? epigraphMaxWidth,
                // Если у блока не задано containerAlignment, наследуем от epigraph
                containerAlignment: b.containerAlignment ?? epigraphContainerAlignment,
              ),
            );
          }
        } else {
          _processNode(child);
        }
      } else if (child is XmlText) {
        final text = child.text.trim();
        if (text.isNotEmpty) {
          _allParagraphs.add(
            ParagraphBlock(
              inlineElements: [
                TextInlineElement(text, StylesConfig.epigraph),
              ],
              textAlign: CustomTextAlign.left,
              textDirection: CustomTextDirection.ltr,
              firstLineIndent: 20,
              paragraphSpacing: 10,
              minimumLines: 1,
              maxWidth: epigraphMaxWidth,
              // Применяем containerAlignment, если задано
              containerAlignment: epigraphContainerAlignment,
              isSectionEnd: false,
              breakable: true,
            ),
          );
        }
      }
    }
  }



  /// Если элемент содержит <p>, возвращаем список ParagraphBlock,
  /// иначе обрабатываем элемент как единый блок
  List<ParagraphBlock> _parseBlockOrMulti(XmlElement elem) {
    final tag = elem.name.local.toLowerCase();
    final pElements = elem.findElements('p').toList();

    // Если элемент (например, <title>) содержит несколько <p>,
    // каждый <p> превращается в отдельный ParagraphBlock
    if (pElements.isNotEmpty) {
      final result = <ParagraphBlock>[];
      for (final p in pElements) {
        final block = _parseParagraph(p, style: _decideStyleFor(tag))?.copyWith(
          textAlign: _decideAlignFor(tag),
          firstLineIndent: (tag == 'p') ? 20 : 0,
          paragraphSpacing: 15,
        );
        if (block != null) {
          result.add(block);
        }
      }
      return result;
    } else {
      // Иначе обрабатываем элемент как единый блок
      final singleBlock = _parseBlock(elem);
      if (singleBlock != null) return [singleBlock];
      return [];
    }
  }

  TextStyle _decideStyleFor(String tag) {
    switch (tag) {
      case 'title':
        return StylesConfig.titleFont;
      case 'subtitle':
        return StylesConfig.subtitleFont;
      case 'text-author':
        return StylesConfig.authorFont;
      case 'epigraph':
        return StylesConfig.epigraph;
      default:
        return StylesConfig.baseText;
    }
  }

  CustomTextAlign _decideAlignFor(String tag) {
    switch (tag) {
      case 'text-author':
        return CustomTextAlign.right;
      case 'title':
      case 'subtitle':

        return CustomTextAlign.center;
      default:
        return CustomTextAlign.left;
    }
  }

  /// Обрабатываем элемент как единый блок
  ParagraphBlock? _parseBlock(XmlElement elem) {
    final tag = elem.name.local.toLowerCase();
    switch (tag) {
      case 'p':
        return _parseParagraph(elem, style: StylesConfig.baseText)?.copyWith(
          textAlign: CustomTextAlign.left,
          firstLineIndent: 10,

          enableRedLine: true,
          paragraphSpacing: 0,
        );
      case 'image':
        return _parseParagraph(elem, style: StylesConfig.baseText)?.copyWith(
          textAlign: CustomTextAlign.center,
          firstLineIndent: 0,
        );
      case 'coverpage':
        for (final img in elem.findElements('image')) {
          final pb = _parseParagraph(img, style: StylesConfig.coverImageStyle);
          if (pb != null) return pb;
        }
        return null;
      case 'annotation':
      case 'poem':
        return _parseParagraph(elem, style: StylesConfig.baseText);
      case 'epigraph':
      // Вместо того, чтобы превращать epigraph в один блок,
      // вызываем _parseEpigraph. Здесь можно вернуть null,
      // так как _parseEpigraph сам добавит ParagraphBlock'и в _allParagraphs.
        _parseEpigraph(elem);
        return null;
      case 'text-author':
        return _parseParagraph(elem, style: StylesConfig.authorFont)?.copyWith(
          textAlign: CustomTextAlign.right,
          firstLineIndent: 0,
          paragraphSpacing: 0,
        );
      case 'title':
        return _parseParagraph(elem, style: StylesConfig.titleFont)?.copyWith(
          textAlign: CustomTextAlign.center,

          paragraphSpacing: 5,
        );
      case 'subtitle':
        return _parseParagraph(elem, style: StylesConfig.subtitleFont)?.copyWith(
          textAlign: CustomTextAlign.center,
          paragraphSpacing: 5,
        );
      default:
      // Прочие теги
        return _parseParagraph(elem, style: StylesConfig.baseText)?.copyWith(
          textAlign: CustomTextAlign.left,
          firstLineIndent: 0,
        );
    }
  }

  /// Собираем inline-элементы (текст, жирный, курсив, <image>)
  ParagraphBlock? _parseParagraph(XmlElement elem, {TextStyle? style}) {
    final inlines = <InlineElement>[];
    final baseStyle = style ?? StylesConfig.baseText;

    // Если это одиночный <image>
    if (elem.name.local.toLowerCase() == 'image' && elem.children.isEmpty) {
      final href = elem.getAttribute('l:href') ??
          elem.getAttribute('xlink:href') ??
          elem.getAttribute('href');
      if (href != null && href.startsWith('#')) {
        final id = href.substring(1);
        if (_decodedImages.containsKey(id)) {
          final image = _decodedImages[id]!;
          inlines.add(ImageInlineElement(
            image: image,
            desiredWidth: image.width.toDouble(),
            desiredHeight: image.height.toDouble(),
          ));
        }
      }
    } else {
      // Рекурсивный обход
      void visit(XmlNode node, TextStyle currentStyle) {
        if (node is XmlText) {
          final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
          if (text.isNotEmpty) {
            final hyph = hyphenator.hyphenate(text);
            inlines.add(TextInlineElement(hyph, currentStyle));
          }
        } else if (node is XmlElement) {
          final localTag = node.name.local.toLowerCase();
          if (localTag == 'b' || localTag == 'strong') {
            final boldStyle = currentStyle.copyWith(fontWeight: FontWeight.bold);
            for (final child in node.children) {
              visit(child, boldStyle);
            }
          } else if (localTag == 'i' || localTag == 'em' || localTag == 'emphasis') {
            final italicStyle = currentStyle.copyWith(fontStyle: FontStyle.italic);
            for (final child in node.children) {
              visit(child, italicStyle);
            }
          } else if (localTag == 'image') {
            final href = node.getAttribute('l:href') ??
                node.getAttribute('xlink:href') ??
                node.getAttribute('href');
            if (href != null && href.startsWith('#')) {
              final id = href.substring(1);
              if (_decodedImages.containsKey(id)) {
                final image = _decodedImages[id]!;
                inlines.add(ImageInlineElement(
                  image: image,
                  desiredWidth: image.width.toDouble(),
                  desiredHeight: image.height.toDouble(),
                ));
              }
            }
          } else {
            // Рекурсивно обходим вложенные теги
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

    return ParagraphBlock(
      inlineElements: inlines,
      textAlign: CustomTextAlign.left,
      textDirection: CustomTextDirection.ltr,
      firstLineIndent: 20,
      paragraphSpacing: 15,
      minimumLines: 1,
      maxWidth: null,
      isSectionEnd: false,
      breakable: false,
    );
  }
}
