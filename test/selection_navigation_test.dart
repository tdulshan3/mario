/// Regression test for the "must click the section before the page" bug.
///
/// The editor resolves the open page within `selection.sectionId`'s page
/// stream, so selecting a page must also align its owning section — otherwise
/// clicking a page in a non-active section sets `pageId` but the editor looks
/// in the wrong section and nothing opens.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/shell/selection_state.dart';

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  SelectionNotifier notifier() => container.read(selectionProvider.notifier);
  Selection state() => container.read(selectionProvider);

  test('clicking a page directly aligns its section and notebook', () {
    notifier().selectNotebook('N');
    notifier().selectSection('A');
    notifier().selectPage('A1');
    expect(state().sectionId, 'A');
    expect(state().pageId, 'A1');

    // Click a page that lives in a *different* section than the active one.
    notifier().selectPage('B2', sectionId: 'B', notebookId: 'N');

    expect(state().sectionId, 'B'); // regression: previously stayed 'A'
    expect(state().pageId, 'B2');
    expect(state().notebookId, 'N');
  });

  test('selectPage without args keeps the current section (legacy callers)',
      () {
    notifier().selectNotebook('N');
    notifier().selectSection('A');
    notifier().selectPage('A1');

    expect(state().notebookId, 'N');
    expect(state().sectionId, 'A');
    expect(state().pageId, 'A1');
  });
}
