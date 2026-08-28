/// Getting JSON out of a model that was not constrained to emit it.
///
/// With a strict `json_schema` backend none of this is needed — the decoder
/// cannot emit anything else. But the user may point Mario at a llama.cpp
/// server, an older Ollama, or a 1B model, and there the reply arrives wrapped
/// in a code fence, prefixed with "Sure! Here is the JSON:", carrying a
/// trailing comma, or with the whole object truncated because generation hit
/// the token ceiling.
///
/// Pure functions with no I/O, which is what makes them testable — see
/// test/json_coercion_test.dart. The rule throughout: never "fix" something
/// ambiguous. Every repair here is one a human would call obvious, and
/// anything else returns null so the caller can retry the model rather than
/// silently acting on a guess.
library;

import 'dart:convert';

/// Pulls the first complete JSON object or array out of [raw].
///
/// Returns null when there is nothing recoverable — the caller should retry or
/// surface an error, never invent a default.
Object? extractJson(String raw) {
  if (raw.trim().isEmpty) return null;

  // Fast path: the whole thing is already valid.
  final direct = _tryDecode(raw.trim());
  if (direct != null) return direct;

  final candidates = <String>[];

  // Fenced blocks first — ```json ... ``` is the single most common wrapper,
  // and its contents are more likely to be the intended payload than a stray
  // brace in the prose around it.
  for (final match in _fence.allMatches(raw)) {
    final inner = match.group(1);
    if (inner != null && inner.trim().isNotEmpty) candidates.add(inner.trim());
  }

  // Then every balanced brace/bracket span in the raw text.
  candidates.addAll(_balancedSpans(raw));

  for (final c in candidates) {
    final decoded = _tryDecode(c) ?? _tryDecode(repairJson(c));
    if (decoded != null) return decoded;
  }
  return null;
}

/// [extractJson] narrowed to an object, which is what every Mario schema is at
/// the top level.
Map<String, dynamic>? extractJsonObject(String raw) {
  final v = extractJson(raw);
  if (v is Map<String, dynamic>) return v;
  // A model asked for one object sometimes returns a single-element array of
  // it. Unwrapping that is unambiguous.
  if (v is List && v.length == 1 && v.first is Map<String, dynamic>) {
    return v.first as Map<String, dynamic>;
  }
  return null;
}

/// [extractJson] narrowed to a list of objects.
///
/// Also accepts an object wrapping the list under a single list-valued key
/// (`{"items": [...]}`, `{"questions": [...]}`), which small models produce
/// constantly no matter how the schema is phrased.
List<Map<String, dynamic>>? extractJsonObjectList(String raw) {
  final v = extractJson(raw);
  final list = switch (v) {
    List l => l,
    Map<String, dynamic> m when _soleListValue(m) != null => _soleListValue(m)!,
    _ => null,
  };
  if (list == null) return null;
  final out = <Map<String, dynamic>>[];
  for (final e in list) {
    if (e is Map<String, dynamic>) out.add(e);
  }
  return out.isEmpty && list.isNotEmpty ? null : out;
}

List<dynamic>? _soleListValue(Map<String, dynamic> m) {
  final lists = m.values.whereType<List<dynamic>>().toList();
  return lists.length == 1 ? lists.first : null;
}

/// Conservative textual repairs, applied only after plain decoding failed.
///
/// Each one is safe in the sense that it cannot turn one valid document into a
/// *different* valid document — they only ever rescue text that does not parse
/// at all.
String repairJson(String s) {
  var out = s.trim();

  // Strip a leading fence marker left behind by a partial match.
  out = out.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
  out = out.replaceFirst(RegExp(r'\s*```$'), '');

  // Smart quotes: models trained on prose emit these inside JSON regularly.
  out = out
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'");

  // Trailing commas before a closer. replaceAllMapped, not replaceAll: Dart's
  // plain replaceAll treats `$1` as two literal characters rather than a
  // backreference, so the naive version deletes the closing brace.
  out = out.replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m.group(1)!);

  // Truncated output: close whatever is still open. Only structural closers
  // are added, and only when the imbalance is unambiguous — a string left open
  // is closed first so the braces that follow are not swallowed into it.
  out = _closeUnterminated(out);

  return out;
}

/// Balances an unterminated string/object/array at the end of [s].
String _closeUnterminated(String s) {
  var inString = false;
  var escaped = false;
  final stack = <String>[];

  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    switch (ch) {
      case '"':
        inString = true;
      case '{':
        stack.add('}');
      case '[':
        stack.add(']');
      case '}':
      case ']':
        if (stack.isNotEmpty && stack.last == ch) stack.removeLast();
    }
  }

  if (!inString && stack.isEmpty) return s;

  final buf = StringBuffer(s);
  if (inString) buf.write('"');

  // Strip whatever trails off into nothing before closing the structure.
  // Generation cut short mid-object leaves shapes like `{"a": 1, "b":` — the
  // separator has to go, and so does the key it belonged to, or the result is
  // `{"a": 1, "b"}` which is not valid JSON either.
  var text = buf.toString();
  while (true) {
    final withoutSeparator = text.replaceFirst(RegExp(r'[,:]\s*$'), '');
    if (withoutSeparator != text) {
      text = withoutSeparator;
      continue;
    }
    // A quoted token in *key* position — preceded by `{` or `,` — with no
    // value after it.
    final danglingKey =
        RegExp(r'(\{|,)\s*"(?:[^"\\]|\\.)*"\s*$').firstMatch(text);
    if (danglingKey != null) {
      text = text.substring(0, danglingKey.start) +
          (danglingKey.group(1) == '{' ? '{' : '');
      continue;
    }
    break;
  }

  final tail = StringBuffer();
  for (final closer in stack.reversed) {
    tail.write(closer);
  }
  return '$text$tail';
}

