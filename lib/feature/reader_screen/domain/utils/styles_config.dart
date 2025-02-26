import 'package:flutter/material.dart';
import 'custom_text_engine/inline_elements.dart';
import 'custom_text_engine/paragraph_block.dart';

/// Пример простейшего класса, задающего настройки для отдельного тега FB2.
class TagStyleConfig {
  final double fontSize;
  final FontWeight fontWeight;
  final Color color;
  final double paragraphSpacing;
  final double firstLineIndent;
  final CustomTextAlign? align;

  /// Для картинок
  final double width;
  final double height;
  final ImageDisplayMode displayMode;

  TagStyleConfig({
    this.fontSize = 14.0,
    this.fontWeight = FontWeight.normal,
    this.color = Colors.black,
    this.paragraphSpacing = 8.0,
    this.firstLineIndent = 0.0,
    this.align,
    this.width = 100,
    this.height = 100,
    this.displayMode = ImageDisplayMode.inline,
  });

  TextStyle toTextStyle() {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: 1.2,
    );
  }
}

/// Класс, в котором вы храните стили для разных тегов.
class StylesConfig {
  final Map<String, TagStyleConfig> _map;

  StylesConfig(this._map);

  /// Если нет стиля для данного тега, вернём дефолт.
  TagStyleConfig getStyleForTag(String tagName) {
    return _map[tagName] ?? TagStyleConfig();
  }
}

/// Можно подготовить «дефолтный» набор, а при желании – расширять
/// под каждую книгу или под каждое приложение.
StylesConfig createDefaultStylesConfig() {
  return StylesConfig({
    'title': TagStyleConfig(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      align: CustomTextAlign.center,
      paragraphSpacing: 16,
    ),
    'p': TagStyleConfig(
      fontSize: 14,
      paragraphSpacing: 8,
    ),
    'subtitle': TagStyleConfig(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      paragraphSpacing: 12,
    ),
    'image': TagStyleConfig(
      width: 200,
      height: 200,
      displayMode: ImageDisplayMode.block,
      paragraphSpacing: 12,
    ),
    // И т.д. для других тегов...
  });
}
