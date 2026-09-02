/// Demo mode — fictional notebooks, for screenshots and demos.
///
/// The README's screenshots used to be shot against the maintainer's real
/// account, which put real note titles and real note content into a public
/// repository. There is no way to shoot the app without *some* data: it is
/// auth-gated, and everything on screen comes from Drive and Firestore.
///
/// So this supplies a second source. Built with `--dart-define=MARIO_DEMO=true`
/// the app swaps five providers for the fixtures below and never reaches the
/// network: sign-in is skipped, the notebooks are invented, and the pages carry
/// content written for the purpose. Everything else — every widget, every
/// layout, every theme — is the real app, so a screenshot taken this way is a
/// screenshot of the shipping build.
///
/// Regenerating the screenshots is therefore reproducible and safe, on any
/// machine, without an account. See `docs/screenshots/README.md`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_notifier.dart';
import '../../features/editor/page_content_provider.dart';
import '../../features/shell/shell_state.dart';
import '../models/note_page.dart';
import '../models/notebook.dart';
import '../models/section.dart';
import '../services/auth_service.dart';

/// Set by `--dart-define=MARIO_DEMO=true`. Const, so a release build with the
/// flag off tree-shakes everything below.
const bool kDemoMode = bool.fromEnvironment('MARIO_DEMO');

const _uid = 'demo-user';

const _demoUser = MarioUser(
  uid: _uid,
  email: 'sam@example.com',
  displayName: 'Sam Rivers',
);

/// Ages are relative to launch, so the home screen's "12 min ago" / "3 d ago"
/// column reads naturally whenever the screenshots are re-shot.
DateTime _ago(Duration d) => DateTime.now().subtract(d);

final List<Notebook> demoNotebooks = [
  _notebook('nb-physics', 'Physics', 0),
  _notebook('nb-biology', 'Biology', 3),
  _notebook('nb-reading', 'Reading', 5),
  _notebook('nb-kitchen', 'Kitchen', 1),
];

Notebook _notebook(String id, String name, int color) => Notebook(
      id: id,
      name: name,
      ownerId: _uid,
      colorIndex: color,
      createdAt: _ago(const Duration(days: 210)),
      updatedAt: _ago(const Duration(days: 1)),
    );

final Map<String, List<Section>> _sections = {
  'nb-physics': [
    Section(id: 'se-mech', notebookId: 'nb-physics', name: 'Mechanics', order: 0),
    Section(id: 'se-waves', notebookId: 'nb-physics', name: 'Waves', order: 1),
    Section(
        id: 'se-thermo', notebookId: 'nb-physics', name: 'Thermodynamics', order: 2),
  ],
  'nb-biology': [
    Section(id: 'se-cells', notebookId: 'nb-biology', name: 'Cells', order: 0),
    Section(
        id: 'se-genetics', notebookId: 'nb-biology', name: 'Genetics', order: 1),
  ],
  'nb-reading': [
    Section(id: 'se-papers', notebookId: 'nb-reading', name: 'Papers', order: 0),
  ],
  'nb-kitchen': [
    Section(id: 'se-bread', notebookId: 'nb-kitchen', name: 'Bread', order: 0),
  ],
};

/// The page the editor and AI screenshots open. Its content is [_photosynthesis].
const kDemoOpenPageFile = 'file-photosynthesis';

final Map<String, List<NotePage>> _pages = {
  'se-cells': [
    _page('pg-photo', 'nb-biology', 'se-cells', 'Photosynthesis',
        kDemoOpenPageFile, 0, const Duration(minutes: 12)),
    _page('pg-mitosis', 'nb-biology', 'se-cells', 'Mitosis vs meiosis',
        'file-mitosis', 1, const Duration(days: 4)),
    _page('pg-membrane', 'nb-biology', 'se-cells', 'Membrane transport',
        'file-membrane', 2, const Duration(days: 9)),
  ],
  'se-mech': [
    _page('pg-torque', 'nb-physics', 'se-mech', 'Torque and moments',
        'file-torque', 0, const Duration(hours: 3)),
    _page('pg-newton', 'nb-physics', 'se-mech', "Newton's three laws",
        'file-newton', 1, const Duration(days: 2)),
    _page('pg-projectile', 'nb-physics', 'se-mech', 'Projectile motion',
        'file-projectile', 2, const Duration(days: 6)),
  ],
  'se-waves': [
    _page('pg-interference', 'nb-physics', 'se-waves', 'Interference and beats',
        'file-interference', 0, const Duration(days: 5)),
    _page('pg-standing', 'nb-physics', 'se-waves', 'Standing waves on a string',
        'file-standing', 1, const Duration(days: 11)),
  ],
  'se-thermo': [
    _page('pg-entropy', 'nb-physics', 'se-thermo', 'Entropy, plainly',
        'file-entropy', 0, const Duration(days: 14)),
  ],
  'se-genetics': [
    _page('pg-punnett', 'nb-biology', 'se-genetics', 'Punnett squares',
        'file-punnett', 0, const Duration(days: 8)),
  ],
  'se-papers': [
    _page('pg-attention', 'nb-reading', 'se-papers',
        'Attention Is All You Need — reading notes', 'file-attention', 0,
        const Duration(days: 3)),
    _page('pg-bitter', 'nb-reading', 'se-papers', 'The Bitter Lesson — summary',
        'file-bitter', 1, const Duration(days: 17)),
  ],
  'se-bread': [
    _page('pg-sourdough', 'nb-kitchen', 'se-bread', 'Sourdough timings',
        'file-sourdough', 0, const Duration(days: 21)),
  ],
};

