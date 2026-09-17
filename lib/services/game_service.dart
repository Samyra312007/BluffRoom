import 'dart:async';

import 'package:collection/collection.dart';

import '../core/config.dart';
import '../core/session_store.dart';
import '../models/card.dart';
import '../models/game_events.dart';
import '../models/player.dart';
import 'socket_io_service.dart';

/// How the room code is shared to other players, surfaced in the UI.
const String kShareMessageTemplate =
    'Join my BluffRoom game! 🃏\nRoom code: %CODE%\n\nGet the app and pick "Join Room".';

/// Network/protocol layer between the UI and the game server.
///
/// Responsibilities:
///  * connection lifecycle + automatic reconnection,
///  * session-token rejoin after app restart,
///  * translating raw Socket.IO events into typed model updates,
///  * emitting player actions with acks and duplicate suppression.
///
/// It holds **no game rules** — everything that decides turn order, card
/// values, scores or outcomes stays on the server. This class only records
/// what the server has told it, leniently and defensively.
class GameService {
  GameService({SocketIoService? socketService, required this.sessionStore}) : _socket = socketService ?? SocketIoService() {
    // Subscribe eagerly: the underlying socket only produces events after
    // connect(), but an early subscription guarantees nothing is missed.
    _eventsSub = _socket.events.listen(_onEvent);
    _connSub = _socket.connectionStates.listen(_onConnState);
  }

  final SocketIoService _socket;
  final SessionStore sessionStore;

  // ------------------------------------------------------------ live session
  String roomCode = '';
  String playerName = '';
  bool isHost = false;
  String selfId = '';

  /// Snapshot of the last known game state (players, pile, turn...).
  GameState state = GameState.empty;

  /// Latest challenge reveal for the overlay.
  ChallengeReveal? lastReveal;

  /// Latest pile collection notice.
  PileCollection? lastCollection;

  /// Final leaderboard when the game finishes.
  List<LeaderboardEntry>? leaderboard;

  /// Recent chat/log lines (lobby + table ticker).
  final List<ChatEntry> chat = <ChatEntry>[];

  /// Server-sent error strings, surfaced as snackbars by the UI layer.
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errors => _errorController.stream;

  /// Connection lifecycle, re-exposed from the underlying socket.
  Stream<ConnState> get connectionStates => _socket.connectionStates;
  ConnState get connState => _socket.state;

  final _stateController = StreamController<GameState>.broadcast();
  Stream<GameState> get stateStream => _stateController.stream;

  final _revealController = StreamController<ChallengeReveal>.broadcast();
  Stream<ChallengeReveal> get revealStream => _revealController.stream;

  final _collectionController = StreamController<PileCollection>.broadcast();
  Stream<PileCollection> get collectionStream => _collectionController.stream;

  final _leaderboardController = StreamController<List<LeaderboardEntry>>.broadcast();
  Stream<List<LeaderboardEntry>> get leaderboardStream => _leaderboardController.stream;

  final _chatController = StreamController<ChatEntry>.broadcast();
  Stream<ChatEntry> get chatStream => _chatController.stream;

  final _lobbyController = StreamController<void>.broadcast();
  Stream<void> get lobbyStream => _lobbyController.stream;

  final _gameStartedController = StreamController<void>.broadcast();
  Stream<void> get gameStartedStream => _gameStartedController.stream;

  /// Fired when the server says this player's session is no longer valid.
  final _kickedController = StreamController<String>.broadcast();
  Stream<String> get kickedStream => _kickedController.stream;

  bool _disposed = false;
  StreamSubscription<SocketEvent>? _eventsSub;
  StreamSubscription<ConnState>? _connSub;

  // --------------------------------------------------------------- lifecycle
  Future<void> init() async {}

  /// Connects and (best effort) rejoins with the stored session token.
  Future<void> connectAndRejoin() async {
    final token = sessionStore.token;
    await connect(token: token);
  }

