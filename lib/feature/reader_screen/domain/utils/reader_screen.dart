import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fb2_parser.dart';
import 'paginator.dart';

/// Пара правил для мягких переносов
class HyphenPair {
  final String pattern;
  final int position;
  HyphenPair(this.pattern, this.position);
}

/// Класс Hyphenator вставляет символ \u00AD (soft hyphen)
/// в соответствии с заданными правилами.
class Hyphenator {
  final String x = "йьъ";
  final String g = "аеёиоуыэюяaeiouy";
  final String s = "бвгджзклмнпрстфхцчшщbcdfghjklmnpqrstvwxz";

  final List<HyphenPair> rules = [];

  Hyphenator() {
    // Пример правил — добавьте нужные
    rules.add(HyphenPair("xgg", 1));
    rules.add(HyphenPair("xgs", 1));
    rules.add(HyphenPair("xsg", 1));
    rules.add(HyphenPair("xss", 1));
    rules.add(HyphenPair("gssssg", 3));
    rules.add(HyphenPair("gsssg", 3));
    rules.add(HyphenPair("gsssg", 2));
    rules.add(HyphenPair("sgsg", 2));
    rules.add(HyphenPair("gssg", 2));
    rules.add(HyphenPair("sggg", 2));
    rules.add(HyphenPair("sggs", 2));
  }

  /// Вставка символов мягкого переноса (\u00AD) в текст
  String hyphenate(String text, {String hyphenateSymbol = "\u00AD"}) {
    final sb = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final c = text[i];
      if (x.contains(c)) {
        sb.write('x');
      } else if (g.contains(c)) {
        sb.write('g');
      } else if (s.contains(c)) {
        sb.write('s');
      } else {
        sb.write(c);
      }
    }
    String hyphenatedText = sb.toString();

    const splitter = '┼';

    for (final hp in rules) {
      int index = hyphenatedText.indexOf(hp.pattern);
      while (index != -1) {
        int actualIndex = index + hp.position;
        // вставляем splitter в «промежуточную» строку
        hyphenatedText = hyphenatedText.substring(0, actualIndex)
            + splitter
            + hyphenatedText.substring(actualIndex);
        // параллельно вставляем splitter в исходный text
        text = text.substring(0, actualIndex)
            + splitter
            + text.substring(actualIndex);
        index = hyphenatedText.indexOf(hp.pattern, index + splitter.length + 1);
      }
    }

    final parts = text.split(splitter);
    final result = StringBuffer();
    for (final part in parts) {
      result.write(hyphenateSymbol + part);
    }

    String res = result.toString();
    if (res.startsWith(hyphenateSymbol)) {
      res = res.substring(hyphenateSymbol.length);
    }
    return res;
  }
}

/// Виджет для чтения fb2-книги (без AppBar).
/// В initState — асинхронное чтение fb2-файла из assets и разбивка на страницы.
class Fb2ReaderWidget extends StatefulWidget {
  const Fb2ReaderWidget({Key? key}) : super(key: key);

  @override
  _Fb2ReaderWidgetState createState() => _Fb2ReaderWidgetState();
}

class _Fb2ReaderWidgetState extends State<Fb2ReaderWidget> {
  List<Widget> pages = [];

  @override
  void initState() {
    super.initState();
    // После сборки виджета загружаем fb2 и пагинируем
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndPaginate();
    });
  }

  Future<void> _loadAndPaginate() async {
    // Считываем fb2-контент из assets
    final fb2Content = await rootBundle.loadString('assets/book.fb2');

    // Парсим fb2
    final parser = Fb2Parser(fb2Content);
    final document = parser.parse();

    // Определяем размеры «страницы»
    final size = MediaQuery.of(context).size;

    // Создаём hyphenator
    final hyphenator = Hyphenator();

    // Пагинируем документ
    final paginator = Paginator(
      document: document,
      textStyle: TextStyle(fontSize: 16, color: Colors.black),
      pageSize: size,
      hyphenate: hyphenator.hyphenate,
    );

    setState(() {
      pages = paginator.paginate();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Без AppBar — просто возвращаем контейнер на весь экран.
    return Container(
      color: Colors.white,
      child: pages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : PageView(
        children: pages,
      ),
    );
  }
}
