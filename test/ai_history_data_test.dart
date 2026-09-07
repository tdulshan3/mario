/// What the notebook's AI file has to get right across two devices.
///
/// The file is downloaded and uploaded whole, and two copies of it drift: one
/// device saves a run, the other deletes a chat. The old rule — take the
/// remote copy only when it holds strictly more — meant a deletion never
/// stuck: the device that still had the entry would push it straight back.
/// Merging by id, with the deleted ids remembered, is what these pin down.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/ai_artifacts.dart';

void main() {
  AiProvenance at(int day) => AiProvenance(
        backend: 'test',
        model: '',
        createdAt: DateTime(2026, 9, day),
      );

  AskEntry ask(String id, int day, {String pageId = 'p1'}) => AskEntry(
        id: id,
        pageId: pageId,
        question: 'q $id',
        answer: 'a $id',
        provenance: at(day),
      );

  DoEntry run(String id, int day, {String pageId = 'p1'}) => DoEntry(
        id: id,
        pageId: pageId,
        instruction: 'do $id',
        summary: 'did $id',
        applied: const ['Added a paragraph'],
        provenance: at(day),
      );

  group('a Do run round-trips through JSON', () {
    test('every field survives', () {
      final entry = DoEntry(
        id: 'do-1',
        pageId: 'p1',
        instruction: 'Pull out the to-dos',
        summary: 'Added a to-do list',
        applied: const ['Added heading "To do"', 'Added 3 to-do(s)'],
        failed: 1,
        dropped: 2,
        provenance: at(1),
      );
      final back = DoEntry.fromJson(entry.toJson());
      expect(back.id, 'do-1');
      expect(back.pageId, 'p1');
      expect(back.instruction, 'Pull out the to-dos');
      expect(back.summary, 'Added a to-do list');
      expect(back.applied, ['Added heading "To do"', 'Added 3 to-do(s)']);
      expect(back.failed, 1);
      expect(back.dropped, 2);
      expect(back.provenance.backend, 'test');
    });

    test('the notebook file carries runs and deletions', () {
      final data = NotebookAiData(
        dos: [run('do-1', 1)],
        deleted: const ['ask-9'],
      );
      final back = NotebookAiData.fromJson(data.toJson());
      expect(back.dos.single.id, 'do-1');
      expect(back.deleted, ['ask-9']);
    });

    test('a file written before there were runs still reads', () {
      final back = NotebookAiData.fromJson({'version': 1, 'asks': []});
      expect(back.dos, isEmpty);
      expect(back.deleted, isEmpty);
    });
  });

  group('deleting a chat', () {
    test('removes it and remembers the id', () {
      final data = NotebookAiData(
        asks: [ask('ask-1', 1), ask('ask-2', 2)],
        dos: [run('do-1', 1)],
      );
      final after = data.withoutEntry('ask-1').withoutEntry('do-1');
      expect(after.asks.map((a) => a.id), ['ask-2']);
      expect(after.dos, isEmpty);
      expect(after.deleted, ['ask-1', 'do-1']);
    });

    test('a deleted page takes its runs with it', () {
      final data = NotebookAiData(
        dos: [run('do-1', 1, pageId: 'gone'), run('do-2', 2)],
      );
      final after = data.withoutPage('gone');
      expect(after.dos.map((d) => d.id), ['do-2']);
      expect(after.deleted, contains('do-1'));
    });
  });

  group('two copies of the file merge by id', () {
    test('what either side added is kept, in time order', () {
      final mine = NotebookAiData(asks: [ask('a1', 1), ask('a3', 3)]);
      final theirs = NotebookAiData(asks: [ask('a1', 1), ask('a2', 2)]);
      final merged = mine.merge(theirs);
      expect(merged.asks.map((a) => a.id), ['a1', 'a2', 'a3']);
    });

    test('a deletion on either side wins over a copy that still has it', () {
      // I deleted a1; they still hold it. They deleted d1; I still hold it.
      final mine = NotebookAiData(
        asks: [ask('a2', 2)],
        dos: [run('d1', 1), run('d2', 2)],
        deleted: const ['a1'],
      );
      final theirs = NotebookAiData(
        asks: [ask('a1', 1), ask('a2', 2)],
        dos: [run('d2', 2)],
        deleted: const ['d1'],
      );
      final merged = mine.merge(theirs);
      expect(merged.asks.map((a) => a.id), ['a2']);
      expect(merged.dos.map((d) => d.id), ['d2']);
      // Both tombstones travel on, so a third copy cannot undo either.
      expect(merged.deleted, containsAll(['a1', 'd1']));
    });

    test('merging is not adopting: nothing local is lost to a bigger remote',
        () {
      final mine = NotebookAiData(dos: [run('d1', 1)]);
      final theirs = NotebookAiData(
        asks: [ask('a1', 1), ask('a2', 2), ask('a3', 3)],
      );
      final merged = mine.merge(theirs);
      expect(merged.dos.map((d) => d.id), ['d1']);
      expect(merged.asks, hasLength(3));
    });

    test('a summary comes from whichever copy wrote it later', () {
      NoteSummary summary(String text, int day) => NoteSummary(
            pageId: 'p1',
            sourceHash: 'h',
            summary: text,
            provenance: at(day),
          );
      final mine = NotebookAiData(summaries: {'p1': summary('old', 1)});
      final theirs = NotebookAiData(summaries: {'p1': summary('new', 2)});
      expect(mine.merge(theirs).summaries['p1']!.summary, 'new');
      expect(theirs.merge(mine).summaries['p1']!.summary, 'new');
    });
  });
}
