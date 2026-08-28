/// Getting JSON back out of a model that was never constrained to emit it.
///
/// Every case here is output a real small model produces: a code fence, a
/// preamble, smart quotes, a trailing comma, a reply cut off mid-object
/// because generation hit the token ceiling. The suite's other job is the
/// negative one — proving the repairs never invent structure that was not
/// there, because a silently wrong quiz is worse than a visibly failed one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/json_coercion.dart';

void main() {
  group('extractJsonObject', () {
    test('passes clean JSON straight through', () {
      expect(extractJsonObject('{"a": 1}'), {'a': 1});
    });

    test('unwraps a ```json fence', () {
      const raw = '```json\n{"score": 7, "why": "clear"}\n```';
      expect(extractJsonObject(raw), {'score': 7, 'why': 'clear'});
    });

    test('unwraps a bare fence with no language tag', () {
      expect(extractJsonObject('```\n{"a": 1}\n```'), {'a': 1});
    });

    test('ignores a conversational preamble', () {
      const raw = 'Sure! Here is the JSON you asked for:\n\n{"a": 1}\n\nHope that helps!';
      expect(extractJsonObject(raw), {'a': 1});
    });

    test('drops a trailing comma', () {
      expect(extractJsonObject('{"a": 1, "b": 2,}'), {'a': 1, 'b': 2});
    });

    test('normalises smart quotes', () {
      expect(extractJsonObject('{“a”: “b”}'), {'a': 'b'});
    });

    test('closes an object truncated by the token limit', () {
      const raw = '{"question": "What is 2+2?", "answer": "four"';
      expect(extractJsonObject(raw),
          {'question': 'What is 2+2?', 'answer': 'four'});
    });

    test('closes a string left open mid-word', () {
      final v = extractJsonObject('{"a": "half a senten');
      expect(v, isNotNull);
      expect(v!['a'], 'half a senten');
    });

    test('drops a dangling key with no value', () {
      // "…, "b":" cannot be closed into anything meaningful, so the key goes.
      expect(extractJsonObject('{"a": 1, "b":'), {'a': 1});
    });

    test('prefers the outer object over a nested one', () {
      const raw = '{"outer": {"inner": 1}}';
      expect(extractJsonObject(raw), {
        'outer': {'inner': 1}
      });
    });

    test('unwraps a single-element array', () {
      expect(extractJsonObject('[{"a": 1}]'), {'a': 1});
    });

    test('returns null on prose with no JSON at all', () {
      expect(extractJsonObject('I am not able to answer that.'), isNull);
    });

    test('returns null on empty input', () {
      expect(extractJsonObject(''), isNull);
      expect(extractJsonObject('   \n  '), isNull);
    });

    test('leaves braces inside strings alone', () {
      final v = extractJsonObject(r'{"code": "if (x) { y(); }"}');
      expect(v, {'code': 'if (x) { y(); }'});
    });

    test('handles escaped quotes inside strings', () {
      final v = extractJsonObject(r'{"q": "she said \"hi\""}');
      expect(v!['q'], r'she said "hi"');
    });
  });

  group('extractJsonObjectList', () {
    test('reads a plain array', () {
      expect(extractJsonObjectList('[{"a":1},{"a":2}]'), [
        {'a': 1},
        {'a': 2}
      ]);
    });

    test('unwraps the single list value models insist on adding', () {
      // Asked for an array, a small model returns {"questions": [...]}.
      const raw = '{"questions": [{"q": "one"}, {"q": "two"}]}';
      expect(extractJsonObjectList(raw), [
        {'q': 'one'},
        {'q': 'two'}
      ]);
    });

    test('does not guess when an object holds two lists', () {
      // Ambiguous: which list was meant? Better to fail and retry.
      const raw = '{"a": [{"x":1}], "b": [{"y":2}]}';
      expect(extractJsonObjectList(raw), isNull);
    });

    test('recovers a truncated array', () {
      const raw = '[{"q": "one"}, {"q": "two"}';
      expect(extractJsonObjectList(raw), [
        {'q': 'one'},
        {'q': 'two'}
      ]);
    });
  });

  group('repairJson leaves valid documents alone', () {
    test('a valid document survives a repair pass unchanged in meaning', () {
      const valid = '{"a": [1, 2, {"b": "c"}], "d": null, "e": true}';
      expect(extractJsonObject(repairJson(valid)), extractJsonObject(valid));
    });

    test('a string containing a fence marker is not mangled', () {
      const raw = r'{"note": "use ``` to fence code"}';
      expect(extractJsonObject(raw), {'note': 'use ``` to fence code'});
    });
  });
}