  /// Establishes the socket connection with optional auth token.
  Future<void> connect({String? token}) async {
    final auth = <String, dynamic>{};
    if (token != null && token.isNotEmpty) {
      auth['token'] = token;
      auth['sessionToken'] = token;
    }
    _socket.connect(
      url: AppConfig.serverUrl,
      auth: auth,
      transportExtraHeaders: const {},
    );
  }

  void _onConnState(ConnState s) {
    if (_disposed) return;
    if (s == ConnState.connected) {
      // Fresh (re)connect: if we have a token and a room, ask the server to
      // re-attach us. Servers that don't implement rejoin will simply ack an
      // error, which we ignore.
      final token = sessionStore.token;
      if (token != null && token.isNotEmpty && roomCode.isNotEmpty) {
        _socket.emit('rejoin', {'roomCode': roomCode, 'token': token});
        _socket.emit('join', {'roomCode': roomCode, 'token': token});
      }
    }
  }

  // ------------------------------------------------------------ public API
  /// Creates a room. Returns true on success.
  Future<bool> createRoom(String name, int maxPlayers) async {
    playerName = name;
    try {
      final ack = await _socket.emitWithAck('create_room', {
        'playerName': name,
        'name': name,
        'maxPlayers': maxPlayers,
      });
      _applyRoomAck(ack, fallbackName: name);
      return true;
    } on SocketAckException {
      // Some servers ack with a bare payload; fall back to waiting for the
      // room_created broadcast event.
      return await _waitForEvent(
        'room_created',
        timeout: const Duration(seconds: 8),
        onEvent: (p) {
          _applyRoomAck(p, fallbackName: name);
        },
      );
    }
  }

  /// Joins an existing room by code.
  Future<bool> joinRoom(String name, String code) async {
    playerName = name;
    final c = code.trim().toUpperCase();
    try {
      final ack = await _socket.emitWithAck('join_room', {
        'roomCode': c,
        'playerName': name,
        'name': name,
      });
      _applyRoomAck(ack, fallbackName: name);
      return true;
    } on SocketAckException {
      return await _waitForEvent(
        'room_joined',
        timeout: const Duration(seconds: 8),
        onEvent: (p) {
          _applyRoomAck(p, fallbackName: name);
        },
      );
    }
  }

  /// Host starts the game.
  Future<bool> startGame() async {
    try {
      await _socket.emitWithAck('start_game', {'roomCode': roomCode});
      return true;
    } on SocketAckException {
      _socket.emit('start_game', {'roomCode': roomCode});
      return true;
    }
  }

  /// Plays [cards] declaring [declaredRank] as the current rank.
  Future<bool> playCards(List<PlayingCard> cards, String declaredRank) async {
    if (cards.isEmpty) return false;
    try {
      await _socket.emitWithAck('play_cards', {
        'roomCode': roomCode,
        'cards': cards.map((c) => c.code).toList(growable: false),
        'declaredRank': declaredRank,
        'declared': declaredRank,
        'count': cards.length,
      });
      return true;
    } on SocketAckException {
      // Keep the client responsive; the server will broadcast cards_played or
      // an error event if the play was rejected.
      _socket.emit('play_cards', {
        'roomCode': roomCode,
        'cards': cards.map((c) => c.code).toList(growable: false),
        'declaredRank': declaredRank,
        'count': cards.length,
      });
      return true;
    }
  }

  /// Challenges the current player's last play.
  Future<bool> challenge() async {
    try {
      await _socket.emitWithAck('challenge', {'roomCode': roomCode});
      return true;
    } on SocketAckException {
      _socket.emit('challenge', {'roomCode': roomCode});
      return true;
    }
  }

  /// Requests the current state from the server (best effort).
  void requestState() {
    _socket.emit('request_state', {'roomCode': roomCode});
    // Alternate naming used by some server versions.
    _socket.emit('get_state', {'roomCode': roomCode});
  }

  /// Host: restart the game (same room, fresh deal).
  Future<bool> playAgain() async {
    try {
      await _socket.emitWithAck('play_again', {'roomCode': roomCode});
      return true;
    } on SocketAckException {
      _socket.emit('play_again', {'roomCode': roomCode});
      _socket.emit('restart_game', {'roomCode': roomCode});
      return true;
    }
  }