/// Every balanced `{...}` / `[...]` span in [raw], longest first.
///
/// Longest-first matters: a nested object would otherwise win over the
/// enclosing one the caller actually asked for.
List<String> _balancedSpans(String raw) {
  final spans = <String>[];
  for (final open in ['{', '[']) {
    final close = open == '{' ? '}' : ']';
    for (var start = raw.indexOf(open);
        start >= 0;
        start = raw.indexOf(open, start + 1)) {
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var i = start; i < raw.length; i++) {
        final ch = raw[i];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (ch == r'\') {
            escaped = true;
          } else if (ch == '"') {
            inString = false;
          }
          continue;
        }
        if (ch == '"') {
          inString = true;
        } else if (ch == open) {
          depth++;
        } else if (ch == close) {
          depth--;
          if (depth == 0) {
            spans.add(raw.substring(start, i + 1));
            break;
          }
        }
      }
      // Unbalanced tail — keep it anyway; repairJson may be able to close it.
      if (depth > 0) spans.add(raw.substring(start));
    }
  }
  spans.sort((a, b) => b.length.compareTo(a.length));
  return spans;
}

Object? _tryDecode(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

final _fence = RegExp(r'```(?:json|JSON)?\s*([\s\S]*?)```');

// ---------------------------------------------------------------------------
// Reading fields out of JSON nobody guarantees the shape of.
//
// `m['correctIndex'] as num?` throws the moment a model answers with `[0]`
// instead of `0` — and small models do exactly that, often enough that it took
// down quiz generation in practice. The same hazard applies to every field of
// every model reply, every Serper response, and every stored artifact written
// by an older build.
//
// So: never cast. Coerce, and return null when the value cannot be read as the
// requested type. Callers already treat a missing field as "drop this item",
// which turns a crash into one discarded question.
//
// The unwrapping rules are deliberately narrow. A single-element list is
// unwrapped because `[0]` unambiguously means `0`; a multi-element list is
// *not* guessed at, because picking one of several answers is exactly the kind
// of silent wrong result these functions exist to prevent.

/// Reads [v] as a string, or null if it cannot be one.
String? asString(Object? v) => switch (v) {
      String s => s,
      num n => n.toString(),
      bool b => b.toString(),
      List l when l.length == 1 => asString(l.first),
      _ => null,
    };

/// [asString] with a fallback, for fields that must produce something.
String asStringOr(Object? v, [String fallback = '']) => asString(v) ?? fallback;

/// Reads [v] as an int, or null.
///
/// Accepts a numeric string, because a model told to emit an integer will
/// sometimes quote it.
int? asInt(Object? v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s.trim()) ?? double.tryParse(s.trim())?.toInt(),
      List l when l.length == 1 => asInt(l.first),
      _ => null,
    };

/// Reads [v] as a double, or null.
///
/// Also accepts `"3/4"`, which is how a model asked for "a score out of 4"
/// frequently answers.
double? asDouble(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s =>
        double.tryParse(s.trim()) ?? double.tryParse(s.split('/').first.trim()),
      List l when l.length == 1 => asDouble(l.first),
      _ => null,
    };

/// Reads [v] as a bool, accepting the strings models emit for one.
bool asBool(Object? v, {bool fallback = false}) => switch (v) {
      bool b => b,
      String s when s.toLowerCase() == 'true' => true,
      String s when s.toLowerCase() == 'false' => false,
      num n => n != 0,
      _ => fallback,
    };

/// Reads [v] as a list of strings, dropping anything unreadable or blank.
List<String> asStringList(Object? v) {
  if (v is String) return v.trim().isEmpty ? const [] : [v];
  if (v is! List) return const [];
  final out = <String>[];
  for (final e in v) {
    final s = asString(e);
    if (s != null && s.trim().isNotEmpty) out.add(s);
  }
  return out;
}

/// Reads [v] as a JSON object, or null.
Map<String, dynamic>? asMap(Object? v) => switch (v) {
      Map<String, dynamic> m => m,
      Map m => m.map((k, val) => MapEntry(k.toString(), val)),
      _ => null,
    };

/// Reads [v] as a list of JSON objects, dropping non-object entries.
List<Map<String, dynamic>> asMapList(Object? v) {
  if (v is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final e in v) {
    final m = asMap(e);
    if (m != null) out.add(m);
  }
  return out;
}

/// Reads [v] as an ISO-8601 timestamp, falling back to [fallback].
DateTime asDateTime(Object? v, DateTime fallback) {
  final s = asString(v);
  if (s == null) return fallback;
  return DateTime.tryParse(s) ?? fallback;
}
