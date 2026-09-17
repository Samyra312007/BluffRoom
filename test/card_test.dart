import 'package:flutter_test/flutter_test.dart';
import 'package:bluffroom/models/card.dart';

void main() {
  group('PlayingCard.tryParse', () {
    test('parses canonical map {rank, suit}', () {
      final c = PlayingCard.tryParse({'rank': 'A', 'suit': 'S'});
      expect(c, isNotNull);
      expect(c!.rank, 'A');
      expect(c.suit, 'S');
    });

    test('parses alternate map keys r/s', () {
      final c = PlayingCard.tryParse({'r': 'K', 's': 'H'});
      expect(c, isNotNull);
      expect(c!.rank, 'K');
      expect(c.suit, 'H');
    });

    test('parses wrapped {card: "AS"}', () {
      final c = PlayingCard.tryParse({'card': 'AS'});
      expect(c, isNotNull);
      expect(c!.code, 'AS');
    });

    test('parses 2-char code with lowercase and 10 normalization', () {
      expect(PlayingCard.tryParse('as')!.code, 'AS');
      expect(PlayingCard.tryParse('10H')!.code, 'TH');
      expect(PlayingCard.tryParse('QD')!.code, 'QD');
      expect(PlayingCard.tryParse('7c')!.code, '7C');
    });

    test('parses separator forms', () {
      expect(PlayingCard.tryParse('A-S')!.code, 'AS');
      expect(PlayingCard.tryParse('K S')!.code, 'KS');
    });

    test('parses emoji suit glyph', () {
      expect(PlayingCard.tryParse('A♠')!.code, 'AS');
      expect(PlayingCard.tryParse('10♥')!.code, 'TH');
    });

    test('returns null for garbage without throwing', () {
      expect(PlayingCard.tryParse(null), isNull);
      expect(PlayingCard.tryParse(''), isNull);
      expect(PlayingCard.tryParse('X'), isNull);
      expect(PlayingCard.tryParse('ZZ'), isNull);
      expect(PlayingCard.tryParse('AX'), isNull); // bad suit
      expect(PlayingCard.tryParse('11S'), isNull); // bad rank
      expect(PlayingCard.tryParse(42), isNull);
      expect(PlayingCard.tryParse({'rank': 'A'}), isNull); // missing suit
    });

    test('parses list of codes leniently', () {
      final cards = ['AS', '10H', 'bogus', {'rank': 'Q', 'suit': 'D'}]
          .map(PlayingCard.tryParse)
          .whereType<PlayingCard>()
          .toList();
      expect(cards.length, 3);
      expect(cards.map((c) => c.code), ['AS', 'TH', 'QD']);
    });
  });

  group('PlayingCard presentation', () {
    test('rankLabel renders 10 for T', () {
      expect(PlayingCard(rank: 'T', suit: 'S').rankLabel, '10');
      expect(PlayingCard(rank: 'A', suit: 'S').rankLabel, 'A');
    });

    test('suitSymbol mapping', () {
      expect(PlayingCard(rank: 'A', suit: 'S').suitSymbol, '♠');
      expect(PlayingCard(rank: 'A', suit: 'H').suitSymbol, '♥');
      expect(PlayingCard(rank: 'A', suit: 'D').suitSymbol, '♦');
      expect(PlayingCard(rank: 'A', suit: 'C').suitSymbol, '♣');
    });

    test('isRedSuit', () {
      expect(PlayingCard(rank: 'A', suit: 'H').isRedSuit, isTrue);
      expect(PlayingCard(rank: 'A', suit: 'D').isRedSuit, isTrue);
      expect(PlayingCard(rank: 'A', suit: 'S').isRedSuit, isFalse);
    });

    test('equality and hashCode', () {
      expect(PlayingCard(rank: 'A', suit: 'S'), PlayingCard(rank: 'A', suit: 'S'));
      expect(PlayingCard(rank: 'A', suit: 'S').hashCode, PlayingCard(rank: 'A', suit: 'S').hashCode);
    });
  });
}
