// fb2_parser.dart
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

class FB2Parser {
  final Hyphenator hyphenator;

  // Хранилище бинарных данных (картинок)
  late final Map<String, Future<ui.Image>> _binaryImages;

  FB2Parser(this.hyphenator);

  /// Парсим FB2 из assets.
  Future<List<ChapterData>> parseFB2FromAssets(String assetPath) async {
    final content = await rootBundle.loadString(assetPath);
    return parseFB2(content);
  }

  /// Парсим текст FB2
  Future<List<ChapterData>> parseFB2(String fb2Text) async {
    final doc = XmlDocument.parse(fb2Text);

    // Собираем все <binary>
    _binaryImages = {};
    for (final bin in doc.findAllElements('binary')) {
      final idAttr = bin.getAttribute('id');
      if (idAttr == null) continue;
      final b64 = bin.innerText.trim();
      final decoded = base64.decode(b64);
      final futureImage = decodeImageFromListAsync(decoded);
      _binaryImages[idAttr] = futureImage;
    }

    // Ищем <body>
    final body = doc.findAllElements('body').isNotEmpty
        ? doc.findAllElements('body').first
        : null;
    if (body == null) {
      return [];
    }

    // Собираем главы как <section>. При желании можно расширять на другие <body>.
    final sections = body.findAllElements('section');
    final chapters = <ChapterData>[];

    for (final section in sections) {
      final paragraphs = <ParagraphBlock>[];

      // title
      final titleElem = section.findElements('title').isNotEmpty
          ? section.findElements('title').first
          : null;
      if (titleElem != null) {
        final titlePars = _parseTitleElement(titleElem);
        paragraphs.addAll(titlePars);
      }

      // основной контент (включая <p>, <subtitle>, <poem>, <footnote>)
      _parseSectionContent(section, paragraphs);

      if (paragraphs.isNotEmpty) {
        chapters.add(ChapterData(paragraphs));
      }
    }

    // Дождёмся декодирования всех картинок
    await Future.wait(_binaryImages.values);

    return chapters;
  }

  /// Разбор <title>: может содержать <p>, <subtitle>, etc.
  List<ParagraphBlock> _parseTitleElement(XmlElement titleElem) {
    final paragraphs = <ParagraphBlock>[];

    // Как правило, <title> содержит <p>, но бывает и <subtitle>.
    // Простым способом: всё, что не <p>, считаем частью одного абзаца?
    for (final node in titleElem.children) {
      if (node is XmlElement && node.name.local.toLowerCase() == 'p') {
        final pBlock = _parseParagraph(node);
        if (pBlock != null) paragraphs.add(pBlock);
      } else if (node is XmlElement && node.name.local.toLowerCase() == 'subtitle') {
        final subBlock = _parseSubtitle(node);
        if (subBlock != null) paragraphs.add(subBlock);
      }
      // можно расширять
    }

    // Если ничего не нашли, возможно есть текст напрямую
    // ...

    // Условно считаем все параграфы в titleElem — это заголовок главы
    for (final pb in paragraphs) {
      // можно придать им особый стиль
      // например, fontWeight.bold
    }

    return paragraphs;
  }

  /// Разбор основной части <section> (помимо <title>)
  void _parseSectionContent(XmlElement sectionElem, List<ParagraphBlock> paragraphs) {
    // p
    for (final p in sectionElem.findElements('p')) {
      final pb = _parseParagraph(p);
      if (pb != null) {
        paragraphs.add(pb);
      }
    }

    // subtitle
    for (final sub in sectionElem.findElements('subtitle')) {
      final subBlock = _parseSubtitle(sub);
      if (subBlock != null) paragraphs.add(subBlock);
    }

    // poem
    for (final poemElem in sectionElem.findElements('poem')) {
      final poemPars = _parsePoem(poemElem);
      paragraphs.addAll(poemPars);
    }

    // footnotes
    for (final footnoteElem in sectionElem.findElements('footnote')) {
      final footBlocks = _parseFootnote(footnoteElem);
      paragraphs.addAll(footBlocks);
    }

    // Возможно, вложенные <section>? Можно рекурсивно.
    for (final subSection in sectionElem.findElements('section')) {
      _parseSectionContent(subSection, paragraphs);
    }
  }

  ParagraphBlock? _parseParagraph(XmlElement pElem) {
    final inlines = <InlineElement>[];

    // Рекурсивная функция
    void visit(XmlNode node, TextStyle style) {
      if (node is XmlText) {
        final raw = _cleanText(node.text);
        if (raw.isNotEmpty) {
          final hyph = hyphenator.hyphenate(raw);
          inlines.add(TextInlineElement(hyph, style));
        }
      } else if (node is XmlElement) {
        final name = node.name.local.toLowerCase();
        switch (name) {
          case 'strong':
            final st = style.merge(const TextStyle(fontWeight: FontWeight.bold));
            node.children.forEach((child) => visit(child, st));
            break;
          case 'emphasis':
          case 'i':
            final st2 = style.merge(const TextStyle(fontStyle: FontStyle.italic));
            node.children.forEach((child) => visit(child, st2));
            break;
          case 'image':
            final imgElem = _parseImageElement(node, style);
            if (imgElem != null) inlines.add(imgElem);
            break;
          default:
            node.children.forEach((child) => visit(child, style));
            break;
        }
      }
    }

    final baseStyle = const TextStyle(fontSize: 16, color: Colors.black);
    pElem.children.forEach((child) => visit(child, baseStyle));

    if (inlines.isEmpty) return null;

    return ParagraphBlock(
      inlineElements: inlines,
      textAlign: null,
      textDirection: CustomTextDirection.ltr,
      firstLineIndent: 0.0,
      paragraphSpacing: 10.0,
      minimumLines: 1,
    );
  }

