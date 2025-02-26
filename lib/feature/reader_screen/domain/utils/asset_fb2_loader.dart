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
    _parseBinaries(doc);
    final titleInfo = doc.findAllElements('title-info').isNotEmpty
        ? doc.findAllElements('title-info').first
        : null;
    if (titleInfo != null) {
      _processTitleInfo(titleInfo);
    }
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

  void _processTitleInfo(XmlElement titleInfo) {
    final bookTitles = titleInfo.findElements('book-title');
    for (final bt in bookTitles) {
      final pb = _parseParagraph(bt, style: StylesConfig.boldHeader);
      if (pb != null) _allParagraphs.add(pb);
    }
    final subtitles = titleInfo.findElements('subtitle');
    for (final st in subtitles) {
      final pb = _parseParagraph(st, style: StylesConfig.subtitle);
      if (pb != null) _allParagraphs.add(pb);
    }
    final textAuthors = titleInfo.findElements('text-author');
    if (textAuthors.isNotEmpty) {
      for (final ta in textAuthors) {
        final pb = _parseParagraph(ta, style: StylesConfig.textAuthor);
        if (pb != null) _allParagraphs.add(pb);
      }
    } else {
      final authors = titleInfo.findElements('author');
      for (final author in authors) {
        final name = author.text.trim();
        if (name.isNotEmpty) {
          _allParagraphs.add(ParagraphBlock(
            inlineElements: [TextInlineElement(name, StylesConfig.textAuthor)],
            textAlign: null,
            textDirection: CustomTextDirection.ltr,
            firstLineIndent: 0,
            paragraphSpacing: 10,
            minimumLines: 1,
          ));
        }
      }
    }
  }

  void _parseAllParagraphs(XmlDocument doc) {
    final body = doc.descendants.whereType<XmlElement>().firstWhere(
          (e) => e.name.local.toLowerCase() == 'body',
      orElse: () => XmlElement(XmlName('body')),
    );
    if (body.children.isEmpty) return;
    for (final tag in ['annotation', 'epigraph']) {
      final elems = body.descendants.whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == tag);
      for (final elem in elems) {
        _processSectionLike(elem, tag);
      }
    }
    final poems = body.descendants.whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'poem');
    for (final poem in poems) {
      _processPoem(poem);
    }
    final pElems = body.descendants.whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'p' &&
        !e.ancestors.any((a) {
          if (a is XmlElement) {
            final lname = a.name.local.toLowerCase();
            return ['annotation', 'epigraph', 'poem', 'stanza', 'title', 'subtitle', 'text-author'].contains(lname);
          }
          return false;
        }))
        .toList();
    for (final p in pElems) {
      final pb = _parseParagraph(p, style: StylesConfig.baseText);
      if (pb != null) _allParagraphs.add(pb);
    }
  }

  void _processSectionLike(XmlElement elem, String tag) {
    TextStyle style;
    CustomTextAlign align = CustomTextAlign.left;
    if (tag == 'annotation') {
      style = StylesConfig.annotation;
    } else if (tag == 'epigraph') {
      style = StylesConfig.epigraph;
      align = CustomTextAlign.right;
    } else {
      style = StylesConfig.baseText;
    }
    final pElems = elem.descendants.whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'p');
    for (final p in pElems) {
      final pb = _parseParagraph(p, style: style);
      if (pb != null) {
        // Для эпиграфа ограничиваем ширину до 2/3 от глобальной ширины
        final styledPb = ParagraphBlock(
          inlineElements: pb.inlineElements,
          textAlign: align,
          textDirection: pb.textDirection,
          firstLineIndent: pb.firstLineIndent,
          paragraphSpacing: pb.paragraphSpacing,
          minimumLines: pb.minimumLines,
          maxWidth: tag == 'epigraph' ? 0.66 : null,
        );
        _allParagraphs.add(styledPb);
      }
    }
  }

  void _processPoem(XmlElement poemElem) {
    final titleElems = poemElem.descendants.whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'title');
    for (final title in titleElems) {
      final pElems = title.descendants.whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'p');
      for (final p in pElems) {
        final pb = _parseParagraph(p, style: StylesConfig.boldHeader);
        if (pb != null) _allParagraphs.add(pb);
      }
    }
    final subtitleElems = poemElem.descendants.whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'subtitle');
    for (final sub in subtitleElems) {
      final pb = _parseParagraph(sub, style: StylesConfig.subtitle);
      if (pb != null) _allParagraphs.add(pb);
    }
    final stanzaElems = poemElem.descendants.whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'stanza');
    for (final stanza in stanzaElems) {
      final pElems = stanza.descendants.whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'p');
      for (final p in pElems) {
        final pb = _parseParagraph(p, style: StylesConfig.epigraph);
        if (pb != null) {
          final styledPb = ParagraphBlock(
            inlineElements: pb.inlineElements,
            textAlign: CustomTextAlign.right,
            textDirection: pb.textDirection,
            firstLineIndent: pb.firstLineIndent,
            paragraphSpacing: pb.paragraphSpacing,
            minimumLines: pb.minimumLines,
            maxWidth: 0.66,
          );
          _allParagraphs.add(styledPb);
        }
      }
    }
  }

  ParagraphBlock? _parseParagraph(XmlElement elem, {TextStyle? style}) {
    final inlines = <InlineElement>[];
    final baseStyle = style ?? StylesConfig.baseText;
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
          node.children.forEach((child) => visit(child, newStyle));
        } else if (tag == 'i' || tag == 'em' || tag == 'emphasis') {
          final newStyle = currentStyle.copyWith(fontStyle: FontStyle.italic);
          node.children.forEach((child) => visit(child, newStyle));
        } else if (tag == 'link') {
          final linkUrl = node.getAttribute('l:href') ?? node.getAttribute('href') ?? '';
          String accumulated = '';
          final List<InlineElement> linkElems = [];
          void visitLink(XmlNode n, TextStyle s) {
            if (n is XmlText) {
              final txt = n.text.replaceAll(RegExp(r'\s+'), ' ');
              if (txt.isNotEmpty) {
                accumulated += txt;
                linkElems.add(TextInlineElement(txt, s));
              }
            } else if (n is XmlElement) {
              final t = n.name.local.toLowerCase();
              if (t == 'b' || t == 'strong') {
                final s2 = s.copyWith(fontWeight: FontWeight.bold);
                n.children.forEach((child) => visitLink(child, s2));
              } else if (t == 'i' || t == 'em' || t == 'emphasis') {
                final s2 = s.copyWith(fontStyle: FontStyle.italic);
                n.children.forEach((child) => visitLink(child, s2));
              } else {
                n.children.forEach((child) => visitLink(child, s));
              }
            }
          }
          node.children.forEach((child) => visitLink(child, currentStyle));
          if (accumulated.isNotEmpty) {
            linkElems.insert(0, TextInlineElement(accumulated, currentStyle));
            inlines.add(InlineLinkElement(accumulated, currentStyle, linkUrl));
          }
        } else if (tag == 'image') {
          final href = node.getAttribute('l:href') ?? node.getAttribute('href');
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
        } else if (tag == 'subtitle' || tag == 'text-author') {
          TextStyle newStyle;
          if (tag == 'subtitle') {
            newStyle = StylesConfig.subtitle;
          } else {
            newStyle = StylesConfig.textAuthor;
          }
          node.children.forEach((child) => visit(child, newStyle));
        } else {
          node.children.forEach((child) => visit(child, currentStyle));
        }
      }
    }
    elem.children.forEach((child) => visit(child, baseStyle));
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
