// paginate.dart

import 'package:flutter/painting.dart';
import 'fb2_parser.dart';

class PageContent {
  final List<ContentBlock> blocks;
  PageContent(this.blocks);
}

class Tuple2<A, B> {
  final A item1;
  final B item2;
  Tuple2(this.item1, this.item2);
}

/// Основная функция, разбивающая список блоков (текст/картинки) на страницы
List<PageContent> paginate(List<ContentBlock> blocks, double pageWidth, double pageHeight) {
  final pages = <PageContent>[];
  final currentPageBlocks = <ContentBlock>[];
  double usedHeight = 0;

  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (block.type == BlockType.text && block.textSpan != null) {
      final textH = _measureTextHeight(block.textSpan!, pageWidth);
      if (usedHeight + textH <= pageHeight) {
        currentPageBlocks.add(block);
        usedHeight += textH;
      } else {
        final splitted = splitTextBlockByHeight(block.textSpan!, pageWidth, pageHeight - usedHeight);
        final part1 = splitted.item1;
        final part2 = splitted.item2;

        if (part1 != null) {
          currentPageBlocks.add(ContentBlock.text(part1));
          usedHeight += _measureTextHeight(part1, pageWidth);
        }
        pages.add(PageContent(List.from(currentPageBlocks)));
        currentPageBlocks.clear();
        usedHeight = 0;

        if (part2 != null) {
          // остаток
          blocks.insert(i + 1, ContentBlock.text(part2));
        }
      }
    } else if (block.type == BlockType.image && block.imageData != null) {
      final h = block.desiredHeight ?? 200;
      if (usedHeight + h <= pageHeight) {
        currentPageBlocks.add(block);
        usedHeight += h;
      } else {
        pages.add(PageContent(List.from(currentPageBlocks)));
        currentPageBlocks.clear();
        usedHeight = 0;

        // добавляем на новую страницу
        currentPageBlocks.add(block);
        usedHeight = h;
      }
    }
  }

  if (currentPageBlocks.isNotEmpty) {
    pages.add(PageContent(currentPageBlocks));
  }

  return pages;
}

/// Измеряем высоту текста
double _measureTextHeight(InlineSpan span, double maxWidth) {
  final tp = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
  );
  tp.layout(maxWidth: maxWidth);
  return tp.size.height;
}

/// Частично обрезаем текст, чтобы он уместился по высоте
Tuple2<InlineSpan?, InlineSpan?> splitTextBlockByHeight(
    InlineSpan original,
    double pageWidth,
    double pageHeight,
    ) {
  final tp = TextPainter(
    text: original,
    textDirection: TextDirection.ltr,
  );
  tp.layout(maxWidth: pageWidth);

  final lines = tp.computeLineMetrics();
  double cumulativeHeight = 0;
  int lastLineIndex = -1;

  for (var i = 0; i < lines.length; i++) {
    final lineH = lines[i].height;
    if (cumulativeHeight + lineH > pageHeight) {
      break;
    }
    cumulativeHeight += lineH;
    lastLineIndex = i;
  }

  if (lastLineIndex < 0) {
    return Tuple2(null, original); // ни одной строки
  }
  if (lastLineIndex == lines.length - 1) {
    return Tuple2(original, null); // всё умещается
  }

  double ySplit = 0;
  for (int i = 0; i <= lastLineIndex; i++) {
    ySplit += lines[i].height;
  }
  final yOffset = (ySplit - 1).clamp(0, tp.size.height);

  final splitPos = tp.getPositionForOffset(Offset(0, yOffset as double));
  final cutIndex = splitPos.offset;

  final fullText = extractPlainText(original);
  if (cutIndex >= fullText.length) {
    return Tuple2(original, null);
  }

  final part1 = extractSpanRange(original, 0, cutIndex);
  final part2 = extractSpanRange(original, cutIndex, fullText.length);

  return Tuple2(part1, part2);
}

// ---- extractPlainText / extractSpanRange ----

String extractPlainText(InlineSpan span) {
  if (span is TextSpan) {
    final buffer = StringBuffer();
    if (span.text != null) {
      buffer.write(span.text);
    }
    if (span.children != null) {
      for (final child in span.children!) {
        buffer.write(extractPlainText(child));
      }
    }
    return buffer.toString();
  }
  return '';
}

InlineSpan? extractSpanRange(InlineSpan original, int start, int end) {
  int currentPos = 0;

  InlineSpan? _extract(InlineSpan span, int s, int e) {
    if (s >= e) return null;
    if (span is TextSpan) {
      final text = span.text ?? '';
      final length = text.length;

      final spanStart = currentPos;
      final spanEnd = currentPos + length;
      currentPos += length;

      List<InlineSpan>? newChildren;
      if (span.children != null && span.children!.isNotEmpty) {
        newChildren = [];
        for (final child in span.children!) {
          final ec = _extract(child, s, e);
          if (ec != null) newChildren.add(ec);
        }
        if (newChildren.isEmpty) newChildren = null;
      }

      // проверяем пересечение
      if (e <= spanStart || s >= spanEnd) {
        if (newChildren != null) {
          return TextSpan(style: span.style, children: newChildren);
        }
        return null;
      }

      final cutStart = (s > spanStart) ? (s - spanStart) : 0;
      final cutEnd = (e < spanEnd) ? (e - spanStart) : length;
      final sliced = text.isNotEmpty ? text.substring(cutStart, cutEnd) : '';

      if (sliced.isEmpty && (newChildren == null || newChildren.isEmpty)) {
        return null;
      }
      return TextSpan(
        text: sliced.isNotEmpty ? sliced : null,
        style: span.style,
        children: newChildren,
      );
    } else {
      // WidgetSpan -> 1 символ
      final spanStart = currentPos;
      final spanEnd = currentPos + 1;
      currentPos += 1;

      if (e <= spanStart || s >= spanEnd) {
        return null;
      }
      return span;
    }
  }

  return _extract(original, start, end);
}