  /// Leaves the current room and clears the session token.
  Future<void> leaveRoom() async {
    _socket.emit('leave_room', {'roomCode': roomCode});
    _socket.emit('leave', {'roomCode': roomCode});
    roomCode = '';
    state = GameState.empty;
    leaderboard = null;
    lastReveal = null;
    lastCollection = null;
    await sessionStore.save(token: '', lastRoomCode: '');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _eventsSub?.cancel();
    _connSub?.cancel();
    _socket.dispose();
    for (final c in [
      _stateController,
      _revealController,
      _collectionController,
      _leaderboardController,
      _chatController,
      _lobbyController,
      _gameStartedController,
      _kickedController,
      _errorController,
    ]) {
      c.close();
    }
  }

  // ------------------------------------------------------------- event pump
  void _onEvent(SocketEvent ev) {
    if (_disposed) return;
    final p = ev.payload;
    switch (ev.name) {
      case 'room_created':
      case 'room_joined':
        if (p != null) _applyRoomAck(p);
        _lobbyController.add(null);
        break;

      case 'players_update':
      case 'lobby_update':
        if (p != null) _applyLobbyUpdate(p);
        _lobbyController.add(null);
        break;

      case 'player_left':
        if (p != null) _applyPlayerLeft(p);
        _lobbyController.add(null);
        break;

      case 'game_started':
        // New round (host pressed Play Again): clear last round's results so
        // the app navigates back to the table instead of the leaderboard.
        leaderboard = null;
        lastReveal = null;
        lastCollection = null;
        _gameStartedController.add(null);
        break;

      case 'cards_dealt':
      case 'game_state':
      case 'state':
        if (p != null) _applyGameState(p);
        break;

      case 'turn_changed':
        if (p != null) _applyTurn(p);
        break;

      case 'cards_played':
        if (p != null) _applyCardsPlayed(p);
        break;

      case 'challenge_resolved':
        if (p != null) _applyChallengeResolved(p);
        break;

      case 'pile_collected':
        if (p != null) _applyPileCollected(p);
        break;

      case 'game_finished':
        if (p != null) _applyGameFinished(p);
        break;

      case 'leaderboard':
        if (p != null) _applyLeaderboard(p);
        break;

      case 'chat_message':
        if (p != null) {
          chat.add(ChatEntry(
            from: (p['from'] ?? p['playerName'] ?? p['name'] ?? 'Player').toString(),
            text: (p['text'] ?? p['message'] ?? '').toString(),
          ));
          if (chat.length > 50) chat.removeRange(0, chat.length - 50);
          _chatController.add(chat.last);
        }
        break;

      case 'error':
      case 'game_error':
      case 'join_error':
        final msg = (p?['message'] ?? p?['error'] ?? 'Something went wrong').toString();
        _errorController.add(msg);
        break;

      case 'kicked':
      case 'session_invalid':
        final msg = (p?['message'] ?? 'Your session ended').toString();
        _kickedController.add(msg);
        break;

      default:
        break;
    }
  }

  // ------------------------------------------------------- payload appliers
  void _applyRoomAck(Map<String, dynamic> p, {String? fallbackName}) {
    final code = (p['roomCode'] ?? p['roomId'] ?? p['room'] ?? '').toString().toUpperCase();
    if (code.isNotEmpty) roomCode = code;

    final token = (p['sessionToken'] ?? p['token'] ?? p['session'] ?? '').toString();
    if (token.isNotEmpty) {
      unawaited(sessionStore.save(token: token, playerName: playerName, lastRoomCode: roomCode));
    } else {
      unawaited(sessionStore.save(playerName: playerName, lastRoomCode: roomCode));
    }

    isHost = _asBool(p['isHost'] ?? p['host'] ?? false) || isHost;
    selfId = (p['playerId'] ?? p['id'] ?? selfId).toString();

    // Some servers include a full lobby snapshot in the join ack.
    if (p['players'] is List) {
      _applyLobbyUpdate(p);
    }
  }

