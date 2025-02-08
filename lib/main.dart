import 'package:flutter/material.dart';

import 'core/di/di_container.dart';
import 'main_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await initLocalStorage();
  initDi();

  runApp(const MainWidget());
}
