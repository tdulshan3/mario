import React, { useMemo, useState } from 'react';
import {
  Column,
  List,
  SearchField,
  Sheet,
  type ListItemData,
  type RowId,
} from '../macos/macos';
import type { Notebook, NotePage, Section } from '../shared/types';

export interface GlobalSearchSheetProps {
  open: boolean;
  onClose: () => void;
  notebooks: Notebook[];
  sectionsByNotebook: Record<string, Section[]>;
  pagesByKey: Record<string, NotePage[]>;
  onSelectPage: (notebookId: string, sectionId: string, pageId: string) => void;
  onQuickCreatePage: (title: string) => void;
}

export function GlobalSearchSheet({
  open,
  onClose,
  notebooks,
  sectionsByNotebook,
  pagesByKey,
  onSelectPage,
  onQuickCreatePage,
}: GlobalSearchSheetProps) {
  const [query, setQuery] = useState('');
  const [selection, setSelection] = useState<RowId[]>([]);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    const out: Array<{
      id: string;
      title: string;
      subtitle: string;
      notebookId: string;
      sectionId: string;
      pageId: string;
    }> = [];
    for (const nb of notebooks) {
      for (const sec of sectionsByNotebook[nb.id] ?? []) {
        for (const p of pagesByKey[`${nb.id}/${sec.id}`] ?? []) {
          if (
            !q ||
            p.title.toLowerCase().includes(q) ||
            sec.name.toLowerCase().includes(q) ||
            nb.name.toLowerCase().includes(q)
          ) {
            out.push({
              id: p.id,
              title: p.title || 'Untitled Page',
              subtitle: `${nb.name} › ${sec.name}`,
              notebookId: nb.id,
              sectionId: sec.id,
              pageId: p.id,
            });
          }
        }
      }
    }
    return out.slice(0, 30);
  }, [query, notebooks, sectionsByNotebook, pagesByKey]);

  const listItems = useMemo<ListItemData[]>(() => {
    const items: ListItemData[] = results.map((r) => ({
      id: r.id,
      title: r.title,
      subtitle: r.subtitle,
      icon: 'doc-text',
    }));
    if (query.trim().length > 0) {
      items.push({
        id: '__create__',
        title: `Create new page “${query.trim()}”`,
        subtitle: 'Quick create in current section',
        icon: 'plus-circle',
      });
    }
    return items;
  }, [results, query]);

  const triggerItem = (id: RowId) => {
    if (id === '__create__') {
      onQuickCreatePage(query.trim());
      setQuery('');
      onClose();
      return;
    }
    const hit = results.find((r) => r.id === id);
    if (hit) {
      onSelectPage(hit.notebookId, hit.sectionId, hit.pageId);
      setQuery('');
      onClose();
    }
  };

  return (
    <Sheet
      open={open}
      onClose={() => onClose()}
      title="Go to Page (Ctrl+K)"
      top={60}
      buttons={[
        { label: 'Cancel', role: 'cancel', onClick: onClose },
        {
          label: 'Open',
          role: 'default',
          disabled: listItems.length === 0,
          onClick: () => {
            const targetId = selection[0] ?? listItems[0]?.id;
            if (targetId != null) triggerItem(targetId);
          },
        },
      ]}
    >
      <Column style={{ width: 440, gap: 10 }}>
        <SearchField
          autoFocus
          value={query}
          onChange={setQuery}
          placeholder="Search pages, sections, or notebooks…"
          label="Global Search"
          onKeyDown={(e) => {
            if (e.key === 'Enter' && listItems[0]) {
              e.preventDefault();
              triggerItem(selection[0] ?? listItems[0].id);
            }
          }}
        />
        <div
          style={{
            maxHeight: 280,
            overflowY: 'auto',
            border: '1px solid var(--mac-separator)',
            borderRadius: 6,
          }}
        >
          <List
            label="Matching Pages"
            items={listItems}
            selection={selection}
            onSelectionChange={setSelection}
            onItemAction={triggerItem}
          />
        </div>
      </Column>
    </Sheet>
  );
}
