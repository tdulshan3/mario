import { Extension, type Editor } from '@tiptap/core';
import { Plugin, PluginKey, type EditorState } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';

/**
 * Inline Ask's place in the page: a widget after the block the caret was in, so
 * the box sits where you were writing and the page flows around it instead of
 * being covered (Mario v1's in-page answer). The box itself is React, rendered
 * into `host` through a portal.
 *
 * The plugin keeps the anchor and the selection the box was opened on, both
 * mapped through every edit, so Insert Below and Replace Selection still land in
 * the right place after the page changes underneath.
 */

export interface InlineAskAnchor {
  /** Position after the caret's top-level block: where the box sits and answers go. */
  pos: number;
  /** The selection it was opened on (from === to when nothing was highlighted). */
  from: number;
  to: number;
  /** Changes on every open, so React can start fresh. */
  nonce: number;
}

export const inlineAskKey = new PluginKey<InlineAskAnchor | null>('marioInlineAsk');

type Meta = { open: InlineAskAnchor } | { close: true };

export const InlineAsk = Extension.create<Record<string, never>, { host: HTMLElement }>({
  name: 'marioInlineAsk',

  addStorage() {
    const host = document.createElement('div');
    host.className = 'mario-inline-ask-host';
    host.contentEditable = 'false';
    return { host };
  },

  addProseMirrorPlugins() {
    const storage = this.storage;
    const host = () => storage.host as HTMLElement;
    return [
      new Plugin<InlineAskAnchor | null>({
        key: inlineAskKey,
        state: {
          init: () => null,
          apply(tr, prev) {
            const meta = tr.getMeta(inlineAskKey) as Meta | undefined;
            if (meta && 'close' in meta) return null;
            if (meta && 'open' in meta) return meta.open;
            if (!prev || !tr.docChanged) return prev;
            const map = (p: number, assoc: number) => Math.min(tr.doc.content.size, Math.max(0, tr.mapping.map(p, assoc)));
            return { ...prev, pos: map(prev.pos, -1), from: map(prev.from, 1), to: map(prev.to, -1) };
          },
        },
        props: {
          decorations(state) {
            const anchor = inlineAskKey.getState(state);
            if (!anchor) return null;
            return DecorationSet.create(state.doc, [
              Decoration.widget(anchor.pos, host, {
                key: 'mario-inline-ask',
                side: 1,
                ignoreSelection: true,
                // Typing in the box is the box's, not the page's.
                stopEvent: () => true,
              }),
            ]);
          },
        },
      }),
    ];
  },
});

/** Opens Inline Ask after the caret's block, remembering the selection. */
export function openInlineAsk(editor: Editor): HTMLElement | null {
  const { state } = editor;
  const sel = state.selection;
  const $to = state.doc.resolve(sel.to);
  const pos = $to.depth >= 1 ? $to.after(1) : sel.to;
  const anchor: InlineAskAnchor = { pos, from: sel.from, to: sel.to, nonce: Date.now() };
  editor.view.dispatch(state.tr.setMeta(inlineAskKey, { open: anchor } satisfies Meta).setMeta('addToHistory', false));
  return inlineAskHost(editor);
}

export function closeInlineAsk(editor: Editor) {
  if (editor.isDestroyed || !inlineAskKey.getState(editor.state)) return;
  editor.view.dispatch(editor.state.tr.setMeta(inlineAskKey, { close: true } satisfies Meta).setMeta('addToHistory', false));
}

export const inlineAskAnchor = (state: EditorState) => inlineAskKey.getState(state) ?? null;

/** The element the box is rendered into (a portal target inside the page). */
export const inlineAskHost = (editor: Editor): HTMLElement | null =>
  (editor.storage as unknown as Record<string, { host?: HTMLElement }>).marioInlineAsk?.host ?? null;

