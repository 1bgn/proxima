// // lib/custom_text_engine/example_screen.dart
//
// import 'dart:ui' as ui;
// import 'package:flutter/material.dart';
// import 'custom_text_engine/advanced_text_widget.dart';
// import 'custom_text_engine/inline_elements.dart';
// import 'custom_text_engine/paragraph_block.dart';
//
// import 'hyphenator.dart';
//
// class ReaderTestScreen extends StatelessWidget {
//   const ReaderTestScreen({Key? key}) : super(key: key);
//
//   @override
//   Widget build(BuildContext context) {
//     // 1) Hyphenator, чтобы вставить \u00AD в длинные слова
//     final hyphenator = Hyphenator();
//
//     // 2) Допустим, у нас есть изображение (ui.Image?), можем оставить null
//     ui.Image? exampleImage;
//
//     // 3) Пример исходного текста, без лишних пробелов
//     //    (мы сознательно слили некоторые слова, чтобы проверить,
//     //     как будет вставлять пробел).
//     String originalText =
//         "Этопример действительнооченьдлинногословa,"
//         "котороемыхотимперенести.Атакже проверимforinstanceverylongenglishword."
//         "Пробелыдолжнысохраниться,атакжепереносыслов.";
//
//     // 4) Гипенизируем
//     final hyphenatedText = hyphenator.hyphenate(originalText);
//
//     // Абзац 1
//     final paragraph1 = ParagraphBlock(
//       inlineElements: [
//         TextInlineElement(hyphenatedText, const TextStyle(fontSize: 16, color: Colors.black)),
//       ],
//       textAlign: CustomTextAlign.justify,
//       textDirection: CustomTextDirection.ltr,
//       firstLineIndent: 40,
//       paragraphSpacing: 12,
//       minimumLines: 2,
//     );
//
//     // Абзац 2 (блочное изображение)
//     final paragraph2 = ParagraphBlock(
//       inlineElements: [
//         TextInlineElement(
//           "Второй абзац с блочной картинкой:И текст после блочной картинки.",
//           const TextStyle(fontSize: 16, color: Colors.blue),
//         ),
//         if (exampleImage != null)
//           ImageInlineElement(
//             image: exampleImage,
//             desiredWidth: 250,
//             desiredHeight: 150,
//             mode: ImageDisplayMode.block,
//           ),
//       ],
//       textAlign: CustomTextAlign.left,
//       textDirection: CustomTextDirection.ltr,
//       firstLineIndent: 0,
//       paragraphSpacing: 10,
//       minimumLines: 2,
//     );
//
//     // Абзац 3 (inline-изображение + RTL)
//     final paragraph3 = ParagraphBlock(
//       inlineElements: [
//         TextInlineElement("فقرة RTL ", const TextStyle(fontSize: 16, color: Colors.red)),
//         if (exampleImage != null)
//           ImageInlineElement(
//             image: exampleImage,
//             desiredWidth: 60,
//             desiredHeight: 60,
//             mode: ImageDisplayMode.inline,
//           ),
//         TextInlineElement(" مرحباً بالعالم!", const TextStyle(fontSize: 16, color: Colors.red)),
//       ],
//       textAlign: CustomTextAlign.right,
//       textDirection: CustomTextDirection.rtl,
//       firstLineIndent: 40,
//       paragraphSpacing: 20,
//       minimumLines: 2,
//     );
//
//     final paragraphs = [paragraph1, paragraph2, paragraph3];
//
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Reader Test Screen"),
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: AdvancedTextWidget(
//           paragraphs: paragraphs,
//           width: MediaQuery.of(context).size.width - 32,
//           lineSpacing: 6.0,
//           textAlign: CustomTextAlign.left,
//           allowSoftHyphens: true,
//           columns: 2,
//           columnSpacing: 20,
//           pageHeight: 800,
//           // Демонстрируем простое выделение
//           selectionStart: 0,
//           selectionEnd: 9999,
//         ),
//       ),
//     );
//   }
// }
