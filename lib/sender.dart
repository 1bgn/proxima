import 'dart:io';
import 'package:http/http.dart' as http;

const String apiUrl = "http://5.183.146.217:5000/upload"; // Windows API

Future<void> uploadZipFile() async {
  var request = http.MultipartRequest("POST", Uri.parse(apiUrl));
  request.files.add(await http.MultipartFile.fromPath("file", "flutter_project.zip"));

  var response = await request.send();
  var responseBody = await response.stream.bytesToString();

  if (response.statusCode == 200) {
    print("✅ Архив загружен! Ответ сервера: $responseBody");
  } else {
    print("❌ Ошибка загрузки! Код: ${response.statusCode}, Ответ: $responseBody");
  }
}

void main() {
  uploadZipFile();
}
