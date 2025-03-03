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

/// Пример FB2-парсера, где:
/// 1) Тег <p> всегда считается блочным элементом (с новой строки).
/// 2) Абзацы оформляются более читабельно: с отступами, расстоянием между абзацами и т.д.
/// 3) Дополнительные обёртки вокруг <p> (например, <span>) не превращают <p> в inline.
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

  /// Инициализация: загрузка файла, парсинг XML и рекурсивная обработка узлов.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _fb2Content = await rootBundle.loadString(assetPath);
    final document = XmlDocument.parse(_fb2Content!);

    _parseBinaries(document);

    // Обходим все <body> и рекурсивно обрабатываем.
    final bodies = document.findAllElements('body');
    for (final body in bodies) {
      _processNode(body);
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

  /// Извлекаем бинарные данные (картинки) и кладём в кэш.
  void _parseBinaries(XmlDocument document) {
    final binaries = document.findAllElements('binary');
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
    ui.decodeImageFromList(data, (img) {
      if (img != null) {
        completer.complete(img);
      } else {
        completer.completeError('Failed to decode image');
      }
    });
    return completer.future;
  }

  /// Рекурсивно обходим XML-узлы. Если встречаем <p> – парсим как блочный абзац.
  void _processNode(XmlNode node) {
    if (node is XmlText) {
      // Пустой текст игнорируем
      if (node.text.trim().isEmpty) return;
    } else if (node is XmlComment) {
      return;
    } else if (node is XmlElement) {
      final tag = node.name.local.toLowerCase();

      if (tag == 'section') {
        // Обрабатываем содержимое секции.
        for (final child in node.children) {
          _processNode(child);
        }
      } else if (tag == 'empty-line') {
        // Пустая строка (абзац с символом \n).
        final emptyBlock = ParagraphBlock(
          inlineElements: [TextInlineElement("\n", StylesConfig.baseText)],
          textAlign: CustomTextAlign.left,
          textDirection: CustomTextDirection.ltr,
          firstLineIndent: 0,
          paragraphSpacing: 10,
          minimumLines: 1,
          breakable: false,
        );
        _allParagraphs.add(emptyBlock);
      } else if (tag == 'p') {
        // Важный момент: <p> ВСЕГДА трактуем как блочный элемент с новой строки.
        final block = _parsePAsBlock(node);
        if (block != null) {
          _allParagraphs.add(block);
        }
      } else if (_isBlockElement(tag)) {
        // Если это другой блочный элемент (<title>, <subtitle>, <poem> и т.д.),
        // обрабатываем как блок
        final block = _parseBlock(node);
        if (block != null) {
          _allParagraphs.add(block);
        }
      } else {
        // Для всего остального – рекурсивный обход
        for (final child in node.children) {
          _processNode(child);
        }
      }
    }
  }

  /// Определяем, какие теги считаются блочными, кроме <p>.
  bool _isBlockElement(String tag) {
    const blockTags = {
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

  /// Парсим элемент <p> как блочный абзац.
  /// Даже если внутри <p> есть обёртки (span, i, em и т.д.), мы собираем весь текст в абзац.
  ParagraphBlock? _parsePAsBlock(XmlElement pElement) {
    final inlines = <InlineElement>[];
    final baseStyle = StylesConfig.baseText; // можно расширить или переопределить

    // Рекурсивная функция, собирающая текстовые узлы внутри <p>.
    void visit(XmlNode node, TextStyle currentStyle) {
      if (node is XmlText) {
        final raw = node.text.replaceAll(RegExp(r'\s+'), ' ');
        if (raw.isNotEmpty) {
          final hyph = hyphenator.hyphenate(raw);
          inlines.add(TextInlineElement(hyph, currentStyle));
        }
      } else if (node is XmlElement) {
        final localTag = node.name.local.toLowerCase();
        // Обрабатываем стили
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
          // Обработка изображения внутри <p>
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
          // Любые другие теги (span, custom и т.д.) – рекурсивный обход
          for (final child in node.children) {
            visit(child, currentStyle);
          }
        }
      }
    }

    // Запускаем обход содержимого <p>
    for (final child in pElement.children) {
      visit(child, baseStyle);
    }

    if (inlines.isEmpty) return null;

    // Возвращаем абзац, делая его более читабельным:
    // - Текст выравниваем влево (можно изменить)
    // - Отступ первой строки 20
    // - Расстояние между абзацами 15
    // - breakable = false, чтобы не разбивать внутри <p>, если не нужно
    return ParagraphBlock(
      inlineElements: inlines,
      textAlign: CustomTextAlign.left,
      textDirection: CustomTextDirection.ltr,
      firstLineIndent: 20,
      paragraphSpacing: 15,
      minimumLines: 1,
      breakable: false,
    );
  }

  /// Парсим другие блочные элементы (кроме <p>).
  ParagraphBlock? _parseBlock(XmlElement element) {
    final tag = element.name.local.toLowerCase();
    switch (tag) {
      case 'image':
        return _parseParagraph(element, style: StylesConfig.baseText)
            ?.copyWith(textAlign: CustomTextAlign.center, firstLineIndent: 0);
      case 'coverpage':
        for (final imgElem in element.findElements('image')) {
          final pb = _parseParagraph(imgElem, style: StylesConfig.coverImageStyle);
          if (pb != null) return pb;
        }
        return null;
      case 'annotation':
      case 'poem':
      case 'text-author':
        return _parseParagraph(element, style: StylesConfig.baseText);
      case 'epigraph':
        return _parseParagraph(element, style: StylesConfig.epigraph)
            ?.copyWith(breakable: true);
      case 'title':
      // Если в title есть несколько <p>, объединяем их
        return _parseMultiParagraph(element, StylesConfig.titleFont, CustomTextAlign.center);
      case 'subtitle':
        return _parseMultiParagraph(element, StylesConfig.subtitleFont, CustomTextAlign.center);
      default:
        return _parseParagraph(element, style: StylesConfig.baseText)
            ?.copyWith(textAlign: CustomTextAlign.left, firstLineIndent: 0);
    }
  }

  /// Парсим элемент, в котором может быть несколько <p> (например, <title>).
  ParagraphBlock? _parseMultiParagraph(XmlElement element, TextStyle style, CustomTextAlign align) {
    final pElems = element.findElements('p');
    if (pElems.isEmpty) return null;

    // Собираем несколько <p> в один ParagraphBlock
    final combinedInlines = <InlineElement>[];
    for (final pElem in pElems) {
      final block = _parsePAsBlock(pElem);
      if (block != null) {
        // Добавляем содержимое
        combinedInlines.addAll(block.inlineElements);
        // Добавляем перевод строки между <p>
        combinedInlines.add(TextInlineElement("\n", style));
      }
    }
    if (combinedInlines.isNotEmpty && combinedInlines.last is TextInlineElement) {
      // Удалим лишний перевод строки в конце
      final lastElem = combinedInlines.last as TextInlineElement;
      if (lastElem.text.trim().isEmpty) {
        combinedInlines.removeLast();
      }
    }

    if (combinedInlines.isEmpty) return null;
    return ParagraphBlock(
      inlineElements: combinedInlines,
      textAlign: align,
      textDirection: CustomTextDirection.ltr,
      firstLineIndent: 0,
      paragraphSpacing: 15,
      minimumLines: 1,
      breakable: false,
    );
  }

  /// Универсальный метод для парсинга блоковых элементов (если не <p>).
  ParagraphBlock? _parseParagraph(XmlElement elem, {TextStyle? style}) {
    final inlines = <InlineElement>[];
    final baseStyle = style ?? StylesConfig.baseText;

    // Если это тег image без дочерних элементов
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
      // Рекурсивный обход содержимого
      void visit(XmlNode node, TextStyle currentStyle) {
        if (node is XmlText) {
          final raw = node.text.replaceAll(RegExp(r'\s+'), ' ');
          if (raw.isNotEmpty) {
            final hyph = hyphenator.hyphenate(raw);
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
    // Возвращаем абзац
    return ParagraphBlock(
      inlineElements: inlines,
      textAlign: CustomTextAlign.left,
      textDirection: CustomTextDirection.ltr,
      firstLineIndent: 20,
      paragraphSpacing: 15,
      minimumLines: 1,
      breakable: false,
    );
  }
}
