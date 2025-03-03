// /// advanced_text_widget.dart
// ///
// /// Итоговый виджет (LeafRenderObjectWidget) и RenderBox,
// /// который использует [AdvancedLayoutEngine] и рисует **первую** страницу.
//
// import 'dart:ui' as ui;
//
// import 'package:flutter/rendering.dart';
// import 'package:flutter/widgets.dart';
// import 'inline_elements.dart';
// import 'paragraph_block.dart';
// import 'line_layout.dart';
// import 'text_layout_engine.dart';
// import 'dart:math' as math;
//
// class AdvancedTextWidget extends LeafRenderObjectWidget {
//   final List<ParagraphBlock> paragraphs;
//   final double width;
//   final double lineSpacing;
//   final CustomTextAlign textAlign;
//   final bool allowSoftHyphens;
//   final int columns;
//   final double columnSpacing;
//   final double pageHeight;
//
//   /// Простой вариант выделения: если заданы оба, то считаем весь текст «подсвечен».
//   final int? selectionStart;
//   final int? selectionEnd;
//
//   /// Callback на клик по ссылке (InlineLinkElement).
//   final void Function(String url)? onLinkTap;
//
//   const AdvancedTextWidget({
//     Key? key,
//     required this.paragraphs,
//     required this.width,
//     this.lineSpacing = 4.0,
//     this.textAlign = CustomTextAlign.left,
//     this.allowSoftHyphens = true,
//     this.columns = 1,
//     this.columnSpacing = 20.0,
//     required this.pageHeight,
//     this.selectionStart,
//     this.selectionEnd,
//     this.onLinkTap,
//   }) : super(key: key);
//
//   @override
//   RenderObject createRenderObject(BuildContext context) {
//     return AdvancedTextRenderObject(
//       paragraphs: paragraphs,
//       width: width,
//       lineSpacing: lineSpacing,
//       textAlign: textAlign,
//       allowSoftHyphens: allowSoftHyphens,
//       columns: columns,
//       columnSpacing: columnSpacing,
//       pageHeight: pageHeight,
//       selectionStart: selectionStart,
//       selectionEnd: selectionEnd,
//       onLinkTap: onLinkTap,
//     );
//   }
//
//   @override
//   void updateRenderObject(BuildContext context, AdvancedTextRenderObject renderObject) {
//     renderObject
//       ..paragraphs = paragraphs
//       ..width = width
//       ..lineSpacing = lineSpacing
//       ..textAlign = textAlign
//       ..allowSoftHyphens = allowSoftHyphens
//       ..columns = columns
//       ..columnSpacing = columnSpacing
//       ..pageHeight = pageHeight
//       ..selectionStart = selectionStart
//       ..selectionEnd = selectionEnd
//       ..onLinkTap = onLinkTap;
//   }
// }
//
// class AdvancedTextRenderObject extends RenderBox {
//   List<ParagraphBlock> _paragraphs;
//   double _width;
//   double _lineSpacing;
//   CustomTextAlign _textAlign;
//   bool _allowSoftHyphens;
//   int _columns;
//   double _columnSpacing;
//   double _pageHeight;
//
//   int? _selectionStart;
//   int? _selectionEnd;
//   void Function(String url)? _onLinkTap;
//
//   AdvancedTextRenderObject({
//     required List<ParagraphBlock> paragraphs,
//     required double width,
//     required double lineSpacing,
//     required CustomTextAlign textAlign,
//     required bool allowSoftHyphens,
//     required int columns,
//     required double columnSpacing,
//     required double pageHeight,
//     int? selectionStart,
//     int? selectionEnd,
//     void Function(String url)? onLinkTap,
//   })  : _paragraphs = paragraphs,
//         _width = width,
//         _lineSpacing = lineSpacing,
//         _textAlign = textAlign,
//         _allowSoftHyphens = allowSoftHyphens,
//         _columns = columns,
//         _columnSpacing = columnSpacing,
//         _pageHeight = pageHeight,
//         _selectionStart = selectionStart,
//         _selectionEnd = selectionEnd,
//         _onLinkTap = onLinkTap;
//
//   MultiColumnPagedLayout? _layoutResult;
//
//   set paragraphs(List<ParagraphBlock> value) {
//     if (_paragraphs != value) {
//       _paragraphs = value;
//       markNeedsLayout();
//     }
//   }
//
//   set width(double value) {
//     if (_width != value) {
//       _width = value;
//       markNeedsLayout();
//     }
//   }
//
//   set lineSpacing(double value) {
//     if (_lineSpacing != value) {
//       _lineSpacing = value;
//       markNeedsLayout();
//     }
//   }
//
//   set textAlign(CustomTextAlign value) {
//     if (_textAlign != value) {
//       _textAlign = value;
//       markNeedsLayout();
//     }
//   }
//
//   set allowSoftHyphens(bool value) {
//     if (_allowSoftHyphens != value) {
//       _allowSoftHyphens = value;
//       markNeedsLayout();
//     }
//   }
//
//   set columns(int value) {
//     if (_columns != value) {
//       _columns = value;
//       markNeedsLayout();
//     }
//   }
//
//   set columnSpacing(double value) {
//     if (_columnSpacing != value) {
//       _columnSpacing = value;
//       markNeedsLayout();
//     }
//   }
//
//   set pageHeight(double value) {
//     if (_pageHeight != value) {
//       _pageHeight = value;
//       markNeedsLayout();
//     }
//   }
//
//   set selectionStart(int? value) {
//     if (_selectionStart != value) {
//       _selectionStart = value;
//       markNeedsPaint();
//     }
//   }
//
//   set selectionEnd(int? value) {
//     if (_selectionEnd != value) {
//       _selectionEnd = value;
//       markNeedsPaint();
//     }
//   }
//
//   set onLinkTap(void Function(String url)? value) {
//     if (_onLinkTap != value) {
//       _onLinkTap = value;
//       markNeedsLayout();
//     }
//   }
//
//   @override
//   void performLayout() {
//     final cWidth = constraints.maxWidth.isFinite
//         ? math.min(_width, constraints.maxWidth)
//         : _width;
//
//     final engine = AdvancedLayoutEngine(
//       paragraphs: _paragraphs,
//       globalMaxWidth: cWidth,
//       lineSpacing: _lineSpacing,
//       globalTextAlign: _textAlign,
//       allowSoftHyphens: _allowSoftHyphens,
//       columns: _columns,
//       columnSpacing: _columnSpacing,
//       pageHeight: _pageHeight,
//     );
//
//     _layoutResult = engine.layoutAll();
//
//     final finalHeight = _pageHeight.clamp(constraints.minHeight, constraints.maxHeight);
//     size = Size(cWidth, finalHeight);
//   }
//
//   @override
//   void paint(PaintingContext context, Offset offset) {
//     if (_layoutResult == null) return;
//
//     final canvas = context.canvas;
//     // Рендерим только первую страницу (pageIndex=0).
//     final page = _layoutResult!.pages.isNotEmpty ? _layoutResult!.pages[0] : null;
//     if (page == null) return;
//
//     for (int colI = 0; colI < page.columns.length; colI++) {
//       final colLines = page.columns[colI];
//       final colX = offset.dx + colI * (page.columnWidth + page.columnSpacing);
//       double dy = offset.dy;
//
//       for (int lineI = 0; lineI < colLines.length; lineI++) {
//         final line = colLines[lineI];
//         final lineTop = dy;
//         double dx = colX;
//         final extraSpace = page.columnWidth - line.width;
//
//         // Считаем количество «пробелов» для justify
//         int gapCount = 0;
//         if (_textAlign == CustomTextAlign.justify && line.elements.length > 1) {
//           for (int eIndex = 0; eIndex < line.elements.length - 1; eIndex++) {
//             final e1 = line.elements[eIndex];
//             final e2 = line.elements[eIndex + 1];
//             if (e1 is TextInlineElement && e2 is TextInlineElement) {
//               gapCount++;
//             }
//           }
//         }
//
//         // Определим смещение dx по выравниванию
//         switch (_textAlign) {
//           case CustomTextAlign.left:
//             dx = colX;
//             break;
//           case CustomTextAlign.right:
//             dx = colX + extraSpace;
//             break;
//           case CustomTextAlign.center:
//             dx = colX + extraSpace / 2;
//             break;
//           case CustomTextAlign.justify:
//             dx = colX;
//             break;
//         }
//
//         // Рисуем элементы
//         for (int eIndex = 0; eIndex < line.elements.length; eIndex++) {
//           final elem = line.elements[eIndex];
//           final baselineShift = line.baseline - elem.baseline;
//           final elemOffset = Offset(dx, lineTop + baselineShift);
//
//           // Если justify
//           double gapExtra = 0.0;
//           if (_textAlign == CustomTextAlign.justify && gapCount > 0 && eIndex < line.elements.length - 1) {
//             final nextElem = line.elements[eIndex + 1];
//             if (elem is TextInlineElement && nextElem is TextInlineElement) {
//               gapExtra = extraSpace / gapCount;
//             }
//           }
//
//           _paintElementWithSelection(canvas, elem, elemOffset);
//
//           dx += elem.width + gapExtra;
//         }
//
//         dy += line.height;
//         if (lineI < colLines.length - 1) {
//           dy += _lineSpacing;
//         }
//       }
//     }
//   }
//
//   /// Рисует элемент, при необходимости выделяя его (упрощённо).
//   void _paintElementWithSelection(ui.Canvas canvas, InlineElement elem, Offset offset) {
//     if (_selectionStart != null && _selectionEnd != null) {
//       // В реальном проекте нужно маппить символы к глобальным индексам.
//       // Здесь — упрощённо: если выделено что-то, заливаем весь элемент.
//       final paint = Paint()..color = const Color(0x44339FFF);
//       final rect = Rect.fromLTWH(offset.dx, offset.dy, elem.width, elem.height);
//       canvas.drawRect(rect, paint);
//     }
//     elem.paint(canvas, offset);
//   }
//
//   @override
//   bool hitTestSelf(Offset position) => true;
//
//   @override
//   bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
//     return false;
//   }
//
//   @override
//   void handleEvent(PointerEvent event, HitTestEntry entry) {
//     // Для упрощения обрабатываем клик по ссылкам
//     if (event is PointerDownEvent && _onLinkTap != null) {
//       if (_layoutResult == null) return;
//       final page = _layoutResult!.pages.isNotEmpty ? _layoutResult!.pages[0] : null;
//       if (page == null) return;
//
//       final localPos = event.localPosition;
//
//       for (int colI = 0; colI < page.columns.length; colI++) {
//         final colLines = page.columns[colI];
//         final colX = colI * (page.columnWidth + page.columnSpacing);
//         double dy = 0.0;
//
//         for (int lineI = 0; lineI < colLines.length; lineI++) {
//           final line = colLines[lineI];
//           final lineTop = dy;
//           double dx = colX;
//           final extraSpace = page.columnWidth - line.width;
//
//           int gapCount = 0;
//           if (_textAlign == CustomTextAlign.justify && line.elements.length > 1) {
//             for (int eIndex = 0; eIndex < line.elements.length - 1; eIndex++) {
//               final e1 = line.elements[eIndex];
//               final e2 = line.elements[eIndex + 1];
//               if (e1 is TextInlineElement && e2 is TextInlineElement) {
//                 gapCount++;
//               }
//             }
//           }
//
//           switch (_textAlign) {
//             case CustomTextAlign.left:
//               dx = colX;
//               break;
//             case CustomTextAlign.right:
//               dx = colX + extraSpace;
//               break;
//             case CustomTextAlign.center:
//               dx = colX + extraSpace / 2;
//               break;
//             case CustomTextAlign.justify:
//               dx = colX;
//               break;
//           }
//
//           for (int eIndex = 0; eIndex < line.elements.length; eIndex++) {
//             final elem = line.elements[eIndex];
//             final baselineShift = line.baseline - elem.baseline;
//             final elemOffset = Offset(dx, lineTop + baselineShift);
//
//             double gapExtra = 0.0;
//             if (_textAlign == CustomTextAlign.justify && gapCount > 0 && eIndex < line.elements.length - 1) {
//               final nextElem = line.elements[eIndex + 1];
//               if (elem is TextInlineElement && nextElem is TextInlineElement) {
//                 gapExtra = extraSpace / gapCount;
//               }
//             }
//
//             final bounding = Rect.fromLTWH(elemOffset.dx, elemOffset.dy, elem.width, elem.height);
//             if (bounding.contains(localPos)) {
//               if (elem is InlineLinkElement) {
//                 _onLinkTap?.call(elem.url);
//                 return;
//               }
//             }
//
//             dx += elem.width + gapExtra;
//           }
//
//           dy += line.height;
//           if (lineI < colLines.length - 1) {
//             dy += _lineSpacing;
//           }
//         }
//       }
//     }
//   }
// }
