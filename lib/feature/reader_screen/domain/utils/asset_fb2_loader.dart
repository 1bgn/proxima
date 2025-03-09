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

/// Новый inline-элемент, обозначающий маркер конца секции.
/// При layout устанавливает ширину и высоту равными 0.
class SectionBreakInlineElement extends InlineElement {
  @override
  void performLayout(double maxWidth) {
    width = 0;
    height = 0;
    baseline = 0;
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    // Ничего не рисуем
  }
}

/// Inline-элемент для изображений, который использует уже декодированное ui.Image
/// для вычисления итоговых размеров на основе натуральных размеров изображения.
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

/// Пример FB2-парсера, который:
/// • Загружает и парсит весь документ целиком.
/// • Для элементов <title>, <subtitle> и <text-author> каждый вложенный <p>
///   обрабатывается как отдельный ParagraphBlock (для text-author – выравнивание по правой стороне).
/// • Все бинарные данные (изображения) декодируются заранее и сохраняются в _decodedImages,
///   что позволяет сразу вычислять итоговые размеры изображений.
class AssetFB2Loader {
  final String assetPath;
  final Hyphenator hyphenator;

  bool _initialized = false;
  String? _fb2Content;
  final List<ParagraphBlock> _allParagraphs = [];
  // Храним уже декодированные изображения.
  final Map<String, ui.Image> _decodedImages = {};

  AssetFB2Loader({
    required this.assetPath,
    required this.hyphenator,
  });

  /// Инициализация: загружаем FB2, декодируем бинарные данные и сохраняем абзацы.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _fb2Content = await rootBundle.loadString(assetPath);
    final doc = XmlDocument.parse(_fb2Content!);

    // Декодируем все бинарные данные (изображения)
    await _parseBinaries(doc);

    // Рекурсивно обходим все элементы <body> и строим абзацы
    final bodies = doc.findAllElements('body');
    for (final body in bodies) {
      _processNode(body);
    }
  }

  /// Возвращает общее количество абзацев в документе.
  int countParagraphs() => _allParagraphs.length;

  /// Возвращает список ВСЕХ абзацев (полный документ).
  Future<List<ParagraphBlock>> loadAllParagraphs() async {
    await init();
    return List.unmodifiable(_allParagraphs);
  }

  /// Возвращает часть абзацев для ленивого отображения.
  /// Параметр chunkSize используется только для UI, а не влияет на разрывы страниц.
  Future<List<ParagraphBlock>> loadChunk(int chunkIndex, int chunkSize) async {
    await init();
    final start = chunkIndex * chunkSize;
    if (start >= _allParagraphs.length) return [];
    final end = (start + chunkSize).clamp(0, _allParagraphs.length);
    return _allParagraphs.sublist(start, end);
  }

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

  /// Рекурсивный обход тегов FB2.
  /// Для тега <section> обрабатываем содержимое, затем добавляем маркер конца секции.
  void _processNode(XmlNode node) {
    if (node is XmlText) {
      if (node.text.trim().isEmpty) return;
    } else if (node is XmlComment) {
      return;
    } else if (node is XmlElement) {
      final tag = node.name.local.toLowerCase();
      if (tag == 'section') {
        for (final child in node.children) {
          _processNode(child);
        }
        _allParagraphs.add(ParagraphBlock(
          inlineElements: [SectionBreakInlineElement()],
          isSectionEnd: true,
          breakable: false,
        ));
      } else if (tag == 'empty-line') {
        _allParagraphs.add(ParagraphBlock(
          inlineElements: [TextInlineElement("\n", StylesConfig.baseText)],
          paragraphSpacing: 10,
          breakable: false,
        ));
      } else if (_isBlockElement(tag)) {
        final blocks = _parseBlockOrMulti(elem: node);
        for (final b in blocks) {
          _allParagraphs.add(b);
        }
      } else {
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

  /// Если элемент содержит несколько <p> (например, <title>, <subtitle>, <text-author>),
  /// возвращаем ParagraphBlock для каждого <p>.
  /// Если вложенных <p> нет, для text-author дополнительно проверяем, есть ли текстовое содержимое.
  List<ParagraphBlock> _parseBlockOrMulti({required XmlElement elem}) {
    final tag = elem.name.local.toLowerCase();
    final pElements = elem.findElements('p').toList();
    if (pElements.isNotEmpty) {
      final result = <ParagraphBlock>[];
      for (final p in pElements) {
        CustomTextAlign align = (tag == 'text-author')
            ? CustomTextAlign.right
            : (tag == 'title' || tag == 'subtitle')
            ? CustomTextAlign.center
            : CustomTextAlign.left;
        final block = _parseParagraph(p, style: _decideStyleFor(tag))?.copyWith(
          textAlign: align,
          firstLineIndent: (tag == 'p') ? 20 : (tag == 'text-author' ? 0 : 0),
          paragraphSpacing: 15,
        );
        if (block != null) {
          result.add(block);
        }
      }
      return result;
    } else {
      // Если тег text-author не содержит <p>, но имеет текстовое содержимое, создаем блок из него.
      if (tag == 'text-author' && elem.text.trim().isNotEmpty) {

        final inline = TextInlineElement(elem.text.trim(), _decideStyleFor(tag));
        return [
          ParagraphBlock(
            inlineElements: [inline],
            textAlign: CustomTextAlign.right,
            textDirection: CustomTextDirection.ltr,
            firstLineIndent: 0,
            paragraphSpacing: 15,
            minimumLines: 1,
            maxWidth: null,
            isSectionEnd: false,
            breakable: false,
          )
        ];
      }
      // Если нет вложенных <p>, обрабатываем элемент как единый блок.
      return [_parseBlock(elem)!];
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
      default:
        return StylesConfig.baseText;
    }
  }

  /// Обрабатывает элемент как единый блок (если не содержит вложенных <p>).
  ParagraphBlock? _parseBlock(XmlElement elem) {
    final tag = elem.name.local.toLowerCase();
    switch (tag) {
      case 'p':
        return _parseParagraph(elem, style: StylesConfig.baseText)?.copyWith(
          textAlign: CustomTextAlign.left,
          firstLineIndent: 20,
          paragraphSpacing: 15,
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
        return _parseParagraph(elem, style: StylesConfig.epigraph)?.copyWith(breakable: true);
      case 'text-author':
        return _parseParagraph(elem, style: StylesConfig.authorFont)?.copyWith(
          textAlign: CustomTextAlign.right,
          firstLineIndent: 0,
          paragraphSpacing: 15,
        );
      case 'title':
        return _parseParagraph(elem, style: StylesConfig.titleFont)?.copyWith(
          textAlign: CustomTextAlign.center,
          paragraphSpacing: 15,
        );
      case 'subtitle':
        return _parseParagraph(elem, style: StylesConfig.subtitleFont)?.copyWith(
          textAlign: CustomTextAlign.center,
          paragraphSpacing: 15,
        );
      default:
        return _parseParagraph(elem, style: StylesConfig.baseText)?.copyWith(
          textAlign: CustomTextAlign.left,
          firstLineIndent: 0,
        );
    }
  }

  /// Основная логика обработки элемента как абзаца.
  /// Для тега <image> извлекаем изображение из _decodedImages и создаём ImageInlineElement.
  ParagraphBlock? _parseParagraph(XmlElement elem, {TextStyle? style}) {
    final inlines = <InlineElement>[];
    final baseStyle = style ?? StylesConfig.baseText;

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
