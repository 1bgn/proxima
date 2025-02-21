
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'child_and_parents.dart';

class StyledNode {
  final ChildAndParents childAndParents;
  final TextStyle textStyle;
  final TextAlign textAlign;
  final EdgeInsets paddings;




  StyledNode({required this.childAndParents, required this.textStyle,required this.textAlign,this.paddings=EdgeInsets.zero});
}