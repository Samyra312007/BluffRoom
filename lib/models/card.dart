/// A single playing card.
///
/// The card identity is only meaningful to the player holding it: the server
/// sends each client only its own hand, so no other player's cards ever exist
/// in app memory.
class PlayingCard {
  /// Canonical rank symbols accepted from the server.
  ///
  /// Letters are case-insensitive on input (`k` == `K`); the canonical form is
  /// always the uppercase letter. `10` is normalized to `T`.
  static const Set<String> knownRanks = {'2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'};

  /// Canonical suit symbols accepted from the server.
  static const Set<String> knownSuits = {'S', 'H', 'D', 'C'};

  /// Canonical short rank code, e.g. `A`, `T`, `K`.
  final String rank;

  /// Canonical suit code: `S`, `H`, `D` or `C`.
  final String suit;

  const PlayingCard({required this.rank, required this.suit});

  /// Parses a card from whatever shorthand the server uses.
  ///
  /// Supported input shapes:
  /// * `{ "rank": "A", "suit": "S" }` (also accepts `r`/`s` keys)
  /// * `{ "card": "AS" }` or `{ "card": { "rank": "A", "suit": "S" } }`
  /// * `"AS"`, `"as"`, `"10S"` (10 normalized to `T`)
  /// * `"A-S"`, `"A S"`, `"A♠"` (emoji suit glyphs)
  ///
  /// Returns `null` for anything unparseable rather than throwing, so one
  /// weird payload can never crash the table.
  static PlayingCard? tryParse(Object? raw) {
    if (raw == null) return null;
    if (raw is PlayingCard) return raw;

    if (raw is Map) {
      final inner = raw['card'] ?? raw['code'];
      if (inner != null && inner is! Map) return tryParse(inner);
      final rank = _asRank(raw['rank'] ?? raw['r'] ?? raw['value']);
      final suit = _asSuit(raw['suit'] ?? raw['s']);
      if (rank == null || suit == null) return null;
      return PlayingCard(rank: rank, suit: suit);
    }

    return _fromCode(raw.toString());
  }

  /// Parses a compact code like `AS`, `10H`, `qd`, `K-S`, `A♠`.
  static PlayingCard? _fromCode(String code) {
    var c = code.trim().replaceAll(RegExp(r'[\s_-]'), '');
    if (c.length < 2) return null;

    String suitPart;
    String rankPart;
    if (c.codeUnits.last > 127) {
      // Last char is a non-ASCII suit glyph (♠ ♥ ♦ ♣).
      suitPart = c.substring(c.length - 1);
      rankPart = c.substring(0, c.length - 1);
    } else {
      suitPart = c.substring(c.length - 1);
      rankPart = c.substring(0, c.length - 1);
    }

    final rank = _asRank(rankPart);
    final suit = _asSuit(suitPart);
    if (rank == null || suit == null) return null;
    return PlayingCard(rank: rank, suit: suit);
  }

  static String? _asRank(Object? raw) {
    if (raw == null) return null;
    var r = raw.toString().trim().toUpperCase();
    if (r == '10') r = 'T';
    return knownRanks.contains(r) ? r : null;
  }

  static String? _asSuit(Object? raw) {
    if (raw == null) return null;
    switch (raw.toString().trim()) {
      case 'S':
      case '♠':
      case 's':
      case 'spades':
      case 'Spades':
        return 'S';
      case 'H':
      case '♥':
      case 'h':
      case 'hearts':
      case 'Hearts':
        return 'H';
      case 'D':
      case '♦':
      case 'd':
      case 'diamonds':
      case 'Diamonds':
        return 'D';
      case 'C':
      case '♣':
      case 'c':
      case 'clubs':
      case 'Clubs':
        return 'C';
      default:
        return null;
    }
  }

  // ------------------------------------------------------------ presentation
  String get rankLabel => switch (rank) {
        'T' => '10',
        _ => rank,
      };

  String get suitSymbol => switch (suit) {
        'S' => '♠',
        'H' => '♥',
        'D' => '♦',
        'C' => '♣',
        _ => suit,
      };

  bool get isRedSuit => suit == 'H' || suit == 'D';

  /// Short code like `AS`, used for local list comparisons only.
  String get code => '$rank$suit';

  @override
  String toString() => code;

  @override
  bool operator ==(Object other) => other is PlayingCard && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => Object.hash(rank, suit);
}
