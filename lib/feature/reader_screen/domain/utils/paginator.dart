import 'package:flutter/material.dart';
import 'fb2_parser.dart';

/// Пагинатор — разбивает fb2-документ на страницы с учётом размеров экрана.
/// Каждая глава начинается с новой страницы.
/// Функция hyphenate (обработка мягких переносов) передаётся как callback.
class Paginator {
  final Fb2Document document;
  final TextStyle textStyle;
  final Size pageSize;
  final String Function(String) hyphenate;

  Paginator({
    required this.document,
    required this.textStyle,
    required this.pageSize,
    required this.hyphenate,
  });

  /// Формирует список виджетов-страниц
  List<Widget> paginate() {
    List<Widget> pages = [];
    for (var chapter in document.chapters) {
      pages.addAll(_paginateChapter(chapter));
    }
    return pages;
  }

  /// Разбиваем конкретную главу на страницы
  List<Widget> _paginateChapter(Chapter chapter) {
    List<Widget> pages = [];
    List<Widget> currentWidgets = [];
    double currentHeight = 0;

    // Заголовок главы, если есть
    if (chapter.title.isNotEmpty) {
      var titleTextStyle = textStyle.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: (textStyle.fontSize ?? 16) + 4,
      );
      double titleHeight = _estimateTextHeight(
        chapter.title,
        titleTextStyle,
        pageSize.width,
      );
      if (currentHeight + titleHeight > pageSize.height) {
        pages.add(_buildPage(currentWidgets));
        currentWidgets = [];
        currentHeight = 0;
      }
      currentWidgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: HyphenatedTextWidget(
            text: chapter.title,
            style: titleTextStyle,
            maxWidth: pageSize.width,
          ),
        ),
      );
      currentHeight += titleHeight + 8;
    }

    // Перебираем элементы главы (параграфы, изображения)
    for (var element in chapter.elements) {
      if (element is Paragraph) {
        // Обработка мягких переносов
        String hyphenatedText = hyphenate(element.text);
        double estimatedHeight = _estimateTextHeight(
          hyphenatedText,
          textStyle,
          pageSize.width,
        );

        // Если не влезает — переносим на новую страницу
        if (currentHeight + estimatedHeight > pageSize.height) {
          pages.add(_buildPage(currentWidgets));
          currentWidgets = [];
          currentHeight = 0;
        }

        currentWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: HyphenatedTextWidget(
              text: hyphenatedText,
              style: textStyle,
              maxWidth: pageSize.width,
            ),
          ),
        );
        currentHeight += estimatedHeight + 8.0;

      } else if (element is Fb2Image) {
        // Изображение с масштабированием
        // Например, пусть занимает высоту в половину экрана
        double imageHeight = pageSize.height / 2;
        if (currentHeight + imageHeight > pageSize.height) {
          pages.add(_buildPage(currentWidgets));
          currentWidgets = [];
          currentHeight = 0;
        }

        currentWidgets.add(
          Container(
            width: pageSize.width,
            height: imageHeight,
            margin: EdgeInsets.only(bottom: 8.0),
            alignment: Alignment.center,
            child: (document.images[element.id] != null &&
                document.images[element.id]!.isNotEmpty)
                ? Image.memory(
              document.images[element.id]!,
              fit: BoxFit.contain,
            )
                : Container(
              color: Colors.grey,
              width: pageSize.width,
              height: imageHeight,
            ),
          ),
        );
        currentHeight += imageHeight + 8.0;
      }
    }

    if (currentWidgets.isNotEmpty) {
      pages.add(_buildPage(currentWidgets));
    }

    return pages;
  }

  /// Создаём «страницу» заданного размера с белым фоном и паддингом,
  /// чтобы текст выглядел «как на предыдущих экранах».
  Widget _buildPage(List<Widget> widgets) {
    return Container(
      width: pageSize.width,
      height: pageSize.height,
      color: Colors.white,
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      ),
    );
  }

  /// Оцениваем высоту текста (многострочного) с помощью TextPainter
  double _estimateTextHeight(String text, TextStyle style, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: null,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: maxWidth);
    return tp.size.height;
  }
}

/// Виджет для вывода многострочного текста с визуализацией мягких переносов.
/// Основной текст отрисовывается обычным Text,
/// а поверх — CustomPaint, который рисует дефисы у правого края, если есть soft hyphen.
class HyphenatedTextWidget extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double maxWidth;

  const HyphenatedTextWidget({
    Key? key,
    required this.text,
    required this.style,
    required this.maxWidth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Основной многострочный текст
        Text(
          text,
          style: style,
          softWrap: true,
        ),
        // Слой для рисования дефисов
        Positioned.fill(
          child: CustomPaint(
            painter: HyphenPainter(
              text: text,
              style: style,
              maxWidth: maxWidth,
            ),
          ),
        ),
      ],
    );
  }
}

/// CustomPainter для отрисовки «дефисов» в местах мягких переносов (\u00AD).
/// Мы делаем упрощённый вариант: если символ \u00AD попадает за пределы
/// (maxWidth - threshold), рисуем короткую чёрточку на baseline.
class HyphenPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final double maxWidth;

  HyphenPainter({
    required this.text,
    required this.style,
    required this.maxWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      maxLines: null, // многострочный
    );
    textPainter.layout(maxWidth: maxWidth);

    const softHyphen = "\u00AD";
    // Порог, когда символ «слишком близко к правому краю»
    const double threshold = 10.0;

    int index = 0;
    while (true) {
      index = text.indexOf(softHyphen, index);
      if (index == -1) break;

      // Определяем позицию символа (координаты каретки)
      final pos = textPainter.getOffsetForCaret(
        TextPosition(offset: index),
        Rect.zero,
      );
      // Если x-координата >= (maxWidth - threshold),
      // считаем, что символ «выпал» за пределы строки
      if (pos.dx >= maxWidth - threshold) {
        final paint = Paint()
          ..color = Colors.black
          ..strokeWidth = 1.0;
        final dashWidth = (style.fontSize ?? 16) / 2;

        // Рисуем короткую чёрточку от pos до pos+dashWidth
        // pos.dy обычно соответствует baseline символа в многострочном тексте.
        canvas.drawLine(
          pos,
          pos.translate(dashWidth, 0),
          paint,
        );
      }
      index++;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
