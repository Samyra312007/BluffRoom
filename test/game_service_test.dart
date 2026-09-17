import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bluffroom/core/session_store.dart';
import 'package:bluffroom/models/game_events.dart' show ChallengeReveal;
import 'package:bluffroom/services/game_service.dart';
import 'package:bluffroom/services/socket_io_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSocket extends Mock implements SocketIoService {}

class _FakeSession extends SessionStore {
  _FakeSession() : super(_prefs);
  static final _prefs = _FakePrefs();
}

class _FakePrefs implements SharedPreferences {
  final Map<String, Object> _m = {};
  @override
  dynamic noSuchMethod(Invocation inv) {
    if (inv.memberName == #getString) {
      return _m[inv.positionalArguments[0] as String];
    }
    if (inv.memberName == #setString) {
      _m[inv.positionalArguments[0] as String] = inv.positionalArguments[1] as String;
      return Future.value(true);
    }
    if (inv.memberName == #remove) {
      _m.remove(inv.positionalArguments[0] as String);
      return Future.value(true);
    }
    return null;
  }
}

void main() {
  late _MockSocket socket;
  late GameService service;
  final events = StreamController<SocketEvent>.broadcast();
  final connStates = StreamController<ConnState>.broadcast();

  setUp(() {
    socket = _MockSocket();
    when(() => socket.events).thenAnswer((_) => events.stream);
    when(() => socket.connectionStates).thenAnswer((_) => connStates.stream);
    when(() => socket.state).thenReturn(ConnState.connected);
    when(() => socket.emit(any(), any())).thenReturn(null);
    when(() => socket.emitRaw(any())).thenReturn(null);
    service = GameService(socketService: socket, sessionStore: _FakeSession());
  });

  test('room_created applies room code, host flag and token', () async {
    events.add(SocketEvent(name: 'room_created', data: {
      'roomCode': 'abc12',
      'playerId': 's1',
      'isHost': true,
      'sessionToken': 'tok',
      'players': [
        {'id': 's1', 'name': 'Ana', 'isHost': true, 'cardCount': 0}
      ],
    }));
    await Future.delayed(Duration.zero);
    expect(service.roomCode, 'ABC12');
    expect(service.isHost, isTrue);
    expect(service.state.players.single.name, 'Ana');
  });

  test('cards_played updates rank and logs activity', () async {
    events.add(SocketEvent(name: 'room_created', data: {
      'roomCode': 'ABC12',
      'playerId': 's1',
      'isHost': false,
      'players': [
        {'id': 's1', 'name': 'Ana'},
        {'id': 's2', 'name': 'Bob'},
      ],
    }));
    await Future.delayed(Duration.zero);

    events.add(SocketEvent(name: 'cards_played', data: {
      'playerName': 'Bob',
      'count': 2,
      'declaredRank': '9',
      'pileCount': 2,
    }));
    await Future.delayed(Duration.zero);
    expect(service.state.currentRank, '9');
    expect(service.chat.last.text, contains('Bob'));
  });

  test('challenge_resolved feeds reveal stream and clears pile', () async {
    ChallengeReveal? got;
    service.revealStream.listen((r) => got = r);
    events.add(SocketEvent(name: 'challenge_resolved', data: {
      'challengerName': 'Ana',
      'challengedName': 'Bob',
      'wasBluff': true,
      'collectorName': 'Ana',
      'revealedCards': ['7C'],
    }));
    await Future.delayed(Duration.zero);
    expect(got, isNotNull);
    expect(service.lastReveal, isNotNull);
    expect(service.lastReveal!.wasBluff, isTrue);
    expect(service.state.pileCount, 0);
  });

  test('leaderboard event builds entries with self flag', () async {
    events.add(SocketEvent(name: 'leaderboard', data: {
      'leaderboard': [
        {'name': 'Ana', 'rank': 1, 'score': 90},
        {'name': 'Bob', 'rank': 2, 'score': 40},
      ],
    }));
    await Future.delayed(Duration.zero);
    expect(service.leaderboard, isNotNull);
    expect(service.leaderboard!.length, 2);
  });

  test('error events are surfaced on errors stream', () async {
    final errs = <String>[];
    service.errors.listen(errs.add);
    events.add(SocketEvent(name: 'error', data: {'message': 'Room is full'}));
    await Future.delayed(Duration.zero);
    expect(errs.single, 'Room is full');
  });

  test('player_left removes the player and logs', () async {
    events.add(SocketEvent(name: 'room_created', data: {
      'roomCode': 'ABC12',
      'playerId': 's1',
      'players': [
        {'id': 's1', 'name': 'Ana'},
        {'id': 's2', 'name': 'Bob'},
      ],
    }));
    await Future.delayed(Duration.zero);
    events.add(SocketEvent(name: 'player_left', data: {'playerName': 'Bob'}));
    await Future.delayed(Duration.zero);
    expect(service.state.players.length, 1);
    expect(service.chat.last.text, contains('Bob left'));
  });
}
