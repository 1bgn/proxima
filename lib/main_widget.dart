import 'package:flutter/material.dart';

import 'core/di/di_container.dart';
import 'core/routing/go_router_provider.dart';

class MainWidget extends StatefulWidget {
  const MainWidget({super.key});

  @override
  State<MainWidget> createState() => _MainWidgetState();
}

class _MainWidgetState extends State<MainWidget> {
  @override
  Widget build(BuildContext context) {
    final route = getIt.get<GoRouterProvider>();
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: route.goRouter(),
    );
  }
}
