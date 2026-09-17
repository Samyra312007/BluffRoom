import 'card.dart';

/// A player as seen from *outside* — no cards, ever.
class PlayerSummary {
  /// Stable server-side identity (may be empty for anonymous transports).
  final String id;

  /// Display name.
  final String name;

  /// Number of cards currently held (private info stays server-side).
  final int cardCount;

  /// Whether this seat is the (current) host.
  final bool isHost;

  const PlayerSummary({
    required this.id,
    required this.name,
    this.cardCount = 0,
    this.isHost = false,
  });

  static String? _string(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  factory PlayerSummary.fromJson(Map<String, dynamic> json) {
    return PlayerSummary(
      id: _string(json['id'] ?? json['playerId'] ?? json['socketId'] ?? json['sid']) ?? '',
      name: _string(json['name'] ?? json['playerName'] ?? json['nickname']) ?? 'Player',
      cardCount: _asInt(json['cardCount'] ?? json['cards'] ?? json['handSize'] ?? json['handCount']),
      isHost: _asBool(json['isHost'] ?? json['host'] ?? json['isLeader']),
    );
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
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

  PlayerSummary copyWith({String? id, String? name, int? cardCount, bool? isHost}) {
    return PlayerSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      cardCount: cardCount ?? this.cardCount,
      isHost: isHost ?? this.isHost,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerSummary && other.id == id && other.name == name && other.cardCount == cardCount && other.isHost == isHost;

  @override
  int get hashCode => Object.hash(id, name, cardCount, isHost);
}

/// The local player — the only one whose hand the app ever sees.
class SelfPlayer {
  final String id;
  final String name;
  final bool isHost;

  /// This player's private hand. Never sent to or received for anyone else.
  final List<PlayingCard> hand;

  /// Cards on the table attributed to this player (added on play, cleared on
  /// pile collection or round reset, per server events).
  final int tableCardCount;

  const SelfPlayer({
    required this.id,
    required this.name,
    required this.isHost,
    required this.hand,
    this.tableCardCount = 0,
  });

  SelfPlayer copyWith({
    String? id,
    String? name,
    bool? isHost,
    List<PlayingCard>? hand,
    int? tableCardCount,
  }) {
    return SelfPlayer(
      id: id ?? this.id,
      name: name ?? this.name,
      isHost: isHost ?? this.isHost,
      hand: hand ?? this.hand,
      tableCardCount: tableCardCount ?? this.tableCardCount,
    );
  }
}
