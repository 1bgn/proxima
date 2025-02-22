import 'dart:typed_data';
import 'dart:convert';
import 'package:xml/xml.dart' as xml;

/// Модель fb2-документа
class Fb2Document {
  final List<Chapter> chapters;
  final Map<String, Uint8List> images;
  Fb2Document({required this.chapters, required this.images});
}

/// Глава книги
class Chapter {
  final String title;
  final List<Fb2Element> elements;
  Chapter({required this.title, required this.elements});
}

/// Абстрактный элемент книги
abstract class Fb2Element {}

/// Параграф текста
class Paragraph extends Fb2Element {
  final String text;
  Paragraph(this.text);
}

/// Изображение (ссылка на бинарные данные)
class Fb2Image extends Fb2Element {
  final String id;
  Fb2Image(this.id);
}

/// Парсер fb2. Принимает XML-содержимое книги и возвращает Fb2Document.
class Fb2Parser {
  final String fb2Content;
  Fb2Parser(this.fb2Content);

  Fb2Document parse() {
    final document = xml.parse(fb2Content);
    List<Chapter> chapters = [];
    Map<String, Uint8List> images = {};

    // Извлечение изображений (<binary>), декодирование base64
    for (var binary in document.findAllElements('binary')) {
      String? id = binary.getAttribute('id');
      final base64data = binary.text.trim();
      if (id != null && base64data.isNotEmpty) {
        try {
          images[id] = base64Decode(base64data);
        } catch (_) {
          images[id] = Uint8List(0); // fallback, если не удалось декодировать
        }
      }
    }

    // Обработка тела книги – главы находятся в тегах <section>
    for (var body in document.findAllElements('body')) {
      for (var section in body.findAllElements('section')) {
        String title = "";
        List<Fb2Element> elements = [];

        var titleElement = section.getElement('title');
        if (titleElement != null) {
          // Внутри <title> обычно <p>
          title = titleElement.text.trim();
        }

        for (var node in section.children) {
          if (node is xml.XmlElement) {
            if (node.name.local == 'p') {
              elements.add(Paragraph(node.text.trim()));
            } else if (node.name.local == 'image') {
              var href = node.getAttribute('href') ?? node.getAttribute('l:href');
              if (href != null && href.startsWith('#')) {
                String id = href.substring(1);
                elements.add(Fb2Image(id));
              }
            }
            // Дополнительная обработка других тегов fb2 при необходимости.
          }
        }

        chapters.add(Chapter(title: title, elements: elements));
      }
    }

    return Fb2Document(chapters: chapters, images: images);
  }
}
