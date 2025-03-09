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

/// Пример FB2-парсера:
/// - Загружает и парсит весь документ целиком.
/// - Параметр chunkSize больше не влияет на разрывы страниц, а используется только для
///   ленивой выдачи абзацев в UI.
/// - По окончании <section> добавляет пустой ParagraphBlock с isSectionEnd=true.
/// - Заголовки (<title>, <subtitle>) и другие элементы,
///   содержащие несколько <p>, парсятся как несколько отдельных абзацев
///   (каждый <p> -> свой ParagraphBlock), чтобы гарантировать отображение с новой строки.
class AssetFB2Loader {
  final String assetPath;
  final Hyphenator hyphenator;

  bool _initialized = false;
  String? _fb2Content;
  final List<ParagraphBlock> _allParagraphs = [];
  final Map<String, Future<ui.Image>> _imageCache = {};

  AssetFB2Loader({
    required this.assetPath,
    required this.hyphenator,
  });

  /// Инициализация: грузим FB2, парсим.
  /// chunkSize не влияет на разрывы страниц,
  /// он нужен лишь для ленивого вывода (например, если документ огромный).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _fb2Content = await rootBundle.loadString(assetPath);
    final doc = XmlDocument.parse(_fb2Content!);

    _parseBinaries(doc);

    // Рекурсивно обходим все <body>.
    final bodies = doc.findAllElements('body');
    for (final body in bodies) {
      _processNode(body);
    }
  }

  /// Общее кол-во абзацев
  int countParagraphs() => _allParagraphs.length;

  /// Возвращаем полный список абзацев (весь документ).
  Future<List<ParagraphBlock>> loadAllParagraphs() async {
    await init();
    return List.unmodifiable(_allParagraphs);
  }

  /// Ленивый метод для UI (подгрузка по chunkSize),
  /// но не влияет на логику разрывов страниц.
  Future<List<ParagraphBlock>> loadChunk(int chunkIndex, int chunkSize) async {
    await init();
    final start = chunkIndex * chunkSize;
    if (start >= _allParagraphs.length) return [];
    final end = (start + chunkSize).clamp(0, _allParagraphs.length);
    return _allParagraphs.sublist(start, end);
  }

  /// Парсим <binary> -> _imageCache
  void _parseBinaries(XmlDocument doc) {
    final bins = doc.findAllElements('binary');
    for (final bin in bins) {
      final id = bin.getAttribute('id');
      if (id == null) continue;
      final b64 = bin.text.trim();
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

  /// Рекурсивный обход FB2.
  /// Если <section>, обрабатываем содержимое, потом
  /// добавляем ParagraphBlock(isSectionEnd=true), чтобы лейаут знал,
  /// что здесь заканчивается секция -> новая страница.
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
        // Маркер конца секции
        _allParagraphs.add(ParagraphBlock(
          inlineElements: [],
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
        // Блочный элемент (<p>, <title>, <subtitle>, <annotation>, ...)
        final blocks = _parseBlockOrMulti(elem: node);
        for (final b in blocks) {
          _allParagraphs.add(b);
        }
      } else {
        // Рекурсивный обход остальных
        for (final child in node.children) {
          _processNode(child);
        }
      }
    }
  }

  bool _isBlockElement(String tag) {
    // Теги, которые считаются блочными (кроме <section>, обрабатываем отдельной логикой).
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

  /// Унифицированный метод:
  /// Если элемент содержит несколько <p> (например <title>),
  /// мы хотим получить несколько ParagraphBlock (каждый <p> -> отдельный ParagraphBlock).
  /// Если элемент – обычное <p> или <image>, вернётся 1 блок.
  List<ParagraphBlock> _parseBlockOrMulti({required XmlElement elem}) {
    final tag = elem.name.local.toLowerCase();

    // Если этот элемент содержит непосредственно несколько <p>, то создадим несколько блоков.
    // Например, <title> может содержать несколько <p>.
    // Если же нет вложенных <p>, то это обычный случай -> вернём 1 блок.
    final pElements = elem.findElements('p');
    if (pElements.isNotEmpty && (tag == 'title' || tag == 'subtitle')) {
      // Для <title>, <subtitle> ... создаём несколько блоков (каждый <p> -> ParagraphBlock)
      final result = <ParagraphBlock>[];
      for (final p in pElements) {
        final singlePara = _parseParagraph(p, style: _decideStyleFor(tag))?.copyWith(
          textAlign: CustomTextAlign.center,
          // если нужно, меняем paragraphSpacing
          paragraphSpacing: 15,
        );
        if (singlePara != null) {
          result.add(singlePara);
        }
      }
      return result;
    }

    // Иначе это обычный блочный элемент -> 1 ParagraphBlock
    final single = _parseBlock(elem);
    if (single!= null) {
      return [single];
    } else {
      return [];
    }
  }

  /// Определяем стиль для <title> или <subtitle>
  TextStyle _decideStyleFor(String tag) {
    switch (tag) {
      case 'title':
        return StylesConfig.titleFont;
      case 'subtitle':
        return StylesConfig.subtitleFont;
      default:
        return StylesConfig.baseText;
    }
  }

  /// Старый метод _parseBlock, возвращающий один ParagraphBlock,
  /// если элемент не содержит вложенных <p>.
  ParagraphBlock? _parseBlock(XmlElement elem) {
    final tag = elem.name.local.toLowerCase();
    switch (tag) {
      case 'p':
        return _parseParagraph(elem, style: StylesConfig.baseText)
            ?.copyWith(
          textAlign: CustomTextAlign.left,
          firstLineIndent: 20,
          paragraphSpacing: 15,
        );
      case 'image':
        return _parseParagraph(elem, style: StylesConfig.baseText)
            ?.copyWith(
          textAlign: CustomTextAlign.center,
          firstLineIndent: 0,
        );
      case 'coverpage':
        for (final img in elem.findElements('image')) {
          final block = _parseParagraph(img, style: StylesConfig.coverImageStyle);
          if (block!= null) return block;
        }
        return null;
      case 'annotation':
      case 'poem':
      case 'text-author':
        return _parseParagraph(elem, style: StylesConfig.baseText)
            ?.copyWith(textAlign: CustomTextAlign.right);
      case 'epigraph':
        return _parseParagraph(elem, style: StylesConfig.epigraph)?.copyWith(breakable: true);
      case 'title':
      // Если встретили <title>, но не нашли внутри <p>, всё равно создаём
      // 1 параграф, чтобы текст не пропал.
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
        return _parseParagraph(elem, style: StylesConfig.baseText)
            ?.copyWith(
          textAlign: CustomTextAlign.left,
          firstLineIndent: 0,
        );
    }
  }

  ParagraphBlock? _parseParagraph(XmlElement elem, {TextStyle? style}) {
    final inlines = <InlineElement>[];
    final baseStyle = style ?? StylesConfig.baseText;

    // Если это <image> без дочерних
    if (elem.name.local.toLowerCase() == 'image' && elem.children.isEmpty) {
      final href = elem.getAttribute('l:href') ??
          elem.getAttribute('xlink:href') ??
          elem.getAttribute('href');
      if (href!= null && href.startsWith('#')) {
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
      // Рекурсивно собираем текст
      void visit(XmlNode node, TextStyle currentStyle) {
        if (node is XmlText) {
          final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
          if (text.isNotEmpty) {
            final hyph = hyphenator.hyphenate(text);
            inlines.add(TextInlineElement(hyph, currentStyle));
          }
        } else if (node is XmlElement) {
          final localTag = node.name.local.toLowerCase();
          if (localTag == 'b' || localTag=='strong') {
            final boldStyle = currentStyle.copyWith(fontWeight: FontWeight.bold);
            for (final child in node.children) {
              visit(child, boldStyle);
            }
          } else if (localTag == 'i' || localTag == 'em' || localTag=='emphasis') {
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

    return ParagraphBlock(
      inlineElements: inlines,
      textAlign: CustomTextAlign.left,
      firstLineIndent: 20,
      paragraphSpacing: 15,
      breakable: false,
    );
  }
}
