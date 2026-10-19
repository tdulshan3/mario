import {
  AuthUser,
  Notebook,
  NotePage,
  PageContent,
  Section,
} from './types';

export const DEMO_USER: AuthUser = {
  uid: 'demo-user',
  email: 'sam@example.com',
  displayName: 'Sam Rivers',
};

const NOW = '2026-10-19T09:00:00.000Z';
const YESTERDAY = '2026-10-18T16:30:00.000Z';
const EARLIER = '2026-10-10T11:15:00.000Z';

export const DEMO_NOTEBOOKS: Notebook[] = [
  {
    id: 'nb-biology',
    name: 'Biology',
    ownerId: 'demo-user',
    collaboratorUids: [],
    colorIndex: 3,
    createdAt: EARLIER,
    updatedAt: NOW,
  },
  {
    id: 'nb-physics',
    name: 'Physics',
    ownerId: 'demo-user',
    collaboratorUids: [],
    colorIndex: 0,
    createdAt: EARLIER,
    updatedAt: YESTERDAY,
  },
  {
    id: 'nb-reading',
    name: 'Reading',
    ownerId: 'demo-user',
    collaboratorUids: [],
    colorIndex: 5,
    createdAt: EARLIER,
    updatedAt: EARLIER,
  },
  {
    id: 'nb-kitchen',
    name: 'Kitchen',
    ownerId: 'demo-user',
    collaboratorUids: [],
    colorIndex: 1,
    createdAt: EARLIER,
    updatedAt: EARLIER,
  },
];

export const DEMO_SECTIONS: Record<string, Section[]> = {
  'nb-biology': [
    { id: 'se-cells', notebookId: 'nb-biology', name: 'Cell Biology', colorIndex: 3, order: 0 },
    { id: 'se-genetics', notebookId: 'nb-biology', name: 'Genetics', colorIndex: 4, order: 1 },
  ],
  'nb-physics': [
    { id: 'se-mech', notebookId: 'nb-physics', name: 'Mechanics', colorIndex: 0, order: 0 },
    { id: 'se-waves', notebookId: 'nb-physics', name: 'Waves & Optics', colorIndex: 2, order: 1 },
    { id: 'se-thermo', notebookId: 'nb-physics', name: 'Thermodynamics', colorIndex: 1, order: 2 },
  ],
  'nb-reading': [
    { id: 'se-papers', notebookId: 'nb-reading', name: 'Papers & Notes', colorIndex: 5, order: 0 },
  ],
  'nb-kitchen': [
    { id: 'se-bread', notebookId: 'nb-kitchen', name: 'Sourdough & Baking', colorIndex: 1, order: 0 },
  ],
};

export const DEMO_PAGES: Record<string, NotePage[]> = {
  'nb-biology/se-cells': [
    {
      id: 'pg-photo',
      notebookId: 'nb-biology',
      sectionId: 'se-cells',
      title: 'Photosynthesis',
      driveFileId: 'file-photosynthesis',
      order: 0,
      indentLevel: 0,
      createdAt: EARLIER,
      updatedAt: NOW,
    },
    {
      id: 'pg-mitosis',
      notebookId: 'nb-biology',
      sectionId: 'se-cells',
      title: 'Mitosis & Cell Cycle',
      driveFileId: 'file-mitosis',
      order: 1,
      indentLevel: 0,
      createdAt: EARLIER,
      updatedAt: YESTERDAY,
    },
  ],
  'nb-biology/se-genetics': [
    {
      id: 'pg-mendel',
      notebookId: 'nb-biology',
      sectionId: 'se-genetics',
      title: 'Mendelian Inheritance',
      driveFileId: 'file-mendel',
      order: 0,
      indentLevel: 0,
      createdAt: EARLIER,
      updatedAt: EARLIER,
    },
  ],
  'nb-physics/se-mech': [
    {
      id: 'pg-newton',
      notebookId: 'nb-physics',
      sectionId: 'se-mech',
      title: "Newton's Laws of Motion",
      driveFileId: 'file-newton',
      order: 0,
      indentLevel: 0,
      createdAt: EARLIER,
      updatedAt: YESTERDAY,
    },
  ],
  'nb-physics/se-waves': [],
  'nb-physics/se-thermo': [],
  'nb-reading/se-papers': [
    {
      id: 'pg-attention',
      notebookId: 'nb-reading',
      sectionId: 'se-papers',
      title: 'Attention Is All You Need',
      driveFileId: 'file-attention',
      order: 0,
      indentLevel: 0,
      createdAt: EARLIER,
      updatedAt: EARLIER,
    },
  ],
  'nb-kitchen/se-bread': [
    {
      id: 'pg-country-loaf',
      notebookId: 'nb-kitchen',
      sectionId: 'se-bread',
      title: 'Country Sourdough Loaf',
      driveFileId: 'file-country-loaf',
      order: 0,
      indentLevel: 0,
      createdAt: EARLIER,
      updatedAt: EARLIER,
    },
  ],
};

