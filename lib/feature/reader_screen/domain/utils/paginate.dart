// paginate.dart

import 'package:flutter/painting.dart';
import 'fb2_parser.dart';

class PageContent {
  final List<ContentBlock> blocks;
  PageContent(this.blocks);
}

/// Основная функция пагинации, которая сначала разбивает текстовые блоки на строки,
/// а затем укладывает полученные строки и изображения на страницы, чтобы не было переполнения.
List<PageContent> paginateBlocks(List<ContentBlock> blocks, double pageWidth, double pageHeight) {
  // Шаг 1: Расбиваем текстовые блоки на отдельные строки.
  final expanded = <ContentBlock>[];
  for (final b in blocks) {
    if (b.type == BlockType.text && b.textSpan != null) {
      final lines = _splitBlockIntoLines(b, pageWidth);
      expanded.addAll(lines);
    } else {
      expanded.add(b);
    }
  }

  // Шаг 2: Укладываем блоки (строки и изображения) на страницы, следя за суммарной высотой.
  final pages = <PageContent>[];
  final currentPage = <ContentBlock>[];
  double usedHeight = 0;

  for (final block in expanded) {
    if (block.type == BlockType.pageBreak) {
      if (currentPage.isNotEmpty) {
        pages.add(PageContent(List.from(currentPage)));
        currentPage.clear();
      }
      usedHeight = 0;
      continue;
    }

    if (block.type == BlockType.image && block.imageData != null) {
      final scaled = _scaleImage(block, pageWidth);
      final needed = scaled.topSpacing + (scaled.height ?? 0) + scaled.bottomSpacing;
      if (usedHeight + needed <= pageHeight) {
        currentPage.add(scaled);
        usedHeight += needed;
      } else {
        if (currentPage.isNotEmpty) {
          pages.add(PageContent(List.from(currentPage)));
          currentPage.clear();
        }
        usedHeight = 0;
        currentPage.add(scaled);
        usedHeight += needed;
      }
    }
    else if (block.type == BlockType.text && block.textSpan != null) {
      final h = _measureHeight(block.textSpan!, block.textAlign, pageWidth);
      final needed = block.topSpacing + h + block.bottomSpacing;
      if (usedHeight + needed <= pageHeight) {
        currentPage.add(block);
        usedHeight += needed;
      } else {
        if (currentPage.isNotEmpty) {
          pages.add(PageContent(List.from(currentPage)));
          currentPage.clear();
        }
        usedHeight = 0;
        currentPage.add(block);
        usedHeight += needed;
      }
    }
  }

  if (currentPage.isNotEmpty) {
    pages.add(PageContent(currentPage));
  }

  return pages;
}

/// Разбиваем текстовый блок (ContentBlock) на строки построчно, используя TextPainter.
List<ContentBlock> _splitBlockIntoLines(ContentBlock block, double maxWidth) {
  final result = <ContentBlock>[];
  final span = block.textSpan;
  if (span == null) return result;

  final tp = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    textAlign: block.textAlign,
  );
  tp.layout(maxWidth: maxWidth);
  final lineMetrics = tp.computeLineMetrics();
  if (lineMetrics.isEmpty) {
    // Если нет строк, возвращаем исходный блок.
    result.add(block);
    return result;
  }

  final fullText = _extractText(span);
  int currentStart = 0;

  for (int i = 0; i < lineMetrics.length; i++) {
    final line = lineMetrics[i];
    // Определяем позицию конца строки
    final pos = tp.getPositionForOffset(Offset(maxWidth, line.baseline + line.descent - 0.5));
    final cutIndex = pos.offset;
    if (cutIndex <= currentStart) continue;
    final realEnd = (cutIndex > fullText.length) ? fullText.length : cutIndex;

    final lineSpan = _extractSpanRange(span, currentStart, realEnd);
    if (lineSpan == null) continue;

    // Не производим замену мягкого переноса на дефис – оставляем soft hyphen
    final topSp = (i == 0) ? block.topSpacing : 0.0;
    final botSp = (i == lineMetrics.length - 1) ? block.bottomSpacing : 0.0;

    result.add(ContentBlock.text(
      textSpan: lineSpan,
      textAlign: block.textAlign,
      topSpacing: topSp,
      bottomSpacing: botSp,
    ));

    currentStart = realEnd;
    // Если следующая строка начинается с soft hyphen, убираем его
    if (currentStart < fullText.length && fullText[currentStart] == '\u00AD') {
      currentStart++;
    }
  }

  return result;
}

double _measureHeight(InlineSpan span, TextAlign align, double maxWidth) {
  final tp = TextPainter(
    text: span,
    textAlign: align,
    textDirection: TextDirection.ltr,
  );
  tp.layout(maxWidth: maxWidth);
  return tp.size.height;
}

String _extractText(InlineSpan span) {
  if (span is TextSpan) {
    final buf = StringBuffer();
    if (span.text != null) buf.write(span.text);
    if (span.children != null) {
      for (final child in span.children!) {
        buf.write(_extractText(child));
      }
    }
    return buf.toString();
  }
  return '';
}

InlineSpan? _extractSpanRange(InlineSpan orig, int start, int end) {
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

      if (e <= spanStart || s >= spanEnd) {
        if (newChildren != null) {
          return TextSpan(style: span.style, children: newChildren);
        }
        return null;
      }

      final cutStart = (s > spanStart) ? (s - spanStart) : 0;
      final cutEnd = (e < spanEnd) ? (e - spanStart) : length;
      final sliced = (cutEnd > cutStart && text.isNotEmpty)
          ? text.substring(cutStart, cutEnd)
          : '';

      if (sliced.isEmpty && (newChildren == null || newChildren.isEmpty)) {
        return null;
      }

      return TextSpan(
        text: sliced.isNotEmpty ? sliced : null,
        style: span.style,
        children: newChildren,
      );
    } else {
      // WidgetSpan => считаем 1 символ
      final spanStart = currentPos;
      final spanEnd = currentPos + 1;
      currentPos++;
      if (e <= spanStart || s >= spanEnd) return null;
      return span;
    }
  }

  return _extract(orig, start, end);
}

ContentBlock _scaleImage(ContentBlock block, double pageWidth) {
  if (block.width == null || block.height == null || block.imageData == null) return block;
  final ow = block.width!;
  final oh = block.height!;
  final scale = pageWidth / ow;
  final newH = oh * scale;
  return ContentBlock.image(
    imageData: block.imageData,
    width: pageWidth,
    height: newH,
    topSpacing: block.topSpacing,
    bottomSpacing: block.bottomSpacing,
  );
}
