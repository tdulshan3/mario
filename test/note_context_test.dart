/// Reading a page the way a study feature needs to read it.
///
/// The reason this code exists rather than reusing `documentToMarkdown` is the
/// first group below: the stock encoder does not know Mario's custom blocks, so
/// a physics page built out of math blocks would reach the model as a handful
/// of empty lines. Everything a student actually revises from — formulas, code,
/// text OCR'd out of a photographed slide, the transcript of a recorded
/// lecture — lives in exactly those blocks.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/note_context.dart';

void main() {
  afe.Document docOf(List<Map<String, dynamic>> children) =>
      afe.Document.fromJson({
        'document': {'type': 'page', 'children': children}
      });

  Map<String, dynamic> para(String text) => {
        'type': 'paragraph',
        'data': {
          'delta': [
            {'insert': text}
          ]
        },
      };

  group('custom blocks the stock Markdown encoder would drop', () {
    test('a math block contributes its formula as LaTeX', () {
      final note = extractNoteText(docOf([
        {
          'type': 'math_equation',
          'data': {'formula': 'E = mc^2'},
        }
      ]));
      expect(note.blocks, hasLength(1));
      expect(note.blocks.first.text, r'$$E = mc^2$$');
    });

    test('an older wrapped math block is not fenced twice', () {
      final note = extractNoteText(docOf([
        {
          'type': 'math_equation',
          'data': {'formula': r'$$E = mc^2$$'},
        }
      ]));
      expect(note.blocks.first.text, r'$$E = mc^2$$');
    });

    test('a code block keeps its body and language', () {
      final note = extractNoteText(docOf([
        {
          'type': 'code',
          'data': {'code': 'print("hi")', 'language': 'python'},
        }
      ]));
      expect(note.blocks.first.text, '```python\nprint("hi")\n```');
    });

    test('an image contributes the text OCR found in it', () {
      final note = extractNoteText(docOf([
        {
          'type': 'image',
          'data': {
            'url': '/tmp/slide.png',
            'ocr_lines': ['Newton\'s second law', 'F = ma'],
          },
        }
      ]));
      expect(note.blocks.first.text, contains('F = ma'));
      expect(note.blocks.first.text, contains("Newton's second law"));
    });

    test('an image with no OCR still leaves a marker', () {
      // Without it the model reads straight across the gap and invents a
      // transition between two unrelated paragraphs.
      final note = extractNoteText(docOf([
        {
          'type': 'image',
          'data': {'url': '/tmp/photo.png'},
        }
      ]));
      expect(note.blocks.first.text, '[image]');
    });

    test('an audio clip contributes its transcript', () {
      final note = extractNoteText(docOf([
        {
          'type': 'audio_clip',
          'data': {'path': '/tmp/a.m4a', 'transcript': 'the exam is on Friday'},
        }
      ]));
      expect(note.blocks.first.text, contains('the exam is on Friday'));
    });

    test('an untranscribed audio clip says so rather than vanishing', () {
      final note = extractNoteText(docOf([
        {
          'type': 'audio_clip',
          'data': {'path': '/tmp/a.m4a'},
        }
      ]));
      expect(note.blocks.first.text, contains('not transcribed'));
    });

    test('a spreadsheet becomes rows of text', () {
      final note = extractNoteText(docOf([
        {
          'type': 'spreadsheet',
          'data': {
            'workbook': {
              'sheets': [
                {
                  'name': 'Results',
                  'cells': {'A1': 'Trial', 'B1': 'Mass', 'A2': '1', 'B2': '4.2'},
                }
              ]
            }
          },
        }
      ]));
      final text = note.blocks.first.text;
      expect(text, contains('Results'));
      expect(text, contains('Trial\tMass'));
      expect(text, contains('1\t4.2'));
    });

    test('a drawing is noted as present but has no text', () {
      final note = extractNoteText(docOf([
        {
          'type': 'drawing',
          'data': {'strokes': <dynamic>[]},
        }
      ]));
      expect(note.blocks.first.text, '[drawing]');
    });
  });

  group('standard blocks', () {
    test('headings keep their level, for structure-aware chunking', () {
      final note = extractNoteText(docOf([
        {
          'type': 'heading',
          'data': {
            'level': 2,
            'delta': [
              {'insert': 'Thermodynamics'}
            ]
          },
        }
      ]));
      expect(note.blocks.first.headingLevel, 2);
      expect(note.blocks.first.text, '## Thermodynamics');
      expect(note.blocks.first.isHeading, isTrue);
    });

    test('list and quote markers survive', () {
      final note = extractNoteText(docOf([
        {
          'type': 'bulleted_list',
          'data': {
            'delta': [
              {'insert': 'first'}
            ]
          },
        },
        {
          'type': 'quote',
          'data': {
            'delta': [
              {'insert': 'as Feynman said'}
            ]
          },
        },
        {
          'type': 'todo_list',
          'data': {
            'checked': true,
            'delta': [
              {'insert': 'revise chapter 3'}
            ]
          },
        },
      ]));
      expect(note.blocks.map((b) => b.text), [
        '- first',
        '> as Feynman said',
        '- [x] revise chapter 3',
      ]);
    });

    test('empty paragraphs are skipped, not fed to the model as blank lines', () {
      final note = extractNoteText(docOf([para('real'), para('   '), para('')]));
      expect(note.blocks, hasLength(1));
    });

    test('nested children are walked', () {
      final note = extractNoteText(docOf([
        {
          'type': 'bulleted_list',
          'data': {
            'delta': [
              {'insert': 'parent'}
            ]
          },
          'children': [
            {
              'type': 'bulleted_list',
              'data': {
                'delta': [
                  {'insert': 'child'}
                ]
              },
            }
          ],
        }
      ]));
      expect(note.blocks.map((b) => b.text), ['- parent', '- child']);
    });
  });

  group('slicing for /summary', () {
    test('above() keeps only what precedes the caret', () {
      final note =
          extractNoteText(docOf([para('one'), para('two'), para('three')]));
      // Caret sitting in the third block.
      final above = note.above([2]);
      expect(above.blocks.map((b) => b.text), ['one', 'two']);
    });

    test('above() at the very top is empty rather than the whole page', () {
      final note = extractNoteText(docOf([para('one'), para('two')]));
      expect(note.above([0]).blocks, isEmpty);
    });

    test('above() past the end keeps everything', () {
      final note = extractNoteText(docOf([para('one'), para('two')]));
      expect(note.above([99]).blocks, hasLength(2));
    });
  });

  group('context budget', () {
    test('limitToTokens keeps the opening of the note, not the tail', () {
      // Notes are written top-down: the start carries the definitions a later
      // paragraph depends on.
      final note = extractNoteText(
          docOf([para('aaaa'), para('bbbb'), para('cccc')]));
      final limited = note.limitToTokens(3);
      expect(limited.blocks.first.text, 'aaaa');
      expect(limited.blocks.length, lessThan(note.blocks.length));
    });

    test('limitToTokens is a no-op when everything fits', () {
      final note = extractNoteText(docOf([para('short')]));
      expect(note.limitToTokens(10000).blocks, hasLength(1));
    });

    test('render includes the title as a heading', () {
      final note =
          extractNoteText(docOf([para('body')]), title: 'Chapter 4');
      expect(note.render(), startsWith('# Chapter 4'));
      expect(note.render(), contains('body'));
    });

    test('an empty document is reported as empty', () {
      expect(extractNoteText(docOf([para('  ')])).isEmpty, isTrue);
      expect(extractNoteText(docOf([])).isEmpty, isTrue);
    });
  });

  group('estimateTokens is script-aware', () {
    // The flat "four characters per token" rule is an English rule. Applying it
    // to a non-Latin note under-counts by 3-4x, so the budget check says the
    // note fits, the server silently truncates the overflow, and the model
    // summarises the tail of a page while appearing to have read all of it.
    test('Latin prose is about four characters per token', () {
      final t = estimateTokens('The mitochondria is the powerhouse of the cell');
      expect(t, closeTo(45 / 4, 3));
    });

    test('Sinhala counts far more tokens than the Latin rule would give', () {
      const sinhala = 'ජීව විද්‍යාව යනු ජීවීන් පිළිබඳ අධ්‍යයනයයි';
      final t = estimateTokens(sinhala);
      expect(t, greaterThan((sinhala.length / 4).ceil() * 2),
          reason: 'a flat /4 would badly under-count this');
    });

    test('Tamil and Devanagari are treated as dense too', () {
      expect(estimateTokens('உயிரியல் என்பது'),
          greaterThan(('உயிரியல் என்பது'.length / 4).ceil()));
      expect(estimateTokens('जीव विज्ञान'),
          greaterThan(('जीव विज्ञान'.length / 4).ceil()));
    });

    test('CJK is about one token per character', () {
      const cjk = '細胞小器官';
      expect(estimateTokens(cjk), greaterThanOrEqualTo(cjk.length));
    });

    test('a few accents do not flip Latin text onto the dense ratio', () {
      // Latin prose carrying a handful of accented characters must stay on the
      // /4 ratio; otherwise any European note gets its budget cut to a quarter.
      const accented = 'café au lait with crème brûlée and naïve résumé ';
      const plain = 'cafe au lait with creme brulee and naive resume ';
      final a = estimateTokens(accented * 4);
      final b = estimateTokens(plain * 4);
      // Same ratio, so the estimates track the (near-identical) lengths.
      expect(a, closeTo(b, 4));
      expect(a, closeTo((accented.length * 4) / 4, 6));
    });

    test('empty text costs nothing', () {
      expect(estimateTokens(''), 0);
    });

    test('the estimate scales with length', () {
      final short = estimateTokens('a' * 100);
      final long = estimateTokens('a' * 1000);
      expect(long, greaterThan(short * 5));
    });
  });
}
