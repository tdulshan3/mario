/// Reading fields out of JSON whose shape nobody guarantees.
///
/// `m['correctIndex'] as num?` throws `type 'List(dynamic)' is not a subtype
/// of type 'num?'` the moment a model answers with `[0]` instead of `0` — which
/// is exactly what took quiz generation down. The same hazard applies to every
/// field of every model reply, every third-party search response, and every
/// stored artifact written by an older build.
///
/// The rule these functions encode: coerce what is unambiguous, return null
/// for anything else, and never guess. A dropped question is recoverable; a
/// question built from a guessed value is not.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/json_coercion.dart';

void main() {
  group('asInt', () {
    test('reads a plain integer', () => expect(asInt(3), 3));
    test('truncates a double', () => expect(asInt(3.7), 3));

    test('unwraps a single-element list — the crash that started this', () {
      // A model asked for an integer answers `[0]`.
      expect(asInt([0]), 0);
      expect(asInt(['2']), 2);
    });

    test('refuses a multi-element list rather than picking one', () {
      // Two "correct" answers is a broken question, not a question with the
      // first answer. Returning null drops it.
      expect(asInt([0, 2]), isNull);
    });

    test('parses a quoted number', () {
      expect(asInt('3'), 3);
      expect(asInt(' 4 '), 4);
      expect(asInt('3.9'), 3);
    });

    test('returns null for prose, objects, and null', () {
      expect(asInt('the first one'), isNull);
      expect(asInt({'value': 1}), isNull);
      expect(asInt(null), isNull);
    });
  });

  group('asDouble', () {
    test('reads numbers', () {
      expect(asDouble(2), 2.0);
      expect(asDouble(2.5), 2.5);
    });

    test('reads a mark written as a fraction', () {
      // "How many marks?" -> "3/4" is a routine small-model answer.
      expect(asDouble('3/4'), 3.0);
    });

    test('unwraps a single-element list', () => expect(asDouble([1.5]), 1.5));

    test('returns null for unreadable values', () {
      expect(asDouble('good effort'), isNull);
      expect(asDouble([1, 2]), isNull);
      expect(asDouble(null), isNull);
    });
  });

  group('asString', () {
    test('passes a string through', () => expect(asString('hi'), 'hi'));

    test('stringifies a number or bool rather than failing', () {
      // A "question" field answered with a bare number is still usable text.
      expect(asString(42), '42');
      expect(asString(true), 'true');
    });

    test('unwraps a single-element list', () => expect(asString(['a']), 'a'));

    test('refuses a multi-element list rather than joining arbitrarily', () {
      expect(asString(['a', 'b']), isNull);
    });

    test('returns null for an object or null', () {
      expect(asString({'a': 1}), isNull);
      expect(asString(null), isNull);
    });

    test('asStringOr supplies the fallback', () {
      expect(asStringOr(null), '');
      expect(asStringOr(null, 'Quiz'), 'Quiz');
      expect(asStringOr('given', 'Quiz'), 'given');
    });
  });

  group('asBool', () {
    test('reads a bool', () => expect(asBool(true), isTrue));

    test('reads the strings a model emits for one', () {
      expect(asBool('true'), isTrue);
      expect(asBool('TRUE'), isTrue);
      expect(asBool('false'), isFalse);
    });

    test('treats a number as truthiness', () {
      expect(asBool(1), isTrue);
      expect(asBool(0), isFalse);
    });

    test('honours the fallback for anything unreadable', () {
      expect(asBool(null, fallback: true), isTrue);
      expect(asBool('maybe', fallback: true), isTrue);
      expect(asBool(null), isFalse);
    });
  });

  group('asStringList', () {
    test('reads a list of strings', () {
      expect(asStringList(['a', 'b']), ['a', 'b']);
    });

    test('stringifies numeric entries', () {
      expect(asStringList([1, 2]), ['1', '2']);
    });

    test('wraps a bare string, which models return for a one-item list', () {
      expect(asStringList('only one'), ['only one']);
    });

    test('drops blank and unreadable entries', () {
      expect(asStringList(['a', '', '   ', null, {'x': 1}]), ['a']);
    });

    test('returns empty for null or a non-list', () {
      expect(asStringList(null), isEmpty);
      expect(asStringList(42), isEmpty);
      expect(asStringList(''), isEmpty);
    });
  });

  group('asMap / asMapList', () {
    test('reads an object', () => expect(asMap({'a': 1}), {'a': 1}));

    test('normalises a Map with non-string keys', () {
      // jsonDecode nested inside a dynamic list can produce Map<dynamic,...>.
      final raw = <dynamic, dynamic>{'a': 1};
      expect(asMap(raw), {'a': 1});
    });

    test('returns null for a list or scalar', () {
      expect(asMap([1, 2]), isNull);
      expect(asMap('text'), isNull);
    });

    test('asMapList keeps objects and drops everything else', () {
      expect(
        asMapList([
          {'a': 1},
          'nope',
          42,
          {'b': 2},
        ]),
        [
          {'a': 1},
          {'b': 2},
        ],
      );
    });

    test('asMapList returns empty for a non-list', () {
      expect(asMapList({'a': 1}), isEmpty);
      expect(asMapList(null), isEmpty);
    });
  });

  group('asDateTime', () {
    final fallback = DateTime.utc(2020);

    test('parses an ISO-8601 timestamp', () {
      expect(asDateTime('2026-08-28T10:00:00Z', fallback),
          DateTime.utc(2026, 8, 28, 10));
    });

    test('falls back on junk or null', () {
      expect(asDateTime('yesterday', fallback), fallback);
      expect(asDateTime(null, fallback), fallback);
      expect(asDateTime({'a': 1}, fallback), fallback);
    });
  });
}