export const DEMO_PAGE_CONTENTS: Record<string, PageContent> = {
  'file-photosynthesis': {
    title: 'Photosynthesis',
    updatedAt: NOW,
    document: {
      type: 'page',
      children: [
        {
          id: 'ph0001',
          type: 'paragraph',
          data: {
            delta: [
              {
                insert:
                  'Photosynthesis converts light energy into chemical energy stored in glucose, releasing oxygen as a byproduct.',
              },
            ],
          },
        },
        {
          id: 'ph0002',
          type: 'math_equation',
          data: {
            formula: '6\\text{CO}_2 + 6\\text{H}_2\\text{O} \\xrightarrow{h\\nu} \\text{C}_6\\text{H}_{12}\\text{O}_6 + 6\\text{O}_2',
          },
        },
        {
          id: 'ph0003',
          type: 'heading',
          data: { level: 2, delta: [{ insert: '1. Light-Dependent Reactions' }] },
        },
        {
          id: 'ph0004',
          type: 'bulleted_list',
          data: {
            delta: [
              { insert: 'Take place across the ' },
              { insert: 'thylakoid membrane', attributes: { bold: true } },
              { insert: ' inside the chloroplast.' },
            ],
          },
        },
        {
          id: 'ph0005',
          type: 'bulleted_list',
          data: {
            delta: [
              { insert: 'Split water via photolysis to produce ' },
              { insert: 'ATP', attributes: { code: true } },
              { insert: ' and ' },
              { insert: 'NADPH', attributes: { code: true } },
              { insert: '.' },
            ],
          },
        },
        {
          id: 'ph0006',
          type: 'heading',
          data: { level: 2, delta: [{ insert: '2. The Calvin Cycle (Stroma)' }] },
        },
        {
          id: 'ph0007',
          type: 'numbered_list',
          data: {
            number: 1,
            delta: [
              { insert: 'Carbon Fixation', attributes: { bold: true } },
              { insert: ' — RuBisCO catalyzes CO₂ attachment to RuBP.' },
            ],
          },
        },
        {
          id: 'ph0008',
          type: 'numbered_list',
          data: {
            number: 2,
            delta: [
              { insert: 'Reduction', attributes: { bold: true } },
              { insert: ' — ATP and NADPH reduce 3-PGA into G3P.' },
            ],
          },
        },
        {
          id: 'ph0009',
          type: 'numbered_list',
          data: {
            number: 3,
            delta: [
              { insert: 'Regeneration', attributes: { bold: true } },
              { insert: ' — G3P molecules regenerate RuBP to continue the cycle.' },
            ],
          },
        },
        {
          id: 'ph0010',
          type: 'quote',
          data: {
            delta: [
              { insert: 'Note', attributes: { bold: true } },
              {
                insert:
                  '\nThree turns of the Calvin cycle fix 3 CO₂ molecules and yield one net G3P molecule.',
              },
            ],
          },
        },
      ],
    },
  },
  'file-newton': {
    title: "Newton's Laws of Motion",
    updatedAt: YESTERDAY,
    document: {
      type: 'page',
      children: [
        {
          id: 'nw0001',
          type: 'paragraph',
          data: {
            delta: [
              {
                insert:
                  'Classical mechanics rests on three foundational laws relating force, mass, and acceleration.',
              },
            ],
          },
        },
        {
          id: 'nw0002',
          type: 'math_equation',
          data: {
            formula: '\\sum \\mathbf{F} = m \\mathbf{a} = m \\frac{d^2\\mathbf{x}}{dt^2}',
          },
        },
        {
          id: 'nw0003',
          type: 'spreadsheet',
          data: {
            workbook: JSON.stringify({
              version: 2,
              active: 0,
              sheets: [
                {
                  name: 'Lab Run #1',
                  rows: 4,
                  cols: 4,
                  cells: {
                    '0,0': 'Trial',
                    '0,1': 'Mass (kg)',
                    '0,2': 'Accel (m/s²)',
                    '0,3': 'Force (N)',
                    '1,0': 'Cart A',
                    '1,1': '2.5',
                    '1,2': '3.2',
                    '1,3': '=B2*C2',
                    '2,0': 'Cart B',
                    '2,1': '4.0',
                    '2,2': '2.5',
                    '2,3': '=B3*C3',
                    '3,0': 'Total Force',
                    '3,1': '',
                    '3,2': '',
                    '3,3': '=SUM(D2:D3)',
                  },
                },
              ],
            }),
          },
        },
        {
          id: 'nw0004',
          type: 'code',
          data: {
            language: 'python',
            delta: [
              {
                insert:
                  'def rk4_step(x: float, v: float, force_fn, mass: float, dt: float):\n    a1 = force_fn(x, v) / mass\n    v_next = v + a1 * dt\n    x_next = x + v * dt + 0.5 * a1 * (dt ** 2)\n    return x_next, v_next',
              },
            ],
          },
        },
      ],
    },
  },
  'file-country-loaf': {
    title: 'Country Sourdough Loaf',
    updatedAt: EARLIER,
    document: {
      type: 'page',
      children: [
        {
          id: 'br0001',
          type: 'heading',
          data: { level: 2, delta: [{ insert: 'Bake Day Checklist' }] },
        },
        {
          id: 'br0002',
          type: 'todo_list',
          data: { checked: true, delta: [{ insert: 'Autolyse 450g bread flour + 50g whole wheat (45 min)' }] },
        },
        {
          id: 'br0003',
          type: 'todo_list',
          data: { checked: true, delta: [{ insert: 'Mix in 100g active levain and 10g sea salt' }] },
        },
        {
          id: 'br0004',
          type: 'todo_list',
          data: { checked: false, delta: [{ insert: '4 sets of coil folds spaced 30 min apart' }] },
        },
        {
          id: 'br0005',
          type: 'todo_list',
          data: { checked: false, delta: [{ insert: 'Cold retard at 4°C overnight (14 hours)' }] },
        },
      ],
    },
  },
};

