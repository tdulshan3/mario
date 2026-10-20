export type CollaboratorRole = 'owner' | 'editor' | 'viewer';

export interface Collaborator {
  uid: string;
  email: string;
  role: CollaboratorRole;
}

export interface Notebook {
  id: string;
  name: string;
  ownerId: string;
  collaboratorUids: string[];
  colorIndex: number;
  createdAt: string;
  updatedAt: string;
  collaborators?: Collaborator[];
  invitedEmails?: string[];
}

export interface Section {
  id: string;
  notebookId: string;
  name: string;
  colorIndex: number;
  order: number;
}

export interface NotePage {
  id: string;
  sectionId: string;
  notebookId: string;
  title: string;
  driveFileId: string | null;
  order: number;
  indentLevel: number;
  createdAt: string;
  updatedAt: string;
}

export interface DeltaAttributes {
  bold?: boolean;
  italic?: boolean;
  underline?: boolean;
  strikethrough?: boolean;
  code?: boolean;
  href?: string | null;
  text_color?: string | null;
  bg_color?: string | null;
  font_size?: number | null;
  font_family?: string | null;
  [key: string]: unknown;
}

export interface DeltaOp {
  insert: string;
  attributes?: DeltaAttributes;
}

export interface StrokePoint {
  x: number;
  y: number;
  p: number;
}

export type StrokeMode = 'pen' | 'highlighter' | 'eraser';

export interface Stroke {
  points: StrokePoint[];
  color: number; // ARGB int e.g. 0xFF000000
  width: number;
  mode: StrokeMode;
}

export interface SheetData {
  name: string;
  rows: number;
  cols: number;
  cells: Record<string, string>;
}

export interface WorkbookData {
  activeIndex: number;
  sheets: SheetData[];
}

export interface AppFlowyNode {
  id?: string; // 6-char runtime block ID for AI prompt & editor keying
  type:
    | 'paragraph'
    | 'heading'
    | 'bulleted_list'
    | 'numbered_list'
    | 'todo_list'
    | 'quote'
    | 'divider'
    | 'table'
    | 'table/cell'
    | 'code'
    | 'math_equation'
    | 'drawing'
    | 'spreadsheet'
    | 'audio_clip'
    | 'image'
    | string;
  data: {
    delta?: DeltaOp[];
    level?: number;
    align?: 'left' | 'center' | 'right';
    checked?: boolean;
    number?: number;
    // code block
    code?: string;
    language?: string;
    // math_equation block
    formula?: string;
    // drawing block
    strokes?: Stroke[];
    width?: number;
    height?: number;
    // spreadsheet block
    workbook?: WorkbookData | string;
    // audio_clip block
    path?: string;
    transcript?: string;
    durationMs?: number;
    // image block
    url?: string;
    drive_id?: string;
    ocr_lines?: string[];
    ocr_dismissed?: boolean;
    // table block
    colsLen?: number;
    rowsLen?: number;
    colWidths?: Record<string, number>;
    rowPosition?: number;
    colPosition?: number;
    [key: string]: unknown;
  };
  children?: AppFlowyNode[];
}

export interface AppFlowyDocument {
  type: 'page';
  children: AppFlowyNode[];
}

export interface PageContent {
  document: AppFlowyDocument;
  title: string;
  createdAt?: string;
  updatedAt?: string;
  strokes?: Stroke[];
  assetIds?: string[];
  rawHtmlOverride?: string;
}

export type MarioThemeMode = 'system' | 'light' | 'white' | 'night' | 'black';
export type CanvasWidth = 'narrow' | 'medium' | 'full';
export type BlockAlign = 'left' | 'center' | 'right' | 'justify';
export type AiTab = 'ask' | 'quiz' | 'write' | 'do';
export type WebSearchMode = 'auto' | 'on' | 'off';

export interface SettingsState {
  themeMode: MarioThemeMode;
  fontScale: number;
  canvasWidth: CanvasWidth;
  autoCorrectMath: boolean;
  spellCheck: boolean;
  holdToRecord: boolean;
  voiceLocale: string;
  offlineMode: boolean;
  askOnHighlight: boolean;
}

export type LlmProviderKind =
  | 'openAiCompatible'
  | 'ollama'
  | 'openAi'
  | 'anthropic'
  | 'gemini';

export type LlmEffort = 'off' | 'low' | 'medium' | 'high';

export interface LlmCapabilities {
  strictJsonSchema: boolean;
  jsonMode: boolean;
  tools: boolean;
  embeddings: boolean;
  vision: boolean;
  contextTokens: number;
}

export interface LlmProviderConfig {
  id: string;
  label: string;
  kind: LlmProviderKind;
  baseUrl: string;
  model: string;
  embeddingModel?: string;
  hasApiKey: boolean;
  capabilities: LlmCapabilities;
  contextTokens: number;
  effort: LlmEffort;
}

