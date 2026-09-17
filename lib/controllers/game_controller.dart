import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/haptics.dart';
import '../core/session_store.dart';
import '../models/game_events.dart';
import '../models/player.dart';
import '../services/game_service.dart';
import '../services/socket_io_service.dart';

/// UI-facing controller.
///
/// The controller mirrors [GameService] into observable state for the screens
/// and adds client-side UX guards. It never decides game outcomes: the guards
/// only prevent the user from firing obviously invalid requests (playing out
/// of turn, challenging themselves, double-tapping). The server still
/// validates everything authoritatively and the UI obeys server events.
class GameController extends ChangeNotifier {
  GameController({required GameService gameService, required this.session}) : _service = gameService {
    _subs.add(_service.stateStream.listen((_) {
      _syncTimerFromState();
      notifyListeners();
    }));
    _subs.add(_service.revealStream.listen(_onReveal));
    _subs.add(_service.collectionStream.listen((_) => notifyListeners()));
    _subs.add(_service.leaderboardStream.listen(_onLeaderboard));
    _subs.add(_service.errors.listen(_onError));
    _subs.add(_service.kickedStream.listen(_onKicked));
    _subs.add(_service.chatStream.listen((_) => notifyListeners()));
    _subs.add(_service.gameStartedStream.listen((_) => notifyListeners()));
    _subs.add(_service.lobbyStream.listen((_) => notifyListeners()));
    _subs.add(_service.connectionStates.listen(_onConnState));
  }

  final GameService _service;
  final SessionStore session;

  final List<StreamSubscription<dynamic>> _subs = [];

  // ------------------------------------------------------------- UI state
  ConnState connState = ConnState.disconnected;
  bool busy = false; // any in-flight action; gates duplicate taps
  String? lastError;

  /// Cards the user has selected in the hand strip (indices into the hand).
  final Set<int> selectedCardIndexes = {};

  /// 0 when no timer running.
  int secondsLeft = 0;
  Timer? _tick;
  int _turnEndsAtMs = 0;

  /// Set while the challenge-reveal overlay should be visible.
  ChallengeReveal? activeReveal;

  GameService get service => _service;

  GameState get state => _service.state;
  String get roomCode => _service.roomCode;
  bool get isHost => _service.isHost;
  String get playerName => _service.playerName;
  List<ChatEntry> get chat => _service.chat;
  List<LeaderboardEntry>? get leaderboard => _service.leaderboard;

  List<PlayerSummary> get opponents {
    final me = state.self;
    return state.players.where((p) => me == null || (p.id != me.id && p.name != me.name)).toList();
  }

  int get handCount => state.self?.hand.length ?? 0;

  bool get isMyTurn {
    final turn = state.turn;
    if (turn == null) return false;
    final me = state.self;
    if (me == null) return false;
    return turn.playerId.isNotEmpty
        ? turn.playerId == me.id || turn.playerName == me.name
        : turn.playerName == me.name;
  }

  bool get canPlay => isMyTurn && !busy && selectedCardIndexes.isNotEmpty;
  bool get canChallenge => isMyTurn && !busy && state.challengeOpen && selectedCardIndexes.isEmpty;

  // ------------------------------------------------------------ connection
  Future<void> connectWithRejoin() => _service.connectAndRejoin();

  void _onConnState(ConnState s) {
    final changed = connState != s;
    connState = s;
    if (!changed) return;
    if (s == ConnState.connected) {
      Haptics.light();
      pushSnack('Connected');
      // Ask the server for a fresh snapshot after reconnect.
      if (_service.roomCode.isNotEmpty) _service.requestState();
    } else if (s == ConnState.reconnecting) {
      Haptics.medium();
      pushSnack('Connection lost — reconnecting…');
    } else if (s == ConnState.error) {
      pushSnack('Connection problem — retrying…');
    }
    notifyListeners();
  }

