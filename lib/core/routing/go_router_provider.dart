
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:proxima_reader/feature/reader_screen/presentation/controller/reader_screen_controller.dart';
import 'package:proxima_reader/feature/reader_screen/domain/utils/reader_screen.dart';
import 'route_name.dart';

import '../di/di_container.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey =
GlobalKey(debugLabel: 'root');
final GlobalKey<StatefulNavigationShellState> _shellNavigatorKey =
GlobalKey(debugLabel: 'shell');

@LazySingleton()
class GoRouterProvider {
  GoRouter? _router;

  GoRouter goRouter() {
    _router ??= GoRouter(
        navigatorKey: _rootNavigatorKey,
        initialLocation: "/reader_route",
        routes: [
          GoRoute(
              path: "/reader_route",
              name: readerRoute,
              pageBuilder: (context, state) {
                return NoTransitionPage(
                    child: BlocProvider(
                      create: (context) => ReaderScreenController(getIt()),
                      child:Scaffold(body: FB2ReaderScreen(),backgroundColor: Colors.white,),
                    ));
              }),


        ]);
    return _router!;
  }
}
