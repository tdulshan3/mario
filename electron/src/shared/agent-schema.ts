import { AgentAction, AgentActionKind, AgentPlan } from './types';
import { normalizeLatexFormula } from './document-codec';

export const AGENT_ACTION_KINDS: AgentActionKind[] = [
  'paragraph',
  'heading',
  'bullets',
  'numbered',
  'todo',
  'quote',
  'divider',
  'code',
  'math',
  'table',
  'spreadsheet',
  'html',
  'rename_page',
  'create_page',
  'create_section',
  'rename_section',
  'create_notebook',
  'markdown',
  'write_page',
  'read_page',
  'list_notebooks',
  'list_pages',
  'search_notes',
  'web_search',
  'open_page',
  'ask_user',
  'replace_block',
  'delete_block',
  'move_block',
  'setting',
];

export const OBSERVING_KINDS = new Set<AgentActionKind>([
  'read_page',
  'list_notebooks',
  'list_pages',
  'search_notes',
  'web_search',
]);

export const AGENT_WRITABLE_SETTINGS = new Set<string>([
  'theme',
  'fontScale',
  'canvasWidth',
  'spellCheck',
  'autoCorrectMath',
]);

export const agentPlanSchema: Record<string, unknown> = {
  type: 'object',
  required: ['summary', 'actions'],
  additionalProperties: false,
  properties: {
    summary: { type: 'string' },
    done: { type: 'boolean' },
    followUps: { type: 'array', items: { type: 'string' } },
    actions: {
      type: 'array',
      items: {
        type: 'object',
        required: ['kind'],
        additionalProperties: false,
        properties: {
          kind: { type: 'string', enum: AGENT_ACTION_KINDS },
          text: { type: 'string' },
          level: { type: 'integer', minimum: 2, maximum: 6 },
          items: { type: 'array', items: { type: 'string' } },
          language: { type: 'string' },
          rows: {
            type: 'array',
            items: { type: 'array', items: { type: 'string' } },
          },
          blockId: { type: 'string' },
          afterBlockId: { type: 'string' },
          section: { type: 'string' },
          notebook: { type: 'string' },
          page: { type: 'string' },
          content: { type: 'string' },
          mode: { type: 'string', enum: ['append', 'prepend', 'replace'] },
          settingKey: { type: 'string' },
          settingValue: { type: 'string' },
        },
      },
    },
  },
};

