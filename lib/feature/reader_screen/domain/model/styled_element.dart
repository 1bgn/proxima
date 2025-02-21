import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:proxima_reader/feature/reader_screen/domain/model/style_attributes.dart';
import 'package:proxima_reader/feature/reader_screen/domain/model/styled_node.dart';

import 'package:xml/xml.dart';
enum BlockType {
  text,
  image,
}
class StyledElement {
  final bool isInline;
  final BlockType type;
  bool get isEmptyLine =>
      styledNode.childAndParents.parents.first.qualifiedName == "empty-line";
  bool get isSectionSeparator=>  styledNode.childAndParents.parents.first.qualifiedName ==
      "section-separator";
  final StyledNode styledNode;
  final styleAttributes = StyleAttributes();
  InlineSpan? _inlineSpan;

  // static final _hyphenator = Hyphenator();
  int index = 0;
  final bool isSplitted;

  Uint8List? image;
  Size? size;

  String? _text;

  @override
  String toString() {
    return 'StyledElement{id: ${styledNode.childAndParents.id},isSplitted: $isSplitted ,index: $index, parents: ${styledNode.childAndParents.parents.map((e) => e.qualifiedName).join(" ")},isInline: $isInline, text:${inlineSpanRead}, ${image != null ? ",imageSize: $size" : ""}';
  }
  // InlineSpan get emptyLine=>const TextSpan(text: "",style: TextStyle(fontSize: 14,height: null));



  StyledElement(
      {required this.isInline,
      required this.styledNode,
      required this.type,
      this.image,
      this.size,
      this.isSplitted = false});

  String get text {
    // _text ??=  _hyphenator.hyphenate(styledNode.childAndParents.child.text,);
    _text ??= styledNode.childAndParents.child.text;
    return _text!;
  }

  bool get isImage => image != null;
  InlineSpan createSpanRead({bool isLast=false,bool isWrapped=false}){
    if(isImage){
      return WidgetSpan(
        child: Image.memory(
          image!.buffer.asUint8List(),
          width: size!.width,
          height: size!.height,
          fit: BoxFit.fill,
        ),
      );
    }
    else if(styledNode.paddings!=EdgeInsets.zero && isWrapped && isLast){
      //text
      return WidgetSpan(
        child: Padding(
          padding: styledNode.paddings,
          child: RichText(textAlign: styledNode.textAlign,text: TextSpan(
              text: text,
              style: styledNode.textStyle,
          )),
        ),
      );

    }else if(styledNode.paddings!=EdgeInsets.zero && isWrapped && !isLast){
      //text
      return WidgetSpan(
        child: Padding(
          padding: styledNode.paddings,
          child: RichText(textAlign: styledNode.textAlign,text: TextSpan(
              text: "$text\n",
              style: styledNode.textStyle,
          )),
        ),
      );

    }else if(styledNode.paddings!=EdgeInsets.zero && !isWrapped && isLast){
      //text
      return TextSpan(
        text: text,
        style: styledNode.textStyle,
      );

    }else if(styledNode.paddings!=EdgeInsets.zero && !isWrapped && !isLast){
      //text
      return TextSpan(
        text: "$text\n",
        style: styledNode.textStyle,
      );

    }
    else if(isInline && isWrapped) {
      return WidgetSpan(child: RichText(text: TextSpan(
        text: text,
        style: styledNode.textStyle,
      )));
    }  else if(isInline && !isWrapped) {
      return TextSpan(
        text: text,
        style: styledNode.textStyle,
      );
    }else if(!isInline && isWrapped){
     return WidgetSpan(child: RichText(text: TextSpan(
        text: "$text\n",
        style: styledNode.textStyle,
      )));
    }else if(!isInline && !isWrapped){
      return  TextSpan(
        text: "$text\n",
        style: styledNode.textStyle,
      );
    }

      else if(isEmptyLine){
        return   TextSpan(text: "\n" ,style: styledNode.textStyle);
      } else {

        return TextSpan(text: "$text\n", style: styledNode.textStyle);
      }


  }



  InlineSpan get inlineSpanRead {

       if(isImage){
         return WidgetSpan(
           child: Image.memory(
             image!.buffer.asUint8List(),
             width: size!.width,
             height: size!.height,
             fit: BoxFit.fill,
           ),
         );
       }
       else if(styledNode.paddings!=EdgeInsets.zero){
         //text
         return WidgetSpan(
           child: Padding(
             padding: styledNode.paddings,
             child: RichText(textAlign: styledNode.textAlign,text: TextSpan(
               text: "$text\n",
               style: styledNode.textStyle,
               children: []
             )),
           ),
         );

      } else {
        if (isInline) {
          return TextSpan(
            text: text,
            style: styledNode.textStyle,
          );
        }else if(isEmptyLine){
          return  const TextSpan(text: "\n" ,style: TextStyle(fontSize: 14,height: 1,inherit: true,color: Colors.red));
        } else {

          return TextSpan(text: "$text\n", style: styledNode.textStyle);
        }

      }

  }


  InlineSpan get textSpan {
     if(isImage ){

      if(isImage){
        return WidgetSpan(
          child: Image.memory(image!.buffer.asUint8List(),
              width: size!.width,
              height: size!.height,
              fit: BoxFit.fill),
          alignment: PlaceholderAlignment.middle,
        );
      }
      else{
        return WidgetSpan(
          child: Padding(
            padding: styledNode.paddings,
            child: RichText(text: TextSpan(
              text: text,
              style: styledNode.textStyle,
            )),
          ),
        );
      }
    }else if(isEmptyLine){

       return  const TextSpan(text: "\t",style: TextStyle(fontSize: 14,color: Colors.black,height: 1,inherit: false));

     }
     else{
      return TextSpan(
        text: text,
        style: styledNode.textStyle,
      );
    }
     return _inlineSpan!;


  }
  InlineSpan get textSpanWithLineNotLast {
    if(isImage ){
        return WidgetSpan(
          child: Image.memory(image!.buffer.asUint8List(),
              width: size!.width,
              height: size!.height,
              fit: BoxFit.fill),
          alignment: PlaceholderAlignment.middle,
        );
    }else if(isEmptyLine){

      return  const TextSpan(text: "\t",style: TextStyle(fontSize: 14,color: Colors.black,height: 1,inherit: false));

    } else if(styledNode.paddings!=EdgeInsets.zero){
      //text
      return WidgetSpan(
        child: Padding(
          padding: styledNode.paddings,
          child: RichText(textAlign: styledNode.textAlign,text: TextSpan(
              text: "$text",
              style: styledNode.textStyle,
          )),
        ),
      );

    }
    else{
      // print("TEXTTEXT $index $text ${styledNode.textStyle}");
      return TextSpan(
        text: text,
        style: styledNode.textStyle,
      );
    }
    return _inlineSpan!;


  }
  InlineSpan get textSpanWithLineLast {

      if(isImage){
        return WidgetSpan(
          child: Image.memory(image!.buffer.asUint8List(),
              width: size!.width,
              height: size!.height,
              fit: BoxFit.fill),
          alignment: PlaceholderAlignment.middle,
        );


    }else if(isEmptyLine){

      return  const TextSpan(text: "\t",style: TextStyle(fontSize: 14,color: Colors.black,height: 1,inherit: false));

    }
    else{
      // print("TEXTTEXT $index $text ${styledNode.textStyle}");
      return TextSpan(
        text: "$text\n",
        style: styledNode.textStyle,
      );
    }
    return _inlineSpan!;


  }
}