export interface DiscoveredModel {
  name: string;
  sizeLabel: string;
}

export interface DiscoveredEndpoint {
  serverName: string;
  kind: LlmProviderKind;
  baseUrl: string;
  models: DiscoveredModel[];
}

export interface AuthUser {
  uid: string;
  email: string;
  displayName: string;
  photoUrl?: string;
}

export interface SyncStatus {
  pendingChanges: number;
  syncing: boolean;
  lastError?: string | null;
  offlineMode: boolean;
}

export interface TreeSnapshot {
  notebooks: Notebook[];
  sectionsByNotebook: Record<string, Section[]>;
  pagesBySection: Record<string, NotePage[]>; // key: `${notebookId}/${sectionId}`
  syncStatus: SyncStatus;
}

export type AgentActionKind =
  | 'paragraph'
  | 'heading'
  | 'bullets'
  | 'numbered'
  | 'todo'
  | 'quote'
  | 'divider'
  | 'code'
  | 'math'
  | 'table'
  | 'spreadsheet'
  | 'html'
  | 'rename_page'
  | 'create_page'
  | 'create_section'
  | 'rename_section'
  | 'create_notebook'
  | 'markdown'
  | 'write_page'
  | 'read_page'
  | 'list_notebooks'
  | 'list_pages'
  | 'search_notes'
  | 'web_search'
  | 'open_page'
  | 'ask_user'
  | 'replace_block'
  | 'delete_block'
  | 'move_block'
  | 'setting';

export interface AgentAction {
  kind: AgentActionKind;
  text?: string;
  level?: number;
  items?: string[];
  language?: string;
  rows?: string[][];
  blockId?: string;
  afterBlockId?: string;
  section?: string;
  notebook?: string;
  page?: string;
  content?: string;
  mode?: 'append' | 'prepend' | 'replace';
  settingKey?: string;
  settingValue?: string;
}

export interface AgentPlan {
  summary: string;
  done: boolean;
  followUps: string[];
  actions: AgentAction[];
  dropped?: number;
}

export interface GrammarSuggestion {
  id: string;
  original: string;
  suggestion: string;
  explanation: string;
  status?: 'pending' | 'applied' | 'ignored';
}

export interface QuizMcq {
  question: string;
  options: string[];
  correctIndex: number;
  explanation: string;
}

export interface QuizEssay {
  question: string;
  /** The points a full-mark answer makes: the rubric it is marked against. */
  expectedPoints: string[];
  /** Marks available: one per rubric point. */
  marks: number;
}

export interface QuizData {
  title: string;
  mcqs: QuizMcq[];
  essays: QuizEssay[];
}

/**
 * An essay's mark. The model's mark is a draft (`provisional`): it comes with
 * the rubric points it matched and missed, and the student can change it.
 */
export interface QuizGrade {
  awarded: number;
  outOf: number;
  feedback: string;
  matchedPoints: string[];
  missedPoints: string[];
  provisional: boolean;
  /** The student's own mark, replacing the model's. */
  override?: number;
}

export interface QuizEntry {
  id: string;
  pageId?: string;
  quiz: QuizData;
  /** Chosen option per multiple-choice question. */
  answers?: Record<number, number>;
  /** Written answer per essay question. */
  essayAnswers?: Record<number, string>;
  /** Mark per essay question, from the last marking. */
  essayGrades?: Record<number, QuizGrade>;
  /** Marks awarded and available, from the last marking. */
  score?: number;
  outOf?: number;
  checkedAt?: string;
  createdAt: string;
}

/** A request from the page to the AI panel (the editor's AI slash commands). */
export interface AiCommand {
  kind: 'ask' | 'summary' | 'quiz';
  /** ask: a question to send; summary: the notes above the caret. */
  text?: string;
  /** Changes with every request, so the same command can be sent twice. */
  nonce: number;
}

export interface AiArtifactData {
  askHistory: Array<{
    id: string;
    pageId?: string;
    question: string;
    answer: string;
    /** The highlighted passage the question was about. */
    quote?: string;
    /** Web pages the answer drew on, numbered as the answer cites them. */
    sources?: Array<{ title: string; link: string }>;
    /** The model's reasoning, when it thought before answering. */
    thinking?: string;
    /** Seconds spent thinking. */
    thinkingSeconds?: number;
    createdAt: string;
  }>;
  doHistory: Array<{
    id: string;
    pageId?: string;
    instruction: string;
    summary: string;
    steps: string[];
    thinking?: string;
    thinkingSeconds?: number;
    createdAt: string;
  }>;
  quizzes: QuizEntry[];
}
