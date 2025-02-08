import 'package:freezed_annotation/freezed_annotation.dart';
part 'reader_screen_state.freezed.dart';

@freezed
class ReaderScreenState with _$ReaderScreenState{
  const factory ReaderScreenState ({
    @Default(0)final int stateScreen
}) = _ReaderScreenState;
}