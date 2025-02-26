import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

const String projectPath = "../";
const String apiUrl = "http://5.183.146.217:5000/refactor";

Future<void> processProject() async {
  final List<File> dartFiles = await getDartFiles(Directory(projectPath));

  for (File file in dartFiles) {
    final String code = await file.readAsString();
    final String newCode = await refactorCode(code);

    if (newCode != code) {
      await file.writeAsString(newCode);
      print("✅ Файл обновлён: ${file.path}");
    }
  }
}

Future<List<File>> getDartFiles(Directory dir) async {
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

Future<String> refactorCode(String code) async {
  final response = await http.post(
    Uri.parse(apiUrl),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({"code": code}),
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body)["refactored_code"];
  }
  return code;
}

void main() {
  processProject();
}
