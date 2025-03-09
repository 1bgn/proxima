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

/// Пример FB2-парсера:
/// - Загружает и парсит весь документ целиком.
/// - Параметр chunkSize больше не влияет на разрывы страниц.
///   Он используется только для ленивой выдачи абзацев при необходимости (например, подгрузка экранами).
/// - Для элементов <title>, <subtitle> и <text-author> каждый вложенный <p>
///   обрабатывается как отдельный ParagraphBlock, причем для <text-author>
///   дополнительно устанавливается выравнивание по правой стороне.
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
  /// Параметр chunkSize не участвует в layout.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _fb2Content = await rootBundle.loadString(assetPath);
    final doc = XmlDocument.parse(_fb2Content!);

    _parseBinaries(doc);

    // Рекурсивно обходим все элементы <body>
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
  /// При встрече секции обрабатываем её содержимое, а затем добавляем
  /// маркер конца секции (ParagraphBlock с isSectionEnd == true).
  void _processNode(XmlNode node) {
    if (node is XmlText) {
      // Пустые текстовые узлы игнорируем
      if (node.text.trim().isEmpty) return;
    } else if (node is XmlComment) {
      return;
    } else if (node is XmlElement) {
      final tag = node.name.local.toLowerCase();
      if (tag == 'section') {
        // Обрабатываем содержимое секции
        for (final child in node.children) {
          _processNode(child);
        }
        // Добавляем маркер конца секции с использованием SectionBreakInlineElement
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
        // Для блочных элементов, таких как <p>, <title>, <subtitle>, <text-author>:
        // Если элемент содержит несколько <p>, обрабатываем каждый отдельно.
        final blocks = _parseBlockOrMulti(elem: node);
        for (final b in blocks) {
          _allParagraphs.add(b);
        }
      } else {
        // Рекурсивный обход дочерних узлов
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
  /// то возвращаем список ParagraphBlock, по одному для каждого <p>.
  /// Если вложенных <p> нет, возвращаем один блок.
  List<ParagraphBlock> _parseBlockOrMulti({required XmlElement elem}) {
    final tag = elem.name.local.toLowerCase();
    final pElements = elem.findElements('p').toList();
    if (pElements.isNotEmpty) {
      final result = <ParagraphBlock>[];
      for (final p in pElements) {
        // Для text-author устанавливаем выравнивание вправо.
        CustomTextAlign align = (tag == 'text-author')
            ? CustomTextAlign.right
            : (tag == 'title' || tag == 'subtitle')
            ? CustomTextAlign.center
            : CustomTextAlign.left;
        final block = _parseParagraph(p, style: _decideStyleFor(tag))?.copyWith(
          textAlign: align,
          firstLineIndent: (tag == 'p') ? 20 : 0,
          paragraphSpacing: 15,
        );
        if (block != null) {
          result.add(block);
        }
      }
      return result;
    } else {
      // Если нет вложенных <p>, обрабатываем элемент как единый блок.
      return [_parseBlock(elem)!];
    }
  }

  /// Выбор стиля в зависимости от тега.
  TextStyle _decideStyleFor(String tag) {
    switch (tag) {
      case 'title':
        return StylesConfig.titleFont;
      case 'subtitle':
        return StylesConfig.subtitleFont;
      case 'text-author':
        return StylesConfig.baseText; // можно задать отдельный стиль для автора
      default:
        return StylesConfig.baseText;
    }
  }

  /// Обрабатывает элемент как единый блок (если он не содержит вложенных <p>).
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
        return _parseParagraph(elem, style: StylesConfig.baseText)?.copyWith(
          textAlign: CustomTextAlign.right,
          firstLineIndent: 20,
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

  ParagraphBlock? _parseParagraph(XmlElement elem, {TextStyle? style}) {
    final inlines = <InlineElement>[];
    final baseStyle = style ?? StylesConfig.baseText;

    // Если элемент является <image> без дочерних элементов.
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
