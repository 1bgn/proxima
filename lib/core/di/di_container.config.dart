// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:proxima_reader/core/routing/go_router_provider.dart' as _i736;
import 'package:proxima_reader/feature/reader_screen/application/service/reader_screen_service.dart'
    as _i760;
import 'package:proxima_reader/feature/reader_screen/presentation/controller/reader_screen_controller.dart'
    as _i424;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    gh.lazySingleton<_i736.GoRouterProvider>(() => _i736.GoRouterProvider());
    gh.lazySingleton<_i760.ReaderScreenService>(
        () => _i760.ReaderScreenService());
    gh.lazySingleton<_i424.ReaderScreenController>(
        () => _i424.ReaderScreenController(gh<_i760.ReaderScreenService>()));
    return this;
  }
}