  void _applyLobbyUpdate(Map<String, dynamic> p) {
    final playersRaw = p['players'];
    if (playersRaw is! List) return;

    final next = playersRaw
        .whereType<Map>()
        .map((m) => PlayerSummary.fromJson(m.cast<String, dynamic>()))
        .toList();

    // Preserve card counts if the update doesn't carry them (lobby events).
    if (next.every((pl) => pl.cardCount == 0) && state.players.isNotEmpty) {
      final byId = {for (final pl in state.players) pl.id: pl};
      final byName = {for (final pl in state.players) pl.name: pl};
      next.replaceRange(0, next.length, next.map((pl) {
        final prev = byId[pl.id] ?? byName[pl.name];
        return prev == null ? pl : pl.copyWith(cardCount: prev.cardCount);
      }));
    }

    // Identify self.
    final me = next.firstWhereOrNull((pl) => pl.id == selfId || pl.name == playerName);
    if (me != null) {
      isHost = me.isHost;
      selfId = selfId.isEmpty ? me.id : selfId;
    } else if (next.length == 1 && state.self == null) {
      // Single-player lobby snapshot: that's us.
      isHost = next.first.isHost;
      selfId = selfId.isEmpty ? next.first.id : selfId;
    }

    state = state.copyWith(players: next);
  }

  void _applyPlayerLeft(Map<String, dynamic> p) {
    final name = (p['playerName'] ?? p['name'] ?? p['player'] ?? '').toString();
    final id = (p['playerId'] ?? p['id'] ?? '').toString();
    final remaining = state.players.where((pl) => pl.id != id && pl.name != name).toList();
    state = state.copyWith(players: remaining);
    chat.add(ChatEntry(from: 'system', text: '$name left the room'));
    _chatController.add(chat.last);
  }

  void _applyGameState(Map<String, dynamic> p) {
    // Full snapshot: merge into current state.
    final playersRaw = p['players'];
    if (playersRaw is List) {
      _applyLobbyUpdate(p);
    }

    final handRaw = p['hand'] ?? p['yourCards'] ?? p['cards'] ?? p['myCards'];
    if (handRaw is List) {
      final hand = handRaw.map(PlayingCard.tryParse).whereType<PlayingCard>().toList();
      final prevSelf = state.self;
      state = state.copyWith(
        self: SelfPlayer(
          id: selfId,
          name: playerName,
          isHost: isHost,
          hand: hand,
          tableCardCount: prevSelf?.tableCardCount ?? 0,
        ),
      );
    }

    final rank = CurrentRank.fromJson(p['currentRank'] ?? p['rank'] ?? p['declaredRank']);
    if (rank != null) {
      state = state.copyWith(currentRank: rank);
    }

    final pile = p['pileCount'] ?? p['pile'] ?? p['discardCount'] ?? p['discardPile'];
    final pileCount = _asIntOrNull(pile);
    if (pileCount != null) {
      state = state.copyWith(pileCount: pileCount);
    }

    if (p['turn'] != null || p['currentTurn'] != null) {
      final t = p['turn'] ?? p['currentTurn'];
      _applyTurn(t is Map ? Map<String, dynamic>.from(t) : {'playerId': t.toString(), 'name': t.toString()});
    } else if (p['currentPlayerId'] != null || p['currentPlayer'] != null) {
      final id = (p['currentPlayerId'] ?? p['currentPlayer'])?.toString() ?? '';
      final byId = state.players.firstWhereOrNull((pl) => pl.id == id);
      _applyTurn({'playerId': id, 'name': byId?.name ?? id});
    }

    if (p['challengeOpen'] is bool) {
      state = state.copyWith(challengeOpen: p['challengeOpen'] as bool);
    }
  }

