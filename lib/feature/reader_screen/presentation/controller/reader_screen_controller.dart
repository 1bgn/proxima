import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:proxima_reader/feature/reader_screen/application/service/reader_screen_service.dart';
import 'package:proxima_reader/feature/reader_screen/presentation/state/reader_screen_state.dart';
@LazySingleton()
class ReaderScreenController extends Cubit<ReaderScreenState>{
  final ReaderScreenService readerScreenService;
  ReaderScreenController(this.readerScreenService):super(ReaderScreenState());

}