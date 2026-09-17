import 'package:flutter_test/flutter_test.dart';
import 'package:bluffroom/models/game_events.dart';
import 'package:bluffroom/models/player.dart';

void main() {
  group('CurrentRank', () {
    test('parses string rank', () {
      expect(CurrentRank.fromJson('Q'), 'Q');
      expect(CurrentRank.fromJson('10'), 'T');
    });

    test('parses numeric rank', () {
      expect(CurrentRank.fromJson(7), '7');
    });

    test('parses map forms', () {
      expect(CurrentRank.fromJson({'rank': 'K'}), 'K');
      expect(CurrentRank.fromJson({'value': 3}), '3');
    });

    test('parses rank names like SEVENS', () {
      expect(CurrentRank.fromJson('SEVENS'), '7');
      expect(CurrentRank.fromJson('queens'), 'Q');
      expect(CurrentRank.fromJson('Ace'), 'A');
    });

    test('returns null on garbage', () {
      expect(CurrentRank.fromJson(null), isNull);
      expect(CurrentRank.fromJson('Eleven'), isNull);
      expect(CurrentRank.fromJson([]), isNull);
    });
  });

  group('ChallengeReveal', () {
    test('parses canonical payload', () {
      final r = ChallengeReveal.fromJson({
        'challengerName': 'Ana',
        'challengedName': 'Bob',
        'wasBluff': true,
        'collectorName': 'Ana',
        'revealedCards': ['7S', '7H'],
      });
      expect(r.wasBluff, isTrue);
      expect(r.challengerName, 'Ana');
      expect(r.revealedCards.length, 2);
    });

    test('parses alternate keys and bool-as-string', () {
      final r = ChallengeReveal.fromJson({
        'challenger': 'X',
        'accusedName': 'Y',
        'bluff': 'false',
        'winnerName': 'Y',
        'cards': [{'rank': 'A', 'suit': 'S'}],
      });
      expect(r.wasBluff, isFalse);
      expect(r.collectorName, 'Y');
      expect(r.revealedCards.first.code, 'AS');
    });
  });

  group('LeaderboardEntry', () {
    test('parses and flags self by id', () {
      final e = LeaderboardEntry.fromJson(
        {'id': 'p1', 'name': 'Ana', 'rank': 1, 'score': 90},
        selfId: 'p1',
      );
      expect(e.isSelf, isTrue);
      expect(e.rank, 1);
    });

    test('parses position/points alternates', () {
      final e = LeaderboardEntry.fromJson(
        {'name': 'Bob', 'position': 2, 'points': '75'},
        selfName: 'Bob',
      );
      expect(e.rank, 2);
      expect(e.score, 75);
      expect(e.isSelf, isTrue);
    });
  });

  group('PlayerSummary', () {
    test('parses canonical and alternates', () {
      final a = PlayerSummary.fromJson({'id': 's1', 'name': 'Ana', 'cardCount': 5, 'isHost': true});
      expect(a.name, 'Ana');
      expect(a.cardCount, 5);
      expect(a.isHost, isTrue);

      final b = PlayerSummary.fromJson({'playerId': 's2', 'playerName': 'Bob', 'cards': 3, 'host': 1});
      expect(b.name, 'Bob');
      expect(b.cardCount, 3);
      expect(b.isHost, isTrue);
    });

    test('defaults gracefully on missing fields', () {
      final p = PlayerSummary.fromJson({});
      expect(p.name, 'Player');
      expect(p.cardCount, 0);
      expect(p.isHost, isFalse);
    });
  });

  group('TurnInfo', () {
    test('parses canonical payload', () {
      final t = TurnInfo.fromJson({'playerId': 's1', 'playerName': 'Ana', 'turnEndsAt': 123456});
      expect(t.playerId, 's1');
      expect(t.playerName, 'Ana');
      expect(t.endsAtMs, 123456);
    });

    test('parses deadline alternates', () {
      final t = TurnInfo.fromJson({'playerId': 's1', 'playerName': 'Ana', 'deadline': 42});
      expect(t.endsAtMs, 42);
    });
  });
}
