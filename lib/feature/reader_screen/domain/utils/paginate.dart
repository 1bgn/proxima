// paginate.dart

import 'package:flutter/painting.dart';
import 'fb2_parser.dart';

class PageContent {
  final List<ContentBlock> blocks;
  PageContent(this.blocks);
}

/// Разбивает ContentBlock'и на страницы (без "построчного" в списке).
/// Если text не влезает, обрезаем часть, остаток идёт на следующую страницу.
/// При этом, если обрез совпал на \u00AD, мы подменяем на '-' в конце.
List<PageContent> paginateBlocks(List<ContentBlock> blocks, double pageWidth, double pageHeight) {
  final pages = <PageContent>[];
  final currentPage = <ContentBlock>[];
  double usedHeight = 0;

  int i = 0;
  while (i < blocks.length) {
    final block = blocks[i];

    if (block.type == BlockType.pageBreak) {
      // Закрываем страницу
      if (currentPage.isNotEmpty) {
        pages.add(PageContent(List.from(currentPage)));
        currentPage.clear();
      }
      usedHeight = 0;
      i++;
      continue;
    }

    if (block.type == BlockType.image && block.imageData != null) {
      // Масштабируем
      final scaled = _scaleImageBlock(block, pageWidth);
      final totalH = scaled.topSpacing + (scaled.height ?? 0) + scaled.bottomSpacing;
      if (usedHeight + totalH <= pageHeight) {
        currentPage.add(scaled);
        usedHeight += totalH;
        i++;
      } else {
        // новая страница
        if (currentPage.isNotEmpty) {
          pages.add(PageContent(List.from(currentPage)));
          currentPage.clear();
        }
        usedHeight = 0;

        // Если картинка сама выше страницы, всё равно кладём.
        currentPage.add(scaled);
        usedHeight += totalH;
        i++;
      }
    }
    else if (block.type == BlockType.text && block.textSpan != null) {
      // Проверяем высоту
      final textH = _measureTextHeight(block.textSpan!, pageWidth);
      final totalH = block.topSpacing + textH + block.bottomSpacing;

      if (usedHeight + totalH <= pageHeight) {
        // целиком влезает
        currentPage.add(block);
        usedHeight += totalH;
        i++;
      } else {
        // нужно обрезать
        final splitted = splitTextBlockByHeight(block, pageWidth, pageHeight - usedHeight);
        // splitted.item1 — часть, которая влезла
        // splitted.item2 — остаток
        if (splitted.item1 != null) {
          currentPage.add(splitted.item1!);
          // добавили
        }
        // Закрываем страницу
        pages.add(PageContent(List.from(currentPage)));
        currentPage.clear();
        usedHeight = 0;

        if (splitted.item2 == null) {
          // Значит всё, весь блок исчерпан
          i++;
        } else {
          // Есть остаток, значит заменяем blocks[i] на остаток и повторим цикл
          blocks[i] = splitted.item2!;
          // не делаем i++ -> на следующей странице обработаем остаток
          if (splitted.item2 == null) {
            // всё
            i++;
          }
        }
      }
    } else {
      // неизвестный тип
      i++;
    }
  }

  if (currentPage.isNotEmpty) {
    pages.add(PageContent(currentPage));
  }

  return pages;
}

