/// Dragging a row: the new order, and the fewest writes that make it so.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/shell/tree_order.dart';

void main() {
  const ids = ['a', 'b', 'c', 'd'];

  group('reorderedIds', () {
    test('dragging down, dropped after', () {
      expect(reorderedIds(ids, 'a', 'c', before: false), ['b', 'c', 'a', 'd']);
    });

    test('dragging down, dropped before', () {
      expect(reorderedIds(ids, 'a', 'c', before: true), ['b', 'a', 'c', 'd']);
    });

    test('dragging up', () {
      expect(reorderedIds(ids, 'd', 'b', before: true), ['a', 'd', 'b', 'c']);
      expect(reorderedIds(ids, 'd', 'a', before: false), ['a', 'd', 'b', 'c']);
    });

    test('onto itself, or beside a stranger, is no change', () {
      expect(reorderedIds(ids, 'b', 'b', before: true), ids);
      expect(reorderedIds(ids, 'b', 'zz', before: true), ids);
    });

    test('a row from elsewhere is inserted', () {
      expect(reorderedIds(ids, 'x', 'b', before: false),
          ['a', 'b', 'x', 'c', 'd']);
    });
  });

  test('appendedIds puts the row last, once', () {
    expect(appendedIds(ids, 'x'), ['a', 'b', 'c', 'd', 'x']);
    expect(appendedIds(ids, 'b'), ['a', 'c', 'd', 'b']);
  });

  group('ordersToWrite', () {
    test('only the rows that moved are written', () {
      final current = {'a': 0, 'b': 1, 'c': 2, 'd': 3};
      expect(ordersToWrite(['b', 'c', 'a', 'd'], current),
          {'b': 0, 'c': 1, 'a': 2});
    });

    test('a list with gaps is renumbered as it is touched', () {
      final current = {'a': 0, 'b': 5, 'c': 9};
      expect(ordersToWrite(['a', 'b', 'c'], current), {'b': 1, 'c': 2});
    });

    test('a newcomer is always written', () {
      expect(ordersToWrite(['a', 'x'], {'a': 0}), {'x': 1});
    });
  });
}