  void _applyTurn(Map<String, dynamic> p) {
    final info = TurnInfo.fromJson(p);
    final challengeOpen = p['canChallenge'] is bool ? p['canChallenge'] as bool : state.challengeOpen;

    state = state.copyWith(turn: info, challengeOpen: challengeOpen);

    // After the first turn change the game table is authoritative — reflect
    // the turn player's name into our player list if it's missing.
    if (state.players.every((pl) => pl.id != info.playerId) && info.playerId.isNotEmpty) {
      final next = [...state.players];
      final idx = next.indexWhere((pl) => pl.name == info.playerName);
      if (idx >= 0) {
        next[idx] = next[idx].copyWith(id: info.playerId);
        state = state.copyWith(players: next);
      }
    }
  }

  void _applyCardsPlayed(Map<String, dynamic> p) {
    final name = (p['playerName'] ?? p['name'] ?? 'Player').toString();
    final count = _asIntOrNull(p['count']) ?? _asIntOrNull(p['cardCount']) ?? 0;
    final declared = CurrentRank.fromJson(p['declaredRank'] ?? p['declared'] ?? p['rank']);

    // Remove played cards from our hand when we were the player.
    final handRaw = p['hand'] ?? p['yourHand'];
    if (handRaw is List) {
      final hand = handRaw.map(PlayingCard.tryParse).whereType<PlayingCard>().toList();
      final prev = state.self;
      state = state.copyWith(
        self: prev?.copyWith(hand: hand) ??
            SelfPlayer(id: selfId, name: playerName, isHost: isHost, hand: hand),
      );
    } else if (name == playerName) {
      // No fresh hand in the payload: keep the optimistic removal the UI
      // already applied when the play was made. Never guess card identities.
    }

    if (declared != null) {
      state = state.copyWith(currentRank: declared);
    }

    chat.add(ChatEntry(from: 'system', text: '$name played ${count <= 0 ? 'some' : count} card${count == 1 ? '' : 's'} as $declared'));
    _chatController.add(chat.last);
    _stateController.add(state);
  }

  void _applyChallengeResolved(Map<String, dynamic> p) {
    final reveal = ChallengeReveal.fromJson(p);
    lastReveal = reveal;
    _revealController.add(reveal);

    // The loser picks up the pile.
    final loser = reveal.wasBluff ? reveal.challengedName : reveal.challengerName;
    state = state.copyWith(pileCount: 0, challengeOpen: false);
    chat.add(ChatEntry(from: 'system', text: '${reveal.challengedName} was ${reveal.wasBluff ? 'bluffing!' : 'truthful.'} $loser picks up the pile.'));
    _chatController.add(chat.last);
  }

  void _applyPileCollected(Map<String, dynamic> p) {
    final c = PileCollection.fromJson(p);
    lastCollection = c;
    _collectionController.add(c);
    state = state.copyWith(pileCount: 0);
    chat.add(ChatEntry(from: 'system', text: '${c.playerName} collected ${c.cardCount} card${c.cardCount == 1 ? '' : 's'}.'));
    _chatController.add(chat.last);
    _stateController.add(state);
  }

  void _applyGameFinished(Map<String, dynamic> p) {
    // Winner info may come inline.
    final lb = p['leaderboard'];
    if (lb is List) {
      _applyLeaderboard(p);
    }
    _stateController.add(state);
  }

  void _applyLeaderboard(Map<String, dynamic> p) {
    final raw = p['leaderboard'] ?? p['entries'] ?? p['results'];
    if (raw is! List) return;
    leaderboard = raw
        .whereType<Map>()
        .map((m) => LeaderboardEntry.fromJson(m.cast<String, dynamic>(), selfId: selfId, selfName: playerName))
        .toList();
    _leaderboardController.add(leaderboard!);
  }

  // ---------------------------------------------------------------- helpers
  Future<bool> _waitForEvent(
    String eventName, {
    required Duration timeout,
    required void Function(Map<String, dynamic>) onEvent,
  }) async {
    try {
      final p = await _socket.events.firstWhere((e) => e.name == eventName).timeout(timeout);
      final payload = p.payload;
      if (payload != null) onEvent(payload);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  static bool _asBool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  static int? _asIntOrNull(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