/// Обрезаем текст block (одноцелый InlineSpan),
/// если не целиком влезает (spaceHeight). Возвращаем (влезшаяЧасть, остаток).
/// При этом, если разрыв произошёл на \u00AD, заменяем его на '-' (в конце первой части),
/// и убираем \u00AD в начале второй части.
Tuple2<ContentBlock?, ContentBlock?> splitTextBlockByHeight(
    ContentBlock block,
    double pageWidth,
    double spaceHeight,
    ) {
  final textSpan = block.textSpan!;
  final blockTop = block.topSpacing;
  final blockBottom = block.bottomSpacing;

  // Проверим, сколько строк влезает
  final tp = TextPainter(
    text: textSpan,
    textDirection: TextDirection.ltr,
  );
  tp.layout(maxWidth: pageWidth);

  final lines = tp.computeLineMetrics();
  double usedH = 0;
  int lastLineIndex = -1;

  for (int i = 0; i < lines.length; i++) {
    final lineH = lines[i].height;
    if (usedH + lineH > (spaceHeight - blockTop - blockBottom)) {
      break;
    }
    usedH += lineH;
    lastLineIndex = i;
  }

  if (lastLineIndex < 0) {
    // Ни одной строки не влезло
    // => (null, original)
    return Tuple2(null, block);
  }
  if (lastLineIndex == lines.length - 1) {
    // Влезает весь блок
    return Tuple2(block, null);
  }

  // У нас есть частичное вхождение
  // Найдём cutIndex => конец последней влезшей строки
  double ySplit = 0;
  for (int i = 0; i <= lastLineIndex; i++) {
    ySplit += lines[i].height;
  }
  final yOffset = ySplit; // без -1

  final splitPos = tp.getPositionForOffset(Offset(0, yOffset));
  final cutIndex = splitPos.offset;

  final fullText = _extractPlainText(textSpan);
  if (cutIndex >= fullText.length) {
    // Вдруг “по факту” всё
    return Tuple2(block, null);
  }

  // Создаём part1 (0..cutIndex), part2(cutIndex..end)
  var part1Span = _extractSpanRange(textSpan, 0, cutIndex);
  var part2Span = _extractSpanRange(textSpan, cutIndex, fullText.length);

  // --- ПОСТ-ОБРАБОТКА мягкого переноса ---
  // Если part1 заканчивается на \u00AD => заменим на '-'
  if (part1Span != null) {
    final t1 = _extractPlainText(part1Span);
    if (t1.endsWith('\u00AD')) {
      final replaced = t1.substring(0, t1.length - 1) + '-';
      part1Span = _buildSpanWithStyle(part1Span, replaced);
    }
  }
  // Если part2 начинается с \u00AD => удаляем
  if (part2Span != null) {
    final t2 = _extractPlainText(part2Span);
    if (t2.startsWith('\u00AD')) {
      final replaced = t2.substring(1);
      part2Span = _buildSpanWithStyle(part2Span, replaced);
    }
  }

  final part1 = (part1Span == null)
      ? null
      : ContentBlock.text(
    textSpan: part1Span,
    textAlign: block.textAlign,
    topSpacing: block.topSpacing,
    bottomSpacing: block.bottomSpacing,
  );

  final part2 = (part2Span == null)
      ? null
      : ContentBlock.text(
    textSpan: part2Span,
    textAlign: block.textAlign,
    topSpacing: block.topSpacing,
    bottomSpacing: block.bottomSpacing,
  );

  return Tuple2(part1, part2);
}

InlineSpan _buildSpanWithStyle(InlineSpan original, String newText) {
  TextStyle? st;
  if (original is TextSpan) {
    st = original.style;
  }
  return TextSpan(text: newText, style: st);
}

String _extractPlainText(InlineSpan span) {
  if (span is TextSpan) {
    final b = StringBuffer();
    if (span.text != null) b.write(span.text);
    if (span.children != null) {
      for (final c in span.children!) {
        b.write(_extractPlainText(c));
      }
    }
    return b.toString();
  }
  return '';
}

InlineSpan? _extractSpanRange(InlineSpan original, int start, int end) {
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
      // WidgetSpan => 1 char
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

double _measureTextHeight(InlineSpan span, double maxWidth) {
  final tp = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
  );
  tp.layout(maxWidth: maxWidth);
  return tp.size.height;
}

ContentBlock _scaleImageBlock(ContentBlock block, double pageWidth) {
  final ow = block.width ?? 200;
  final oh = block.height ?? 200;
  final scale = pageWidth / ow;
  final dispH = oh * scale;

  return ContentBlock.image(
    imageData: block.imageData!,
    width: pageWidth,
    height: dispH,
    topSpacing: block.topSpacing,
    bottomSpacing: block.bottomSpacing,
  );
}

/// Помощный Tuple2
class Tuple2<A, B> {
  final A item1;
  final B item2;
  Tuple2(this.item1, this.item2);
}
