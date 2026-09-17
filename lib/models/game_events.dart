import 'card.dart';
import 'player.dart';

/// Current rank to call on the table, e.g. `7` or `Q`.
class CurrentRank {
  static String? fromJson(Object? raw) {
    if (raw is Map) return _asRank(raw['rank'] ?? raw['value'] ?? raw['current'] ?? raw['card']);
    if (raw is String || raw is num) return _asRank(raw);
    return null;
  }

  static String? _asRank(Object? raw) {
    if (raw == null) return null;
    var s = raw.toString().trim().toUpperCase();
    if (s.length >= 3) {
      // Long forms like "SEVENS"/"SEVEN"/"QUEENS": match by prefix.
      const names = {
        'A': 'ACE', '2': 'TWO', '3': 'THREE', '4': 'FOUR', '5': 'FIVE',
        '6': 'SIX', '7': 'SEVEN', '8': 'EIGHT', '9': 'NINE', 'T': 'TEN',
        'J': 'JACK', 'Q': 'QUEEN', 'K': 'KING',
      };
      for (final entry in names.entries) {
        if (s.startsWith(entry.value) || s.startsWith('${entry.value}S')) {
          return entry.key;
        }
      }
      return null;
    }
    if (s == '10') s = 'T';
    if (PlayingCard.knownRanks.contains(s)) return s;
    return null;
  }
}

/// Who is currently playing.
class TurnInfo {
  final String playerId;
  final String playerName;
  final int endsAtMs;

  const TurnInfo({required this.playerId, required this.playerName, this.endsAtMs = 0});

  factory TurnInfo.fromJson(Map<String, dynamic> json) {
    String? id = (json['playerId'] ?? json['player'] ?? json['id'])?.toString();
    if (id == null || id.isEmpty) id = (json['name'] ?? json['playerName'])?.toString() ?? '';
    final endsAt = _asInt(json['turnEndsAt'] ?? json['deadline'] ?? json['endsAt'] ?? json['turnDeadline']);
    return TurnInfo(
      playerId: id,
      playerName: (json['playerName'] ?? json['name'] ?? 'Player').toString(),
      endsAtMs: endsAt,
    );
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }
}

/// Full client-side snapshot of the game.
class GameState {
  /// Opponents — never contains cards.
  final List<PlayerSummary> players;

  /// This device's player, including the private hand.
  final SelfPlayer? self;

  /// Rank that must be declared this round, e.g. `7`.
  final String? currentRank;

  /// Whose turn it is.
  final TurnInfo? turn;

  /// Total cards face-down in the central pile.
  final int pileCount;

  /// Whether a challenge window is currently open (bluff button enabled).
  final bool challengeOpen;

  const GameState({
    required this.players,
    required this.self,
    required this.currentRank,
    required this.turn,
    required this.pileCount,
    required this.challengeOpen,
  });

  static const GameState empty = GameState(
    players: [],
    self: null,
    currentRank: null,
    turn: null,
    pileCount: 0,
    challengeOpen: false,
  );

  GameState copyWith({
    List<PlayerSummary>? players,
    SelfPlayer? self,
    Object? currentRank = _sentinel,
    TurnInfo? turn,
    int? pileCount,
    bool? challengeOpen,
  }) {
    return GameState(
      players: players ?? this.players,
      self: self ?? this.self,
      currentRank: identical(currentRank, _sentinel) ? this.currentRank : currentRank as String?,
      turn: turn ?? this.turn,
      pileCount: pileCount ?? this.pileCount,
      challengeOpen: challengeOpen ?? this.challengeOpen,
    );
  }

  static const Object _sentinel = Object();
}

/// Result of a resolved challenge, rendered by the reveal overlay.
class ChallengeReveal {
  final String challengerName;
  final String challengedName;
  final bool wasBluff;
  final String collectorName;
  final List<PlayingCard> revealedCards;

  const ChallengeReveal({
    required this.challengerName,
    required this.challengedName,
    required this.wasBluff,
    required this.collectorName,
    required this.revealedCards,
  });

  static List<PlayingCard> _cards(Object? raw) {
    final list = raw is List ? raw : const [];
    return list.map(PlayingCard.tryParse).whereType<PlayingCard>().toList();
  }

  factory ChallengeReveal.fromJson(Map<String, dynamic> json) {
    return ChallengeReveal(
      challengerName: (json['challengerName'] ?? json['challenger'] ?? json['byPlayerName'] ?? 'Player').toString(),
      challengedName: (json['challengedName'] ?? json['accusedName'] ?? json['targetName'] ?? json['playerName'] ?? 'Player').toString(),
      wasBluff: _asBool(json['wasBluff'] ?? json['bluff'] ?? json['isBluff'] ?? json['result']),
      collectorName: (json['collectorName'] ?? json['winnerName'] ?? json['collector'] ?? json['byPlayerName'] ?? 'Player').toString(),
      revealedCards: _cards(json['revealedCards'] ?? json['cards'] ?? json['playedCards'] ?? json['pile']),
    );
  }

  static bool _asBool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == '1' || s == 'bluff' || s == 'yes';
    }
    return false;
  }
}

/// A player picking up the pile.
class PileCollection {
  final String playerName;
  final int cardCount;
  final String? reason; // 'challenge' | 'timeout' | 'round_end'

  const PileCollection({required this.playerName, required this.cardCount, this.reason});

  factory PileCollection.fromJson(Map<String, dynamic> json) {
    return PileCollection(
      playerName: (json['playerName'] ?? json['name'] ?? json['player'] ?? 'Player').toString(),
      cardCount: _asInt(json['cardCount'] ?? json['count'] ?? json['cards'] ?? json['pileSize']),
      reason: json['reason']?.toString(),
    );
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }
}

/// One row of the final leaderboard.
class LeaderboardEntry {
  final String name;
  final int rank;
  final int score;
  final bool isSelf;

  const LeaderboardEntry({required this.name, required this.rank, required this.score, required this.isSelf});

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json, {String? selfId, String? selfName}) {
    String? name = (json['name'] ?? json['playerName'] ?? json['player'] ?? json['nickname'])?.toString();
    final id = (json['id'] ?? json['playerId'])?.toString();
    final isSelf = (selfId != null && id == selfId) || (name != null && name == selfName);
    return LeaderboardEntry(
      name: name ?? 'Player',
      rank: _asInt(json['rank'] ?? json['position'] ?? json['place'] ?? json['placement']),
      score: _asInt(json['score'] ?? json['points'] ?? json['total']),
      isSelf: isSelf,
    );
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }
}

/// Lightweight chat line shown in the lobby/game ticker.
class ChatEntry {
  final String from;
  final String text;
  final DateTime at;

  ChatEntry({required this.from, required this.text, DateTime? at}) : at = at ?? DateTime.now();
}
