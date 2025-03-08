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
/// - Параметр chunkSize больше не влияет на разрывы страниц.
///   Он используется только для ленивой выдачи абзацев при необходимости (например, подгрузка экранами).
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

  /// Инициализация: грузим весь FB2, парсим и сохраняем абзацы.
  /// chunkSize никак не участвует в процессе layout; он нужен лишь для
  /// методики «ленивой» выдачи данных, если это требуется в UI.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _fb2Content = await rootBundle.loadString(assetPath);
    final doc = XmlDocument.parse(_fb2Content!);

    _parseBinaries(doc);

    // Рекурсивно обходим все элементы <body>.
    final bodies = doc.findAllElements('body');
    for (final body in bodies) {
      _processNode(body);
    }
  }

  /// Возвращает общее количество абзацев в документе.
  int countParagraphs() => _allParagraphs.length;

  /// Возвращает список ВСЕХ абзацев (полный документ).
  /// Этот метод можно использовать, чтобы передать их дальше в layout‑движок.
  Future<List<ParagraphBlock>> loadAllParagraphs() async {
    await init();
    return List.unmodifiable(_allParagraphs);
  }

  /// Возвращаем часть абзацев для ленивого отображения (если требуется).
  /// chunkSize не влияет на разрывы страниц; он просто «отрезает» часть массива.
  Future<List<ParagraphBlock>> loadChunk(int chunkIndex, int chunkSize) async {
    await init();
    final start = chunkIndex * chunkSize;
    if (start >= _allParagraphs.length) return [];
    final end = (start + chunkSize).clamp(0, _allParagraphs.length);
    return _allParagraphs.sublist(start, end);
  }

  void _parseBinaries(XmlDocument doc) {
    final binaries = doc.findAllElements('binary');
    for (final bin in binaries) {
      final id = bin.getAttribute('id');
      if (id == null) continue;
      final b64 = bin.text.trim();
      final data = base64.decode(b64);
      _imageCache[id] = _decodeImage(data);
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
  /// Если встречаем секцию, обрабатываем её содержимое, затем
  /// добавляем маркер конца секции (ParagraphBlock c isSectionEnd = true).
  void _processNode(XmlNode node) {
    if (node is XmlText) {
      // Пустые текстовые узлы игнорируем
      if (node.text.trim().isEmpty) return;
    } else if (node is XmlComment) {
      return;
    } else if (node is XmlElement) {
      final tag = node.name.local.toLowerCase();
      if (tag == 'section') {
        // Секция: обрабатываем внутренние элементы
        for (final child in node.children) {
          _processNode(child);
        }
        // По окончании секции – маркер isSectionEnd
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
        final pb = _parseBlock(node);
        if (pb != null) _allParagraphs.add(pb);
      } else {
        // Обход дочерних
        for (final child in node.children) {
          _processNode(child);
        }
      }
    }
  }

  bool _isBlockElement(String tag) {
    // Любые блочные теги, кроме <section> (который отдельно обрабатывается)
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

  /// Парсинг блочных элементов
  ParagraphBlock? _parseBlock(XmlElement elem) {
    final tag = elem.name.local.toLowerCase();
    switch (tag) {
      case 'p':
        return _parseParagraph(elem, style: StylesConfig.baseText)
            ?.copyWith(textAlign: CustomTextAlign.left, firstLineIndent: 20, paragraphSpacing: 15);
      case 'image':
        return _parseParagraph(elem, style: StylesConfig.baseText)
            ?.copyWith(textAlign: CustomTextAlign.center, firstLineIndent: 0);
      case 'coverpage':
        for (final img in elem.findElements('image')) {
          final pb = _parseParagraph(img, style: StylesConfig.coverImageStyle);
          if (pb != null) return pb;
        }
        return null;
      case 'annotation':
      case 'poem':
      case 'text-author':
        return _parseParagraph(elem, style: StylesConfig.baseText);
      case 'epigraph':
        return _parseParagraph(elem, style: StylesConfig.epigraph)
            ?.copyWith(breakable: true);
      case 'title':
        return _parseMultiParagraph(elem, StylesConfig.titleFont, CustomTextAlign.center);
      case 'subtitle':
        return _parseMultiParagraph(elem, StylesConfig.subtitleFont, CustomTextAlign.center);
      default:
        return _parseParagraph(elem, style: StylesConfig.baseText)
            ?.copyWith(textAlign: CustomTextAlign.left, firstLineIndent: 0);
    }
  }

  /// Если элемент содержит несколько <p>, объединяем их в один блок
  ParagraphBlock? _parseMultiParagraph(XmlElement elem, TextStyle style, CustomTextAlign align) {
    final pElems = elem.findElements('p');
    if (pElems.isEmpty) return null;
    final combined = <InlineElement>[];
    for (var p in pElems) {
      final block = _parseParagraph(p, style: style);
      if (block != null) {
        combined.addAll(block.inlineElements);
        combined.add(TextInlineElement("\n", style));
      }
    }
    if (combined.isNotEmpty && combined.last is TextInlineElement) {
      final last = combined.last as TextInlineElement;
      if (last.text.trim().isEmpty) combined.removeLast();
    }
    if (combined.isEmpty) return null;

    return ParagraphBlock(
      inlineElements: combined,
      textAlign: align,
      paragraphSpacing: 15,
      breakable: false,
    );
  }

  ParagraphBlock? _parseParagraph(XmlElement elem, {TextStyle? style}) {
    final inlines = <InlineElement>[];
    final baseStyle = style ?? StylesConfig.baseText;

    if (elem.name.local.toLowerCase() == 'image' && elem.children.isEmpty) {
      final href = elem.getAttribute('l:href') ??
          elem.getAttribute('xlink:href') ??
          elem.getAttribute('href');
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
            final hyphenated = hyphenator.hyphenate(raw);
            inlines.add(TextInlineElement(hyphenated, currentStyle));
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