NotePage _page(String id, String notebookId, String sectionId, String title,
        String fileId, int order, Duration age) =>
    NotePage(
      id: id,
      sectionId: sectionId,
      notebookId: notebookId,
      title: title,
      driveFileId: fileId,
      order: order,
      createdAt: _ago(age + const Duration(days: 30)),
      updatedAt: _ago(age),
    );

// ---------------------------------------------------------------------------
// Page content
// ---------------------------------------------------------------------------

Map<String, dynamic> _text(String type, String text, [Map<String, dynamic>? extra]) => {
      'type': type,
      'data': {
        'delta': [
          {'insert': text}
        ],
        ...?extra,
      },
    };

/// The one page written out in full — it is what the editor and AI-panel
/// screenshots show, so it has to survive being read closely.
final Map<String, dynamic> _photosynthesis = {
  'document': {
    'type': 'page',
    'children': [
      _text('paragraph',
          'Plants turn light, water and carbon dioxide into sugar and oxygen. '
          'The whole thing runs in two stages, and the second one does not '
          'actually need light — it needs what the first stage made.'),
      _text('heading', 'The light-dependent reactions', {'level': 2}),
      _text('paragraph',
          'These happen in the thylakoid membrane. Light knocks electrons out '
          'of chlorophyll; the plant replaces them by splitting water, which '
          'is where the oxygen we breathe comes from.'),
      _text('bulleted_list', 'Light hits photosystem II and excites electrons'),
      _text('bulleted_list', 'Water splits — O₂ is released as a by-product'),
      _text('bulleted_list', 'The electron transport chain pumps protons'),
      _text('bulleted_list', 'ATP synthase uses that gradient to make ATP'),
      _text('heading', 'The Calvin cycle', {'level': 2}),
      _text('paragraph',
          'The ATP and NADPH from stage one drive carbon fixation in the '
          'stroma. RuBisCO attaches CO₂ to a five-carbon sugar, and the cycle '
          'turns three times to yield one molecule of G3P.'),
      _text('quote',
          'Worth remembering: six turns of the cycle are needed for one glucose, '
          'not three. Three turns gives one G3P; glucose takes two.'),
      _text('heading', 'What to revise', {'level': 2}),
      _text('numbered_list', 'Where each stage happens, and why that matters'),
      _text('numbered_list', 'The role of RuBisCO, and why it is inefficient'),
      _text('numbered_list', 'How C4 and CAM plants get around photorespiration'),
    ],
  },
};

Map<String, dynamic> _stub(String opening) => {
      'document': {
        'type': 'page',
        'children': [
          _text('paragraph', opening),
        ],
      },
    };

final Map<String, Map<String, dynamic>> _content = {
  kDemoOpenPageFile: _photosynthesis,
  'file-mitosis': _stub('One makes two identical cells; the other makes four that are not.'),
  'file-membrane': _stub('Passive needs no energy. Active does. Everything else is detail.'),
  'file-torque': _stub('Torque is force times perpendicular distance from the pivot.'),
  'file-newton': _stub(
      'Inertia, F = ma, and equal-and-opposite. The third is the one people '
      'state correctly and then apply wrongly.'),
  'file-projectile': _stub('Horizontal and vertical motion are independent. That is the whole trick.'),
  'file-interference': _stub('Two close frequencies produce a beat at their difference.'),
  'file-standing': _stub('Nodes stay still; antinodes move most. Fixed ends must be nodes.'),
  'file-entropy': _stub('Not disorder — the number of ways a state can be arranged.'),
  'file-punnett': _stub('A bookkeeping device for allele combinations, nothing more.'),
  'file-attention': _stub('Self-attention replaces recurrence, so the sequence is processed at '
      'once rather than one step at a time.'),
  'file-bitter': _stub('General methods that scale with compute beat hand-built knowledge.'),
  'file-sourdough': _stub('Levain at 8pm, autolyse at 9, mix at 10, bulk overnight at 18°C.'),
};

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

/// Swapped into the root `ProviderScope` when [kDemoMode] is set.
///
/// These five are the app's entire read path for shell data, so overriding
/// them is enough — nothing downstream reaches Firestore or Drive on its own.
/// `recentPagesProvider` needs no override: it composes the notebook, section
/// and page streams, and so follows the fixtures for free.
List<Override> demoOverrides() => [
      authStateProvider.overrideWith((ref) => Stream.value(_demoUser)),
      notebooksStreamProvider.overrideWith((ref) => Stream.value(demoNotebooks)),
      sectionsStreamProvider.overrideWith(
          (ref, notebookId) => Stream.value(_sections[notebookId] ?? const [])),
      pagesStreamProvider.overrideWith(
          (ref, key) => Stream.value(_pages[key.sectionId] ?? const [])),
      pageContentProvider.overrideWith((ref, fileId) async =>
          _content[fileId] ??
          _stub('This demo page has no content.')),
    ];