  // --------------------------------------------------------------- actions
  Future<bool> createRoom(String name, int maxPlayers) async {
    if (busy) return false;
    busy = true;
    notifyListeners();
    try {
      final ok = await _service.createRoom(name, maxPlayers);
      if (ok) Haptics.success();
      return ok;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> joinRoom(String name, String code) async {
    if (busy) return false;
    busy = true;
    notifyListeners();
    try {
      final ok = await _service.joinRoom(name, code);
      if (ok) Haptics.success();
      return ok;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> startGame() async {
    if (busy || !isHost) return false;
    busy = true;
    notifyListeners();
    try {
      return await _service.startGame();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Toggles selection of a hand card. Max [AppConfig.maxCardsPerPlay].
  void toggleCard(int index) {
    if (index < 0 || index >= handCount) return;
    if (selectedCardIndexes.contains(index)) {
      selectedCardIndexes.remove(index);
      Haptics.light();
    } else {
      if (selectedCardIndexes.length >= AppConfig.maxCardsPerPlay) {
        pushSnack('You can play at most ${AppConfig.maxCardsPerPlay} cards');
        Haptics.warning();
        return;
      }
      selectedCardIndexes.add(index);
      Haptics.light();
    }
    notifyListeners();
  }

  /// Plays the selected cards, declaring the current table rank.
  Future<void> playSelected() async {
    final me = state.self;
    if (me == null) return;
    if (!isMyTurn) {
      pushSnack("It's not your turn");
      Haptics.warning();
      return;
    }
    if (selectedCardIndexes.isEmpty) {
      pushSnack('Select cards to play first');
      return;
    }
    final rank = state.currentRank;
    if (rank == null) {
      pushSnack('Waiting for the table rank…');
      return;
    }
    final cards = selectedCardIndexes.map((i) => me.hand[i]).toList();
    if (cards.isEmpty || cards.length > AppConfig.maxCardsPerPlay) return;

    busy = true;
    selectedCardIndexes.clear();
    notifyListeners();

    // Optimistically remove the cards from the local hand; the next
    // authoritative cards_played / cards_dealt event will reconcile.
    final remaining = me.hand.where((c) => !cards.contains(c)).toList();
    _service.state = _service.state.copyWith(self: me.copyWith(hand: remaining));

    Haptics.medium();
    await _service.playCards(cards, rank);
    busy = false;
    notifyListeners();
  }

  /// Fires a bluff challenge with guards: not on self, not out of turn.
  Future<void> challenge() async {
    if (!canChallenge) {
      if (!isMyTurn) pushSnack("It's not your turn");
      return;
    }
    final turn = state.turn;
    if (turn != null && (turn.playerId == state.self?.id || turn.playerName == playerName)) {
      pushSnack("You can't challenge your own play");
      Haptics.warning();
      return;
    }
    busy = true;
    notifyListeners();
    Haptics.heavy();
    await _service.challenge();
    busy = false;
    notifyListeners();
  }

  Future<void> playAgain() async {
    if (busy || !isHost) return;
    busy = true;
    notifyListeners();
    try {
      await _service.playAgain();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> leaveRoom() async {
    stopTimer();
    selectedCardIndexes.clear();
    activeReveal = null;
    await _service.leaveRoom();
    notifyListeners();
  }

  // ---------------------------------------------------------- server events
  void _onReveal(ChallengeReveal reveal) {
    activeReveal = reveal;
    Haptics.heavy();
    notifyListeners();
  }

  void _onLeaderboard(List<LeaderboardEntry> lb) {
    stopTimer();
    activeReveal = null;
    Haptics.success();
    notifyListeners();
  }

  void _onError(String message) {
    lastError = message;
    pushSnack(message);
    Haptics.warning();
    busy = false;
    notifyListeners();
  }

  void _onKicked(String message) {
    kickedMessage = message;
    stopTimer();
    selectedCardIndexes.clear();
    notifyListeners();
  }

  String? kickedMessage;

  // ------------------------------------------------------------------ timer
  void _syncTimerFromState() {
    final endsAt = state.turn?.endsAtMs ?? 0;
    if (endsAt > 0 && endsAt != _turnEndsAtMs) {
      _turnEndsAtMs = endsAt;
      startTimerFromDeadline(endsAt);
    } else if (endsAt == 0 && state.turn != null) {
      // Server gave no deadline: run a local countdown for display only.
      if (secondsLeft == 0) startTimer(AppConfig.turnSeconds);
    } else if (state.turn == null) {
      stopTimer();
    }
  }

  /// Starts a countdown from full seconds (display-only fallback).
  void startTimer(int seconds) {
    stopTimer();
    secondsLeft = seconds;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    notifyListeners();
  }

  /// Starts a countdown synchronized to a server epoch-milliseconds deadline.
  void startTimerFromDeadline(int endsAtMs) {
    final remaining = DateTime.fromMillisecondsSinceEpoch(endsAtMs).difference(DateTime.now()).inSeconds;
    startTimer(remaining.clamp(0, AppConfig.turnSeconds));
  }

  void _onTick() {
    if (secondsLeft <= 1) {
      stopTimer();
      if (isMyTurn) {
        pushSnack("Time's up — turn passed");
        Haptics.warning();
      }
    } else {
      secondsLeft--;
      if (secondsLeft <= 5) Haptics.light();
    }
    notifyListeners();
  }

  void stopTimer() {
    _tick?.cancel();
    _tick = null;
    secondsLeft = 0;
    _turnEndsAtMs = 0;
  }

  // ----------------------------------------------------------------- helpers
  final List<void Function(String)> _snackTargets = [];

  /// Registers a UI callback used to show snackbars without a BuildContext.
  void addSnackTarget(void Function(String) cb) => _snackTargets.add(cb);

  /// Removes a previously registered snackbar callback.
  void removeSnackTarget(void Function(String) cb) => _snackTargets.remove(cb);

  /// Pushes a message to registered snack targets.
  void pushSnack(String message) {
    for (final cb in List.of(_snackTargets)) {
      cb(message);
    }
  }

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    stopTimer();
    super.dispose();
  }
}
