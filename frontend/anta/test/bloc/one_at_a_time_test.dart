import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/one_at_a_time.dart';

/// An event a test holds: its handler waits on [gate], then records [name]
/// and emits it.
class _Step {
  final String name;
  final Completer<void> gate;

  _Step(this.name) : gate = Completer<void>();
}

class _StepBloc extends Bloc<_Step, List<String>> {
  final List<String> started = [];
  final List<String> finished = [];

  _StepBloc() : super(const []) {
    on<_Step>((step, emit) async {
      started.add(step.name);
      await step.gate.future;
      finished.add(step.name);
      emit([...state, step.name]);
    }, transformer: oneAtATime);
  }
}

/// The ordered queue the share and calendar blocs run their writes on: one
/// handler at a time, in arrival order, and a close that never waits on
/// the handler running.
void main() {
  test('events run one at a time, in the order they arrived', () async {
    final bloc = _StepBloc();
    addTearDown(bloc.close);
    final a = _Step('a');
    final b = _Step('b');
    final c = _Step('c');

    bloc
      ..add(a)
      ..add(b)
      ..add(c);
    await pumpEventQueue();
    expect(bloc.started, ['a']);

    c.gate.complete();
    b.gate.complete();
    await pumpEventQueue();
    expect(bloc.started, ['a'], reason: 'b and c wait for a');

    a.gate.complete();
    await pumpEventQueue();
    expect(bloc.finished, ['a', 'b', 'c']);
    expect(bloc.state, ['a', 'b', 'c']);
  });

  test('a running handler is not cancelled by a later event', () async {
    final bloc = _StepBloc();
    addTearDown(bloc.close);
    final a = _Step('a');
    final b = _Step('b');

    bloc.add(a);
    await pumpEventQueue();
    bloc.add(b);
    await pumpEventQueue();
    a.gate.complete();
    b.gate.complete();
    await pumpEventQueue();

    expect(bloc.finished, ['a', 'b']);
    expect(bloc.state, ['a', 'b']);
  });

  test('close completes while a handler is still waiting; that handler '
      'ends on its own, its late emit dropped without throwing, and an '
      'event not yet started never runs', () async {
    final bloc = _StepBloc();
    final a = _Step('a');
    final b = _Step('b');
    bloc
      ..add(a)
      ..add(b);
    await pumpEventQueue();

    var closed = false;
    unawaited(bloc.close().then((_) => closed = true));
    await pumpEventQueue();
    expect(closed, isTrue);

    final errors = <Object>[];
    await runZonedGuarded(() async {
      a.gate.complete();
      b.gate.complete();
      await pumpEventQueue();
    }, (error, _) => errors.add(error));

    expect(errors, isEmpty);
    expect(bloc.finished, ['a']);
    expect(bloc.started, ['a']);
    expect(bloc.state, isEmpty);
  });
}
