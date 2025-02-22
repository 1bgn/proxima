// book_reader_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fb2_parser.dart';
import 'paginate.dart';

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

  Future<void> _loadFb2() async {
    try {
      final fb2String = await rootBundle.loadString('assets/book.fb2');
      final parsed = await parseFb2(fb2String);
      setState(() {
        _blocks = parsed;
      });
    } catch (e) {
      debugPrint('Error parse: $e');
      setState(() {
        _blocks = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (ctx, constraints) {
        if (_blocks == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_blocks!.isEmpty) {
          return const Center(child: Text("FB2 пуст / ошибка"));
        }

        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastSize == null || _lastSize != size) {
          _lastSize = size;
          _pages = paginateBlocks(_blocks!, size.width, size.height);
        }

        if (_pages == null || _pages!.isEmpty) {
          return const Center(child: Text("Нет страниц"));
        }

        return PageView.builder(
          itemCount: _pages!.length,
          itemBuilder: (context, idx) {
            final page = _pages![idx];
            return SafeArea(
              child: Container(
                color: Colors.white,
                width: double.infinity,
                height: double.infinity,
                child: _buildPage(page),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildPage(PageContent page) {
    // каждый элемент - строка или картинка
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: page.blocks.map((b) => _buildBlock(b)).toList(),
    );
  }

  Widget _buildBlock(ContentBlock block) {
    return Container(
      margin: EdgeInsets.only(
        top: block.topSpacing,
        bottom: block.bottomSpacing,
      ),
      child: () {
        if (block.type == BlockType.text && block.textSpan != null) {
          return RichText(
            text: block.textSpan!,
            textAlign: block.textAlign,
            softWrap: true,
          );
        } else if (block.type == BlockType.image && block.imageData != null) {
          return Image.memory(
            block.imageData!,
            width: block.width,
            height: block.height,
            fit: BoxFit.contain,
          );
        }
        // pageBreak / unknown
        return const SizedBox.shrink();
      }(),
    );
  }
}
