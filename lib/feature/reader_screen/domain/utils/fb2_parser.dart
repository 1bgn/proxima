// fb2_parser.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/inline_elements.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/custom_text_engine/paragraph_block.dart';
import 'package:xml/xml.dart';
import 'package:flutter/material.dart';


import 'hyphenator.dart';

class FB2Parser {
  final Hyphenator hyphenator;

  FB2Parser(this.hyphenator);

  /// Парсит FB2 из указанного asset-пути (например, 'assets/book.fb2')
  /// Возвращает список "глав" (chapterList), где каждая глава — список ParagraphBlock.
  Future<List<ChapterData>> parseFB2FromAssets(String assetPath) async {
    final content = await rootBundle.loadString(assetPath);
    return parseFB2(content);
  }

  /// Основной метод разбора FB2-строки.
  /// Возвращает список глав (ChapterData).
  Future<List<ChapterData>> parseFB2(String fb2Text) async {
    final document = XmlDocument.parse(fb2Text);

    // Собираем все binary (картинки) в Map
    final binaryMap = <String, Future<ui.Image>>{};
    for (final bin in document.findAllElements('binary')) {
      final idAttr = bin.getAttribute('id');
      if (idAttr == null) continue;

      // FB2 обычно хранит Base64
      final base64Data = bin.innerText.trim();
      final decoded = base64.decode(base64Data);

      // Генерируем Future<ui.Image> (через decodeImageFromList)
      final futureImage = decodeImageFromListAsync(decoded);
      binaryMap[idAttr] = futureImage;
    }

    // Ищем основное <body>. Часто бывает один <body>, но может быть и несколько.
    // Для примера возьмём самый первый <body>.
    final body = document.findAllElements('body').isEmpty
        ? null
        : document.findAllElements('body').first;
    if (body == null) {
      // Нет тела => нет глав
      return [];
    }

    // Каждая <section> будет считаться "главой"
    final sections = body.findAllElements('section');
    final chapters = <ChapterData>[];

    for (final section in sections) {
      final chapterParagraphs = <ParagraphBlock>[];

      // Попробуем получить заголовок <title>, часто внутри <section><title><p>Заголовок</p></title>
      final titleElem = section.findElements('title').isNotEmpty
          ? section.findElements('title').first
          : null;
      if (titleElem != null) {
        final titleText = titleElem.findElements('p').map((e) => e.text).join(' ');
        if (titleText.isNotEmpty) {
          // Прогоняем через hyphenator
          final hyphText = hyphenator.hyphenate(titleText);
          final paragraph = createParagraphBlock(
            hyphText,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          );
          chapterParagraphs.add(paragraph);
        }
      }

      // Парсим все абзацы <p>, плюс поддержка под-тегов типа <strong>, <emphasis> и т.п.
      for (final p in section.findElements('p')) {
        final paraBlock = parseParagraphElement(p, binaryMap);
        if (paraBlock != null) {
          chapterParagraphs.add(paraBlock);
        }
      }

      // Пример: Если надо поддерживать и другие теги (например, <subtitle>, <poem>),
      // мы могли бы аналогичным способом их обработать.

      // Если в секции есть вложенные <section>, можно рекурсивно парсить;
      // но здесь для упрощения пропустим.
      // ...

      // Если глава не пуста, добавим в список
      if (chapterParagraphs.isNotEmpty) {
        chapters.add(ChapterData(chapterParagraphs));
      }
    }

    // Дожидаемся декодирования всех картинок (чтобы потом не было проблем при верстке).
    // Но, возможно, вам удобнее декодировать "на лету" позже. Здесь — пример синхронизации.
    await Future.wait(binaryMap.values);

    return chapters;
  }

  /// Парсит один элемент <p> (со всеми вложенными).
  /// Возвращает ParagraphBlock со списком InlineElement.
  ParagraphBlock? parseParagraphElement(XmlElement pElem, Map<String, Future<ui.Image>> binaryMap) {
    // Может быть внутри текста ещё <strong>, <emphasis>, <image>, и т.д.
    // Для упрощения соберём всё в список инлайн-элементов.
    final inlineElements = <InlineElement>[];

    // Функция рекурсивного обхода вложенных нод, чтобы собрать текст/картинки
    void visitNode(XmlNode node, TextStyle currentStyle) {
      if (node is XmlText) {
        // Текстовая нода
        final rawText = node.text;
        final trimmed = rawText.replaceAll('\n', ' ').replaceAll('\r', ' ');
        if (trimmed.trim().isNotEmpty) {
          // Пропустим через hyphenator
          final hyphText = hyphenator.hyphenate(trimmed);
          inlineElements.add(TextInlineElement(hyphText, currentStyle));
        }
      } else if (node is XmlElement) {
        // Проверим тег
        switch (node.name.local.toLowerCase()) {
          case 'strong':
            final newStyle = currentStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
            node.children.forEach((child) => visitNode(child, newStyle));
            break;
          case 'emphasis':
            final newStyle = currentStyle.merge(const TextStyle(fontStyle: FontStyle.italic));
            node.children.forEach((child) => visitNode(child, newStyle));
            break;
          case 'image':
          // <image l:href="#id" />
            final href = node.getAttribute('l:href') ?? node.getAttribute('href');
            if (href != null && href.startsWith('#')) {
              final id = href.substring(1); // убираем '#'
              if (binaryMap.containsKey(id)) {
                // Для примера зададим фиксированные размеры
                final futureImage = binaryMap[id]!;
                // Пока не можем сразу вставить ui.Image (это Future),
                // поэтому вставим некий «заглушечный» inlineElement,
                // а реально картинку подставим после получения.
                // Но для наглядности в данном примере можно дожидаться futureImage сразу.
                // Чтобы не усложнять, дождёмся здесь синхронно (await),
                // но учтите, что метод тогда нужно сделать async.
              }
            }
            break;
          default:
          // Если что-то другое, рекурсивно обходим
            node.children.forEach((child) => visitNode(child, currentStyle));
            break;
        }
      }
    }

    visitNode(pElem, const TextStyle(fontSize: 16.0, color: Colors.black));

    if (inlineElements.isEmpty) return null;

    // Создаём абзац
    return ParagraphBlock(
      inlineElements: inlineElements,
      textAlign: null, // Пусть глобальный возьмётся
      textDirection: CustomTextDirection.ltr,
      firstLineIndent: 0.0,
      paragraphSpacing: 10.0,
      minimumLines: 1,
    );
  }

  /// Упрощённая функция: создаёт ParagraphBlock из строки
  ParagraphBlock createParagraphBlock(String text, {TextStyle? style}) {
    final st = style ?? const TextStyle(fontSize: 16, color: Colors.black);
    final inline = TextInlineElement(text, st);
    return ParagraphBlock(
      inlineElements: [inline],
      textAlign: null,
      textDirection: CustomTextDirection.ltr,
      firstLineIndent: 0.0,
      paragraphSpacing: 10.0,
      minimumLines: 1,
    );
  }

  /// Декодирование [Uint8List] в ui.Image через Future
  Future<ui.Image> decodeImageFromListAsync(Uint8List data) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(data, (img) {
      completer.complete(img);
    },);
    return completer.future;
  }
}

/// Хранит список ParagraphBlock, относящихся к одной главе.
class ChapterData {
  final List<ParagraphBlock> paragraphs;

  ChapterData(this.paragraphs);
}
