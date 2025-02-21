// book_reader_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/utils/fb2_parser.dart';
import '../../domain/utils/paginate.dart';


class BookReaderPage extends StatefulWidget {
  const BookReaderPage({Key? key}) : super(key: key);

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  List<ContentBlock>? _blocks;
  List<PageContent>? _pages;
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    _loadFb2();
  }

  /// Читаем FB2-файл из ассета и парсим
  Future<void> _loadFb2() async {
    try {
      final fb2String = await rootBundle.loadString('assets/books/book7.fb2');
      final blocks = parseFb2(fb2String);
      setState(() {
        _blocks = blocks;
      });
    } catch (e) {
      setState(() {
        _blocks = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Полноэкранный Scaffold (без AppBar)
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (_blocks == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_blocks!.isEmpty) {
            return const Center(child: Text('Нет данных'));
          }

          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (_lastSize == null || _lastSize != size) {
            _lastSize = size;
            _pages = paginate(_blocks!, size.width, size.height);
          }

          if (_pages == null || _pages!.isEmpty) {
            return const Center(child: Text('Нет страниц'));
          }

          return PageView.builder(
            itemCount: _pages!.length,
            itemBuilder: (context, index) {
              final page = _pages![index];
              return SafeArea(
                child: Container(
                  color: Colors.white,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: page.blocks.map((block) {
                        if (block.type == BlockType.text) {
                          return RichText(
                            text: block.textSpan!,
                            textAlign: TextAlign.left,
                            softWrap: true,
                          );
                        } else if (block.type == BlockType.image) {
                          return Image.memory(
                            block.imageData!,
                            width: block.desiredWidth,
                            height: block.desiredHeight,
                            fit: BoxFit.cover,
                          );
                        }
                        return const SizedBox.shrink();
                      }).toList(),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
