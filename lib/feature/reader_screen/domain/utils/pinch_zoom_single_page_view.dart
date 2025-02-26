// // pinch_zoom_single_page_view.dart
//
// import 'package:flutter/rendering.dart';
// import 'package:flutter/widgets.dart';
// import 'custom_text_engine/line_layout.dart';
// import 'custom_text_engine/paragraph_block.dart';
//
// import 'dart:math' as math;
//
// class PinchZoomSinglePageView extends LeafRenderObjectWidget {
//   final MultiColumnPage page;
//   final double lineSpacing;
//   final CustomTextAlign textAlign;
//   final bool allowSoftHyphens;
//
//   const PinchZoomSinglePageView({
//     Key? key,
//     required this.page,
//     this.lineSpacing = 4.0,
//     this.textAlign = CustomTextAlign.left,
//     this.allowSoftHyphens = true,
//   }) : super(key: key);
//
//   @override
//   RenderObject createRenderObject(BuildContext context) {
//     return PinchZoomSinglePageRender(
//       page: page,
//       lineSpacing: lineSpacing,
//       textAlign: textAlign,
//       allowSoftHyphens: allowSoftHyphens,
//     );
//   }
//
//   @override
//   void updateRenderObject(BuildContext context, covariant PinchZoomSinglePageRender renderObject) {
//     renderObject
//       ..page = page
//       ..lineSpacing = lineSpacing
//       ..textAlign = textAlign
//       ..allowSoftHyphens = allowSoftHyphens;
//   }
// }
//
// class PinchZoomSinglePageRender extends RenderBox {
//   MultiColumnPage _page;
//   double _lineSpacing;
//   CustomTextAlign _textAlign;
//   bool _allowSoftHyphens;
//
//   // Pinch-zoom state
//   double _scale = 1.0;
//
//   PinchZoomSinglePageRender({
//     required MultiColumnPage page,
//     required double lineSpacing,
//     required CustomTextAlign textAlign,
//     required bool allowSoftHyphens,
//   })  : _page = page,
//         _lineSpacing = lineSpacing,
//         _textAlign = textAlign,
//         _allowSoftHyphens = allowSoftHyphens;
//
//   set page(MultiColumnPage v) {
//     if (_page != v) {
//       _page = v;
//       markNeedsLayout();
//     }
//   }
//   set lineSpacing(double v) {
//     if (_lineSpacing != v) {
//       _lineSpacing = v;
//       markNeedsLayout();
//     }
//   }
//   set textAlign(CustomTextAlign v) {
//     if (_textAlign != v) {
//       _textAlign = v;
//       markNeedsLayout();
//     }
//   }
//   set allowSoftHyphens(bool v) {
//     if (_allowSoftHyphens != v) {
//       _allowSoftHyphens = v;
//       markNeedsLayout();
//     }
//   }
//
//   // Для жестов
//   Offset? _lastFocalPoint;
//
//   @override
//   bool hitTestSelf(Offset position) => true;
//   @override
//   void handleEvent(PointerEvent event, HitTestEntry entry) {
//     if (event is PointerDownEvent) {
//       _lastFocalPoint = event.position;
//     } else if (event is PointerMoveEvent && event.isZooming) {
//       // pinch
//       final scaleChange = event.zoomScale;
//       _scale *= scaleChange;
//       _scale = math.max(0.5, math.min(_scale, 5.0));
//       markNeedsLayout();
//     }
//   }
//
//   @override
//   void performLayout() {
//     size = constraints.biggest;
//   }
//
//   @override
//   void paint(PaintingContext context, Offset offset) {
//     final canvas = context.canvas;
//
//     final colWidth = _page.columnWidth * _scale;
//     final spacing = _page.columnSpacing * _scale;
//     for (int colI = 0; colI < _page.columns.length; colI++) {
//       final colLines = _page.columns[colI];
//       final colX = offset.dx + colI * (colWidth + spacing);
//       double dy = offset.dy;
//
//       for (int lineI = 0; lineI < colLines.length; lineI++) {
//         final line = colLines[lineI];
//         final lineTop = dy;
//         double dx = colX;
//         final scaledLineWidth = line.width * _scale;
//         final extraSpace = colWidth - scaledLineWidth;
//
//         int gapCount = 0;
//         if (_textAlign == CustomTextAlign.justify && line.elements.length > 1) {
//           // ...
//         }
//
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
//         for (int eIndex = 0; eIndex < line.elements.length; eIndex++) {
//           final elem = line.elements[eIndex];
//           final baselineShift = line.baseline - elem.baseline;
//           final scaledElemWidth = elem.width * _scale;
//           final scaledElemHeight = elem.height * _scale;
//           final elemOffset = Offset(dx, lineTop + baselineShift * _scale);
//
//           double gapExtra = 0;
//           // if justify ...
//           // ...
//
//           // Если elem — ImageFutureInlineElement, подмешаем scale
//           if (elem is ImageFutureInlineElement) {
//             // Установим elem.zoomScale = _scale?
//             elem.zoomScale = _scale;
//           }
//
//           // canvas.save, scale?
//           // Можно по-разному — проще scale == 1 fallback
//           canvas.save();
//           canvas.translate(elemOffset.dx, elemOffset.dy);
//           canvas.scale(_scale, _scale);
//           elem.paint(canvas, Offset.zero);
//           canvas.restore();
//
//           dx += scaledElemWidth + gapExtra;
//         }
//
//         dy += line.height * _scale;
//         if (lineI < colLines.length - 1) {
//           dy += _lineSpacing * _scale;
//         }
//       }
//     }
//   }
// }