const KIND_ALIASES: Record<string, { kind: AgentActionKind; inferredLevel?: number }> = {
  paragraph: { kind: 'paragraph' },
  text: { kind: 'paragraph' },
  p: { kind: 'paragraph' },
  heading: { kind: 'heading' },
  header: { kind: 'heading' },
  h1: { kind: 'heading', inferredLevel: 2 },
  h2: { kind: 'heading', inferredLevel: 2 },
  h3: { kind: 'heading', inferredLevel: 3 },
  h4: { kind: 'heading', inferredLevel: 4 },
  h5: { kind: 'heading', inferredLevel: 5 },
  h6: { kind: 'heading', inferredLevel: 6 },
  bullets: { kind: 'bullets' },
  bulleted_list: { kind: 'bullets' },
  bullet_list: { kind: 'bullets' },
  bulleted: { kind: 'bullets' },
  unordered_list: { kind: 'bullets' },
  list: { kind: 'bullets' },
  numbered: { kind: 'numbered' },
  numbered_list: { kind: 'numbered' },
  ordered_list: { kind: 'numbered' },
  todo: { kind: 'todo' },
  todo_list: { kind: 'todo' },
  to_do: { kind: 'todo' },
  to_do_list: { kind: 'todo' },
  checklist: { kind: 'todo' },
  check_list: { kind: 'todo' },
  checkbox: { kind: 'todo' },
  task: { kind: 'todo' },
  tasks: { kind: 'todo' },
  quote: { kind: 'quote' },
  blockquote: { kind: 'quote' },
  callout: { kind: 'quote' },
  divider: { kind: 'divider' },
  hr: { kind: 'divider' },
  horizontal_rule: { kind: 'divider' },
  code: { kind: 'code' },
  code_block: { kind: 'code' },
  codeblock: { kind: 'code' },
  math: { kind: 'math' },
  math_equation: { kind: 'math' },
  equation: { kind: 'math' },
  formula: { kind: 'math' },
  table: { kind: 'table' },
  spreadsheet: { kind: 'spreadsheet' },
  html: { kind: 'html' },
  html_artifact: { kind: 'html' },
  webpage: { kind: 'html' },
  website: { kind: 'html' },
  rename_page: { kind: 'rename_page' },
  rename: { kind: 'rename_page' },
  rename_title: { kind: 'rename_page' },
  create_page: { kind: 'create_page' },
  new_page: { kind: 'create_page' },
  add_page: { kind: 'create_page' },
  create_section: { kind: 'create_section' },
  new_section: { kind: 'create_section' },
  add_section: { kind: 'create_section' },
  rename_section: { kind: 'rename_section' },
  create_notebook: { kind: 'create_notebook' },
  new_notebook: { kind: 'create_notebook' },
  add_notebook: { kind: 'create_notebook' },
  markdown: { kind: 'markdown' },
  insert_markdown: { kind: 'markdown' },
  write: { kind: 'markdown' },
  insert: { kind: 'markdown' },
  append: { kind: 'markdown' },
  write_page: { kind: 'write_page' },
  write_to_page: { kind: 'write_page' },
  append_page: { kind: 'write_page' },
  update_page: { kind: 'write_page' },
  edit_page: { kind: 'write_page' },
  read_page: { kind: 'read_page' },
  get_page: { kind: 'read_page' },
  read: { kind: 'read_page' },
  view_page: { kind: 'read_page' },
  list_notebooks: { kind: 'list_notebooks' },
  list_sections: { kind: 'list_notebooks' },
  notebooks: { kind: 'list_notebooks' },
  list_pages: { kind: 'list_pages' },
  pages: { kind: 'list_pages' },
  find_pages: { kind: 'list_pages' },
  search_notes: { kind: 'search_notes' },
  search: { kind: 'search_notes' },
  find: { kind: 'search_notes' },
  search_pages: { kind: 'search_notes' },
  grep: { kind: 'search_notes' },
  web_search: { kind: 'web_search' },
  search_web: { kind: 'web_search' },
  browse: { kind: 'web_search' },
  lookup: { kind: 'web_search' },
  google: { kind: 'web_search' },
  open_page: { kind: 'open_page' },
  navigate: { kind: 'open_page' },
  go_to_page: { kind: 'open_page' },
  show_page: { kind: 'open_page' },
  goto: { kind: 'open_page' },
  ask_user: { kind: 'ask_user' },
  ask: { kind: 'ask_user' },
  question: { kind: 'ask_user' },
  clarify: { kind: 'ask_user' },
  ask_question: { kind: 'ask_user' },
  replace_block: { kind: 'replace_block' },
  update_block: { kind: 'replace_block' },
  edit_block: { kind: 'replace_block' },
  delete_block: { kind: 'delete_block' },
  remove_block: { kind: 'delete_block' },
  move_block: { kind: 'move_block' },
  setting: { kind: 'setting' },
};

/**
 * Block ids as the model writes them back. The prompt labels blocks `[id:ab12cd]`,
 * and models often copy the label: "id:ab12cd", "[id:ab12cd]", "#ab12cd".
 */
