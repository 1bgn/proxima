import 'package:xml/xml.dart';

class ChildAndParents{
  final XmlNode child;
  final List<XmlElement> parents;
   int id;

  ChildAndParents({required this.child, required this.parents,this.id=0});

  @override
  String toString() {
    return "id=$id {${child.text} <${parents.map((e) => e.name.qualified).join(" ")}}>";
  }
}