  ParagraphBlock? _parseSubtitle(XmlElement subElem) {
    final text = subElem.text.trim();
    if (text.isEmpty) return null;
    final cleaned = _cleanText(text);
    final hyph = hyphenator.hyphenate(cleaned);

    return ParagraphBlock(
      inlineElements: [
        TextInlineElement(hyph, const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
      textAlign: null,
      textDirection: CustomTextDirection.ltr,
      firstLineIndent: 0.0,
      paragraphSpacing: 10.0,
      minimumLines: 1,
    );
  }

  List<ParagraphBlock> _parsePoem(XmlElement poemElem) {
    final result = <ParagraphBlock>[];
    // В <poem> могут быть <stanza>, <title> и т.д.
    // Упрощённо: каждое <stanza> -> несколько <p>
    for (final stanza in poemElem.findElements('stanza')) {
      for (final p in stanza.findElements('p')) {
        final pb = _parseParagraph(p);
        if (pb != null) {
          result.add(pb);
        }
      }
    }
    return result;
  }

  List<ParagraphBlock> _parseFootnote(XmlElement footElem) {
    // Условно: считаем каждый <p> в footnote
    final result = <ParagraphBlock>[];
    for (final p in footElem.findElements('p')) {
      final pb = _parseParagraph(p);
      if (pb != null) result.add(pb);
    }
    // Можно пометить footnote особым стилем (мелкий шрифт)
    for (final pb in result) {
      // Условно
      for (final inl in pb.inlineElements) {
        if (inl is TextInlineElement) {
          final oldStyle = inl.style;
          final newStyle = oldStyle.copyWith(fontSize: (oldStyle.fontSize ?? 16) * 0.8);
          inl.style = newStyle; // Нужно сделать сеттер или пересоздать
        }
      }
    }
    return result;
  }

  InlineElement? _parseImageElement(XmlElement imgNode, TextStyle style) {
    // <image l:href="#ID"/>
    final href = imgNode.getAttribute('l:href') ?? imgNode.getAttribute('href');
    if (href == null || !href.startsWith('#')) {
      return null;
    }
    final id = href.substring(1); // убираем '#'
    if (!_binaryImages.containsKey(id)) {
      return null;
    }
    // Для примера пусть desiredWidth=200, desiredHeight=150
    // В реальном проекте лучше смотреть размеры из атрибутов
    return _ImagePlaceholderFuture(
      future: _binaryImages[id]!,
      style: style,
    );
  }

  /// Утилита: удаляем \u00AD, \u200B, \u00A0 и превращаем \s+ в пробел.
  String _cleanText(String raw) {
    var t = raw.replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceAll('\u00AD', '');
    t = t.replaceAll('\u200B', '');
    t = t.replaceAll('\u00A0', ' ');
    return t.trim();
  }

  Future<ui.Image> decodeImageFromListAsync(Uint8List data) {
    final comp = Completer<ui.Image>();
    ui.decodeImageFromList(data, (img) {
      if (img != null) {
        comp.complete(img);
      } else {
        comp.completeError('decodeImageFromList returned null');
      }
    });
    return comp.future;
  }
}

/// Простая обёртка, чтобы встроить Future<ui.Image> в InlineElement.
/// В реальном проекте лучше решать вопрос асинхронного рендера картинок иначе
/// (например, после получения декодированного ui.Image, перерисовать).
class _ImagePlaceholderFuture extends InlineElement {
  final Future<ui.Image> future;
  final TextStyle style; // Можно хранить для масштабирования?

  _ImagePlaceholderFuture({
    required this.future,
    required this.style,
  });

  ui.Image? _image;
  bool _loaded = false;

  @override
  void performLayout(double maxWidth) {
    // Если изображение ещё не загружено, ставим заглушку
    if (!_loaded) {
      width = 100;
      height = 80;
      baseline = height;
      // запускаем загрузку
      future.then((img) {
        _image = img;
        _loaded = true;
        // Надо вызвать перерисовку -> нужен доступ к RenderBox
        // В упрощённом варианте игнорируем.
      });
    } else {
      // уже есть _image
      final desiredWidth = 200.0;
      final desiredHeight = 150.0;
      final w = (desiredWidth > maxWidth) ? maxWidth : desiredWidth;
      width = w;
      height = desiredHeight;
      baseline = height;
    }
  }

  @override
  void paint(ui.Canvas canvas, Offset offset) {
    if (_image == null) {
      // Рисуем заглушку
      final rect = Rect.fromLTWH(offset.dx, offset.dy, width, height);
      final paint = Paint()..color = const Color(0x66CCCCCC);
      canvas.drawRect(rect, paint);
      // Можно написать "Loading..."
      return;
    } else {
      final image = _image!;
      final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      final dst = Rect.fromLTWH(offset.dx, offset.dy, width, height);
      canvas.drawImageRect(image, src, dst, Paint());
    }
  }
}

/// Описывает главу (раздел).
class ChapterData {
  final List<ParagraphBlock> paragraphs;
  ChapterData(this.paragraphs);
}