function normaliseBlockId(raw: unknown): string | undefined {
  const id = String(raw ?? '')
    .trim()
    .replace(/^\[\s*/, '')
    .replace(/\s*\]$/, '')
    .replace(/^(id\s*[:=]\s*|#)/i, '')
    .trim();
  return id || undefined;
}

export function parseAgentPlan(
  raw: Record<string, unknown>,
  knownBlockIds?: Set<string>,
): AgentPlan {
  const summary = String(raw.summary ?? 'Completed actions.').trim() || 'Completed actions.';
  const doneRaw = raw.done ?? raw.finished ?? raw.complete;
  const done = typeof doneRaw === 'boolean' ? doneRaw : true;

  const rawFollowUps = (raw.followUps ?? raw.follow_ups ?? raw.suggestions) as unknown;
  const followUps: string[] = Array.isArray(rawFollowUps)
    ? rawFollowUps
        .map((x) => String(x ?? '').trim())
        .filter((x) => x.length > 0)
        .slice(0, 3)
    : [];

  const rawActions = Array.isArray(raw.actions) ? raw.actions : [];
  const actions: AgentAction[] = [];
  let dropped = 0;

  for (const item of rawActions.slice(0, 25)) {
    if (!item || typeof item !== 'object') {
      dropped++;
      continue;
    }
    const obj = item as Record<string, unknown>;
    const rawKind = String(obj.kind ?? obj.type ?? obj.action ?? obj.op ?? '')
      .trim()
      .toLowerCase();
    const mapped = KIND_ALIASES[rawKind];
    if (!mapped) {
      dropped++;
      continue;
    }

    let kind = mapped.kind;
    const blockId = normaliseBlockId(obj.blockId ?? obj.block_id);
    let afterBlockId = normaliseBlockId(obj.afterBlockId ?? obj.after_block_id);

    if (
      knownBlockIds &&
      (kind === 'replace_block' || kind === 'delete_block' || kind === 'move_block')
    ) {
      if (!blockId || !knownBlockIds.has(blockId)) {
        dropped++;
        continue;
      }
    }
    // An insert after a block that doesn't exist still happens — at the end of the page.
    if (knownBlockIds && afterBlockId && !knownBlockIds.has(afterBlockId)) {
      afterBlockId = undefined;
    }

    const extractItems = (): string[] => {
      if (Array.isArray(obj.items)) {
        return obj.items
          .map((it) => {
            if (typeof it === 'string') return it.trim();
            if (it && typeof it === 'object') {
              const m = it as Record<string, unknown>;
              return String(
                m.text ?? m.content ?? m.name ?? m.title ?? m.label ?? '',
              ).trim();
            }
            return '';
          })
          .filter(Boolean);
      }
      const txt = String(obj.text ?? obj.content ?? '').trim();
      if (!txt) return [];
      return txt
        .split('\n')
        .map((l) => l.replace(/^([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?/, '').trim())
        .filter(Boolean);
    };

    const textVal = String(
      obj.text ??
        obj.content ??
        obj.body ??
        obj.value ??
        obj.replacement ??
        obj.newText ??
        obj.question ??
        obj.prompt ??
        obj.query ??
        obj.q ??
        obj.title ??
        obj.name ??
        '',
    );

    if (kind === 'replace_block' && textVal === '') {
      kind = 'delete_block';
    }

    const action: AgentAction = { kind };
    if (blockId) action.blockId = blockId;
    if (afterBlockId) action.afterBlockId = afterBlockId;

    switch (kind) {
      case 'heading': {
        const lvl = Number(obj.level ?? mapped.inferredLevel ?? 2);
        action.level = Math.min(6, Math.max(2, Number.isFinite(lvl) ? lvl : 2));
        action.text = textVal.trim();
        break;
      }
      case 'bullets':
      case 'numbered':
      case 'todo': {
        action.items = extractItems();
        if (action.items.length === 0) {
          dropped++;
          continue;
        }
        break;
      }
      case 'code': {
        action.language = String(obj.language ?? 'plaintext').trim() || 'plaintext';
        action.text =
          typeof obj.text === 'string'
            ? obj.text
            : Array.isArray(obj.items)
              ? obj.items.join('\n')
              : textVal;
        break;
      }
      case 'math': {
        action.text = normalizeLatexFormula(textVal);
        break;
      }
      case 'table':
      case 'spreadsheet': {
        if (Array.isArray(obj.rows) && obj.rows.length > 0) {
          action.rows = (obj.rows as unknown[][])
            .slice(0, 200)
            .map((r) =>
              Array.isArray(r)
                ? r.slice(0, 30).map((c) => String(c ?? ''))
                : [String(r ?? '')],
            );
        } else {
          dropped++;
          continue;
        }
        if (kind === 'spreadsheet' && textVal.trim()) {
          action.text = textVal.trim();
        }
        break;
      }
      case 'setting': {
        const sk = String(obj.settingKey ?? obj.key ?? '').trim();
        const sv = String(obj.settingValue ?? obj.value ?? '').trim();
        if (!AGENT_WRITABLE_SETTINGS.has(sk) || !sv) {
          dropped++;
          continue;
        }
        action.settingKey = sk;
        action.settingValue = sv;
        break;
      }
      default: {
        action.text = textVal;
        if (obj.notebook || obj.notebookName || obj.notebook_name) {
          action.notebook = String(
            obj.notebook ?? obj.notebookName ?? obj.notebook_name,
          ).trim();
        }
        if (obj.section || obj.sectionName || obj.section_name) {
          action.section = String(
            obj.section ?? obj.sectionName ?? obj.section_name,
          ).trim();
        }
        if (obj.page || obj.pageTitle || obj.page_title || obj.pageId) {
          action.page = String(
            obj.page ?? obj.pageTitle ?? obj.page_title ?? obj.pageId,
          ).trim();
        }
        if (obj.content || obj.body || obj.markdown) {
          action.content = String(obj.content ?? obj.body ?? obj.markdown);
        }
        if (obj.mode === 'append' || obj.mode === 'prepend' || obj.mode === 'replace') {
          action.mode = obj.mode;
        }
        break;
      }
    }

    actions.push(action);
  }

  return { summary, done, followUps, actions, dropped };
}

export function marioAgentPrompt(userSkills: string[] = [], includeHtml = false): string {
  const parts = [
    `You are Mario, an intelligent note-taking and workspace agent integrated directly into the user's notebooks.`,
    `## Core Capabilities & Turn Model
- You respond strictly with a JSON object matching the \`agent_plan\` schema (\`summary\`, \`done\`, \`followUps\`, \`actions\`).
- Every block on the open page is prefixed with \`[id:xxxxxx]\`.
- To edit an existing block in place, use \`replace_block\` with \`blockId\`.
- To remove a block, use \`delete_block\` with \`blockId\`.
- To insert after a specific block, pass \`afterBlockId: "xxxxxx"\`.
- To write rich multi-block content (headings, paragraphs, lists, code, math, tables), use \`markdown\` or individual block actions (\`heading\`, \`paragraph\`, \`bullets\`, \`numbered\`, \`todo\`, \`quote\`, \`code\`, \`math\`, \`table\`, \`spreadsheet\`, \`divider\`).
- You can inspect and organize the user's workspace across notebooks using \`list_notebooks\`, \`list_pages\`, \`read_page\`, \`search_notes\`, \`web_search\`, \`create_notebook\`, \`create_section\`, \`create_page\`, \`write_page\`, and \`open_page\`.
- When you invoke an observing tool (\`read_page\`, \`list_notebooks\`, \`list_pages\`, \`search_notes\`, \`web_search\`), set \`done: false\` so you can inspect the observation on the next turn and complete the task.`,
  ];

  if (includeHtml) {
    parts.push(
      `## HTML Artifacts
- When asked to build an interactive webpage, dashboard, or preview, emit an \`html\` action whose \`text\` is a complete, self-contained \`<!DOCTYPE html><html>...</html>\` document with embedded CSS and JS.`,
    );
  }

  if (userSkills.length > 0) {
    parts.push(`## User Skills\n${userSkills.join('\n\n')}`);
  }

  return parts.join('\n\n');
}

export const grammarSchema: Record<string, unknown> = {
  type: 'object',
  required: ['suggestions'],
  additionalProperties: false,
  properties: {
    suggestions: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'original', 'suggestion', 'explanation'],
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          original: { type: 'string' },
          suggestion: { type: 'string' },
          explanation: { type: 'string' },
        },
      },
    },
  },
};

const DESTRUCTIVE_KINDS = new Set<AgentActionKind>(['replace_block', 'delete_block', 'move_block', 'rename_page', 'rename_section']);

/**
 * One line saying what an action will do, for the Do tab's preview, and whether
 * it changes or removes something already there.
 */
export function describeAgentAction(
  action: AgentAction,
  textOf: (blockId: string) => string | undefined = () => undefined,
): { text: string; destructive: boolean } {
  const clip = (t: string | undefined, n = 48) => {
    const one = (t ?? '').replace(/\s+/g, ' ').trim();
    return one.length > n ? `${one.slice(0, n - 1)}…` : one;
  };
  const quoted = (t: string | undefined) => (clip(t) ? `“${clip(t)}”` : '');
  const block = (id: string | undefined) => (id && textOf(id) ? quoted(textOf(id)) : 'a block');
  const where = action.afterBlockId && textOf(action.afterBlockId) ? ` after ${quoted(textOf(action.afterBlockId))}` : '';
  const n = (count: number, one: string) => `${count} ${one}${count === 1 ? '' : 's'}`;
  const destructive = DESTRUCTIVE_KINDS.has(action.kind) || (action.kind === 'write_page' && action.mode === 'replace');
  const text = (() => {
    switch (action.kind) {
      case 'paragraph':
        return `Add a paragraph ${quoted(action.text)}${where}`;
      case 'heading':
        return `Add a heading ${quoted(action.text)}${where}`;
      case 'bullets':
        return `Add ${n(action.items?.length ?? 0, 'bullet point')}${where}`;
      case 'numbered':
        return `Add a numbered list of ${n(action.items?.length ?? 0, 'item')}${where}`;
      case 'todo':
        return `Add ${n(action.items?.length ?? 0, 'to-do')}${where}`;
      case 'quote':
        return `Add a quote ${quoted(action.text)}${where}`;
      case 'divider':
        return `Add a divider${where}`;
      case 'code':
        return `Add a ${action.language ? `${action.language} ` : ''}code block${where}`;
      case 'math':
        return `Add an equation${where}`;
      case 'table':
        return `Add a table of ${n(action.rows?.length ?? 0, 'row')}${where}`;
      case 'spreadsheet':
        return `Add a spreadsheet${action.text ? ` ${quoted(action.text)}` : ''}${where}`;
      case 'markdown':
        return `Add text${where}: ${quoted(action.text ?? action.content)}`;
      case 'html':
        return 'Show an interactive HTML preview';
      case 'write_page':
        return action.mode === 'replace'
          ? 'Replace everything on the page'
          : action.mode === 'prepend'
            ? 'Add text at the top of the page'
            : 'Add text at the end of the page';
      case 'replace_block':
        return `Rewrite ${block(action.blockId)}`;
      case 'delete_block':
        return `Delete ${block(action.blockId)}`;
      case 'move_block':
        return `Move ${block(action.blockId)}${where}`;
      case 'rename_page':
        return `Rename the page to ${quoted(action.text)}`;
      case 'rename_section':
        return `Rename the section to ${quoted(action.text)}`;
      case 'create_page':
        return `Create a page ${quoted(action.page ?? action.text)}`;
      case 'create_section':
        return `Create a section ${quoted(action.section ?? action.text)}`;
      case 'create_notebook':
        return `Create a notebook ${quoted(action.notebook ?? action.text)}`;
      case 'open_page':
        return `Open the page ${quoted(action.page ?? action.text)}`;
      case 'setting':
        return `Change the setting ${action.settingKey ?? ''} to ${action.settingValue ?? ''}`.trim();
      case 'read_page':
        return 'Read a page';
      case 'list_notebooks':
      case 'list_pages':
        return 'Look through the notebook';
      case 'search_notes':
        return `Search the notes for ${quoted(action.text)}`;
      case 'web_search':
        return `Search the web for ${quoted(action.text)}`;
      case 'ask_user':
        return `Ask: ${action.text ?? ''}`;
      default:
        return String(action.kind);
    }
  })();
  return { text: text.replace(/\s+/g, ' ').trim(), destructive };
}

/** Whether a plan changes anything, as opposed to only reading or asking. */
export const planWrites = (actions: AgentAction[]) =>
  actions.some((a) => !OBSERVING_KINDS.has(a.kind) && a.kind !== 'ask_user');

