import React, { useEffect, useState } from 'react';
import {
  Button,
  Column,
  Content,
  Form,
  FormRow,
  FormSection,
  FormValue,
  PopUpButton,
  Row,
  SegmentedControl,
  Sheet,
  Sidebar,
  SidebarItem,
  SidebarSection,
  Slider,
  Switch,
  TextField,
  Titlebar,
  Window,
  WindowMain,
} from '../macos/macos';
import type {
  AuthUser,
  CanvasWidth,
  DiscoveredEndpoint,
  LlmEffort,
  LlmProviderConfig,
  LlmProviderKind,
  MarioThemeMode,
  SettingsState,
} from '../shared/types';
import { newClientId } from '../shared/ids';

export type SettingsPane =
  | 'appearance'
  | 'editor'
  | 'voice'
  | 'ai'
  | 'sync'
  | 'account'
  | 'about';

export interface SettingsWindowProps {
  open: boolean;
  initialPane?: SettingsPane;
  onClose: () => void;
  settings: SettingsState;
  onSettingsChange: (next: SettingsState) => void;
  user: AuthUser | null;
  pendingCount: number;
  isSyncing: boolean;
  onSyncNow: () => Promise<void>;
  onSignOut: () => Promise<void>;
  onProvidersChanged: () => void;
}

export function SettingsWindow({
  open,
  initialPane = 'appearance',
  onClose,
  settings,
  onSettingsChange,
  user,
  pendingCount,
  isSyncing,
  onSyncNow,
  onSignOut,
  onProvidersChanged,
}: SettingsWindowProps) {
  const [pane, setPane] = useState<SettingsPane>(initialPane);
  const [providers, setProviders] = useState<LlmProviderConfig[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [webSearchEnabled, setWebSearchEnabled] = useState(true);
  const [serperConfigured, setSerperConfigured] = useState(false);
  const [serperDraft, setSerperDraft] = useState('');
  const [discovered, setDiscovered] = useState<DiscoveredEndpoint[]>([]);
  const [scanningLocal, setScanningLocal] = useState(false);

  // Add / Edit Provider draft
  const [editingProviderId, setEditingProviderId] = useState<string | null>(
    null,
  );
  const [draftLabel, setDraftLabel] = useState('LAN Server');
  const [draftKind, setDraftKind] =
    useState<LlmProviderKind>('openAiCompatible');
  const [draftBaseUrl, setDraftBaseUrl] = useState(
    'http://192.168.1.118:8081/v1',
  );
  const [draftModel, setDraftModel] = useState('');
  const [draftEffort, setDraftEffort] = useState<LlmEffort>('medium');
  const [draftApiKey, setDraftApiKey] = useState('');
  const [fetchedModels, setFetchedModels] = useState<string[]>([]);
  const [fetchingModels, setFetchingModels] = useState(false);

  useEffect(() => {
    setPane(initialPane);
  }, [initialPane, open]);

  const loadAiConfig = async () => {
    const res = await window.mario.ai.getProviders();
    setProviders(res.providers);
    setActiveId(res.activeId);
    setWebSearchEnabled(res.webSearchEnabled);
    setSerperConfigured(res.serperKeyConfigured);
  };

  useEffect(() => {
    if (open) {
      loadAiConfig();
    }
  }, [open]);

  const updateSetting = <K extends keyof SettingsState>(
    key: K,
    val: SettingsState[K],
  ) => {
    onSettingsChange({ ...settings, [key]: val });
  };

  const startNewProvider = (preset?: DiscoveredEndpoint) => {
    setEditingProviderId('__new__');
    setDraftLabel(preset?.serverName ?? 'LAN Inference Server');
    setDraftKind(preset?.kind ?? 'openAiCompatible');
    setDraftBaseUrl(preset?.baseUrl ?? 'http://192.168.1.118:8081/v1');
    const modelNames = (preset?.models ?? []).map((m) => m.name);
    setDraftModel(modelNames[0] ?? '');
    setFetchedModels(modelNames);
    setDraftEffort('medium');
    setDraftApiKey('');
  };

  const startEditProvider = (p: LlmProviderConfig) => {
    setEditingProviderId(p.id);
    setDraftLabel(p.label);
    setDraftKind(p.kind);
    setDraftBaseUrl(p.baseUrl);
    setDraftModel(p.model);
    setDraftEffort(p.effort);
    setDraftApiKey('');
    setFetchedModels(p.model ? [p.model] : []);
  };

  const handleFetchModels = async () => {
    setFetchingModels(true);
    try {
      const list = await window.mario.ai.listModels({
        id:
          editingProviderId && editingProviderId !== '__new__'
            ? editingProviderId
            : undefined,
        kind: draftKind,
        baseUrl: draftBaseUrl,
        apiKey: draftApiKey || undefined,
      });
      setFetchedModels(list);
      if (list.length > 0 && !draftModel) {
        setDraftModel(list[0]);
      }
    } finally {
      setFetchingModels(false);
    }
  };

  const handleSaveProvider = async () => {
    const id =
      editingProviderId && editingProviderId !== '__new__'
        ? editingProviderId
        : newClientId('llm');
    const cfg: LlmProviderConfig = {
      id,
      label: draftLabel.trim() || 'AI Provider',
      kind: draftKind,
      baseUrl: draftBaseUrl.trim(),
      model: draftModel.trim(),
      hasApiKey: Boolean(draftApiKey),
      capabilities: {
        strictJsonSchema: draftKind !== 'openAiCompatible',
        jsonMode: true,
        tools: true,
        embeddings: false,
        vision: false,
        contextTokens: 65536,
      },
      contextTokens: 65536,
      effort: draftEffort,
    };
    const next = await window.mario.ai.saveProvider(
      cfg,
      draftApiKey ? draftApiKey : undefined,
      true,
    );
    setProviders(next.providers);
    setActiveId(next.activeId);
    setEditingProviderId(null);
    onProvidersChanged();
  };

  const handleScanLocal = async () => {
    setScanningLocal(true);
    try {
      const eps = await window.mario.ai.discoverLocal();
      setDiscovered(eps);
    } finally {
      setScanningLocal(false);
    }
  };

  if (!open) return null;

  const paneTitle: Record<SettingsPane, string> = {
    appearance: 'Appearance',
    editor: 'Editor',
    voice: 'Voice',
    ai: 'AI & Local Models',
    sync: 'Sync & Offline',
    account: 'Account',
    about: 'About Mario',
  };

  return (
    <Sheet
      open={open}
      onClose={() => onClose()}
      top={44}
      buttons={[{ label: 'Done', role: 'default', onClick: onClose }]}
    >
      <div style={{ width: 720, height: 500, margin: '-8px -4px' }}>
        <Window style={{ width: '100%', height: '100%' }}>
          <Sidebar size="medium" width={195} label="Settings Categories">
            <SidebarSection>
              <SidebarItem
                icon="sun"
                label="Appearance"
                selected={pane === 'appearance'}
                onClick={() => setPane('appearance')}
              />
              <SidebarItem
                icon="doc-text"
                label="Editor"
                selected={pane === 'editor'}
                onClick={() => setPane('editor')}
              />
              <SidebarItem
                icon="mic"
                label="Voice"
                selected={pane === 'voice'}
                onClick={() => setPane('voice')}
              />
              <SidebarItem
                icon="bolt"
                label="AI & Models"
                selected={pane === 'ai'}
                onClick={() => setPane('ai')}
              />
              <SidebarItem
                icon="icloud"
                label="Sync"
                selected={pane === 'sync'}
                onClick={() => setPane('sync')}
              />
              <SidebarItem
                icon="person-circle"
                label="Account"
                selected={pane === 'account'}
                onClick={() => setPane('account')}
              />
              <SidebarItem
                icon="info-circle"
                label="About"
                selected={pane === 'about'}
                onClick={() => setPane('about')}
              />
            </SidebarSection>
          </Sidebar>

          <WindowMain>
            <Titlebar title={paneTitle[pane]} toolbarStyle="compact" />
            <Content>
              {pane === 'appearance' && (
                <Form>
                  <FormSection title="Theme & Canvas">
                    <FormRow label="Appearance">
                      <SegmentedControl
                        size="small"
                        label="Theme Mode"
                        value={
                          settings.themeMode === 'night' ||
                          settings.themeMode === 'black'
                            ? 'night'
                            : settings.themeMode === 'light' ||
                              settings.themeMode === 'white'
                            ? 'light'
                            : 'system'
                        }
                        onChange={(v) =>
                          updateSetting('themeMode', v as MarioThemeMode)
                        }
                        options={[
                          { value: 'system', label: 'Auto' },
                          { value: 'light', label: 'Light' },
                          { value: 'night', label: 'Dark' },
                        ]}
                      />
                    </FormRow>
                    <FormRow label="Page Canvas Width">
                      <SegmentedControl
                        size="small"
                        label="Canvas Width"
                        value={settings.canvasWidth}
                        onChange={(v) =>
                          updateSetting('canvasWidth', v as CanvasWidth)
                        }
                        options={[
                          { value: 'narrow', label: 'Narrow' },
                          { value: 'medium', label: 'Medium' },
                          { value: 'full', label: 'Full' },
                        ]}
                      />
                    </FormRow>
                  </FormSection>
                </Form>
              )}

              {pane === 'editor' && (
                <Form>
                  <FormSection title="Typography & Editing">
                    <FormRow
                      label={`Font Scale (${Math.round(
                        settings.fontScale * 100,
                      )}%)`}
                    >
                      <Slider
                        min={75}
                        max={150}
                        value={Math.round(settings.fontScale * 100)}
                        onChange={(v) => updateSetting('fontScale', v / 100)}
                      />
                    </FormRow>
                    <FormRow label="Spell Check">
                      <Switch
                        checked={settings.spellCheck}
                        onChange={(v) => updateSetting('spellCheck', v)}
                      />
                    </FormRow>
                    <FormRow label="Auto-Correct Math Macros">
                      <Switch
                        checked={settings.autoCorrectMath}
                        onChange={(v) => updateSetting('autoCorrectMath', v)}
                      />
                    </FormRow>
                    <FormRow label="Ask AI on Text Highlight">
                      <Switch
                        checked={settings.askOnHighlight}
                        onChange={(v) => updateSetting('askOnHighlight', v)}
                      />
                    </FormRow>
                  </FormSection>
                </Form>
              )}

              {pane === 'voice' && (
                <Form>
                  <FormSection
                    title="Speech & Transcription"
                    footer="Used for voice notes and dictation."
                  >
                    <FormRow label="Language">
                      <PopUpButton
                        size="small"
                        value={settings.voiceLocale}
                        onChange={(v) => updateSetting('voiceLocale', v)}
                        options={[
                          { value: 'en_US', label: 'English (US)' },
                          { value: 'en_GB', label: 'English (UK)' },
                          { value: 'de_DE', label: 'German' },
                          { value: 'fr_FR', label: 'French' },
                          { value: 'ja_JP', label: 'Japanese' },
                        ]}
                      />
                    </FormRow>
                    <FormRow label="Hold Spacebar to Record">
                      <Switch
                        checked={settings.holdToRecord}
                        onChange={(v) => updateSetting('holdToRecord', v)}
                      />
                    </FormRow>
                  </FormSection>
                </Form>
              )}

              {pane === 'ai' && (
                <Column style={{ gap: 14 }}>
                  <Form>
                    <FormSection
                      title="Configured AI Providers"
                      footer="Mario supports local LAN OpenAI-compatible servers (llama.cpp, vLLM, LM Studio, Ollama) as well as cloud APIs."
                    >
                      {providers.map((p) => (
                        <FormRow
                          key={p.id}
                          label={p.label}
                          subtitle={`${p.kind} · ${p.baseUrl} · ${
                            p.model || 'default'
                          }`}
                        >
                          <Row style={{ gap: 6 }}>
                            <Button
                              size="small"
                              variant={
                                p.id === activeId ? 'prominent' : 'bordered'
                              }
                              onClick={async () => {
                                const next =
                                  await window.mario.ai.setActiveProvider(p.id);
                                setProviders(next.providers);
                                setActiveId(next.activeId);
                                onProvidersChanged();
                              }}
                            >
                              {p.id === activeId ? 'Active' : 'Use'}
                            </Button>
                            <Button
                              size="small"
                              variant="bordered"
                              icon="pencil"
                              label="Edit"
                              onClick={() => startEditProvider(p)}
                            />
                            <Button
                              size="small"
                              variant="borderless"
                              icon="trash"
                              label="Delete"
                              onClick={async () => {
                                const next =
                                  await window.mario.ai.deleteProvider(p.id);
                                setProviders(next.providers);
                                setActiveId(next.activeId);
                                onProvidersChanged();
                              }}
                            />
                          </Row>
                        </FormRow>
                      ))}
                      <FormRow label="Add Provider">
                        <Row style={{ gap: 6 }}>
                          <Button
                            size="small"
                            variant="tinted"
                            icon="plus"
                            onClick={() => startNewProvider()}
                          >
                            Add Provider…
                          </Button>
                          <Button
                            size="small"
                            variant="bordered"
                            icon="wifi"
                            disabled={scanningLocal}
                            onClick={handleScanLocal}
                          >
                            {scanningLocal
                              ? 'Scanning…'
                              : 'Scan Local Ports'}
                          </Button>
                        </Row>
                      </FormRow>
                    </FormSection>

                    {discovered.length > 0 && (
                      <FormSection title="Discovered Local Inference Servers">
                        {discovered.map((ep) => (
                          <FormRow
                            key={ep.baseUrl}
                            label={ep.serverName}
                            subtitle={`${ep.baseUrl} (${ep.models.length} models)`}
                          >
                            <Button
                              size="small"
                              variant="prominent"
                              onClick={() => startNewProvider(ep)}
                            >
                              Configure
                            </Button>
                          </FormRow>
                        ))}
                      </FormSection>
                    )}

                    {editingProviderId && (
                      <FormSection
                        title={
                          editingProviderId === '__new__'
                            ? 'New AI Provider'
                            : 'Edit AI Provider'
                        }
                      >
                        <FormRow label="Display Name">
                          <TextField
                            size="small"
                            value={draftLabel}
                            onChange={setDraftLabel}
                          />
                        </FormRow>
                        <FormRow label="Provider Type">
                          <PopUpButton
                            size="small"
                            value={draftKind}
                            onChange={(v) => {
                              const k = v as LlmProviderKind;
                              setDraftKind(k);
                              if (k === 'ollama')
                                setDraftBaseUrl('http://127.0.0.1:11434');
                              else if (k === 'openAi')
                                setDraftBaseUrl('https://api.openai.com/v1');
                              else if (k === 'anthropic')
                                setDraftBaseUrl('https://api.anthropic.com');
                              else if (k === 'gemini')
                                setDraftBaseUrl(
                                  'https://generativelanguage.googleapis.com',
                                );
                            }}
                            options={[
                              {
                                value: 'openAiCompatible',
                                label:
                                  'OpenAI-Compatible (LAN / llama.cpp / vLLM)',
                              },
                              { value: 'ollama', label: 'Ollama' },
                              { value: 'openAi', label: 'OpenAI' },
                              { value: 'anthropic', label: 'Anthropic Claude' },
                              { value: 'gemini', label: 'Google Gemini' },
                            ]}
                          />
                        </FormRow>
                        <FormRow label="Base URL">
                          <TextField
                            size="small"
                            value={draftBaseUrl}
                            onChange={setDraftBaseUrl}
                            placeholder="http://192.168.1.118:8081/v1"
                          />
                        </FormRow>
                        <FormRow
                          label="API Key"
                          subtitle="Stored in system keyring (leave blank for local LAN servers)"
                        >
                          <TextField
                            size="small"
                            type="password"
                            value={draftApiKey}
                            onChange={setDraftApiKey}
                            placeholder="Optional for LAN/Ollama"
                          />
                        </FormRow>
                        <FormRow label="Model">
                          <Row style={{ gap: 6 }}>
                            {fetchedModels.length > 0 ? (
                              <PopUpButton
                                size="small"
                                value={draftModel}
                                onChange={setDraftModel}
                                options={fetchedModels.map((m) => ({
                                  value: m,
                                  label: m,
                                }))}
                              />
                            ) : (
                              <TextField
                                size="small"
                                value={draftModel}
                                onChange={setDraftModel}
                                placeholder="Model ID"
                              />
                            )}
                            <Button
                              size="small"
                              variant="bordered"
                              disabled={fetchingModels}
                              onClick={handleFetchModels}
                            >
                              {fetchingModels ? 'Fetching…' : 'Fetch Models'}
                            </Button>
                          </Row>
                        </FormRow>
                        <FormRow label="Reasoning Effort">
                          <PopUpButton
                            size="small"
                            value={draftEffort}
                            onChange={(v) => setDraftEffort(v as LlmEffort)}
                            options={[
                              { value: 'off', label: 'Off' },
                              { value: 'low', label: 'Low' },
                              { value: 'medium', label: 'Medium' },
                              { value: 'high', label: 'High' },
                            ]}
                          />
                        </FormRow>
                        <FormRow label="Actions">
                          <Row style={{ gap: 6 }}>
                            <Button
                              size="small"
                              variant="bordered"
                              onClick={() => setEditingProviderId(null)}
                            >
                              Cancel
                            </Button>
                            <Button
                              size="small"
                              variant="prominent"
                              onClick={handleSaveProvider}
                            >
                              Save Provider
                            </Button>
                          </Row>
                        </FormRow>
                      </FormSection>
                    )}

                    <FormSection
                      title="Web Search Grounding"
                      footer="Uses Serper.dev Google Search when a key is saved in keyring, or falls back to Wikipedia Search."
                    >
                      <FormRow label="Enable Web Search">
                        <Switch
                          checked={webSearchEnabled}
                          onChange={async (enabled) => {
                            setWebSearchEnabled(enabled);
                            await window.mario.ai.setSerperConfig(null, enabled);
                          }}
                        />
                      </FormRow>
                      <FormRow
                        label="Serper API Key"
                        subtitle={
                          serperConfigured
                            ? 'Configured in system keyring'
                            : 'Not configured (using Wikipedia fallback)'
                        }
                      >
                        <Row style={{ gap: 6 }}>
                          <TextField
                            size="small"
                            type="password"
                            value={serperDraft}
                            onChange={setSerperDraft}
                            placeholder="Optional Serper key"
                          />
                          <Button
                            size="small"
                            variant="bordered"
                            onClick={async () => {
                              await window.mario.ai.setSerperConfig(
                                serperDraft,
                                webSearchEnabled,
                              );
                              setSerperDraft('');
                              await loadAiConfig();
                            }}
                          >
                            Save Key
                          </Button>
                        </Row>
                      </FormRow>
                    </FormSection>
                  </Form>
                </Column>
              )}

              {pane === 'sync' && (
                <Form>
                  <FormSection
                    title="Cloud Sync & Offline Outbox"
                    footer="Mario writes every note locally first (~/.local/share/com.marionote.app.mario) and syncs to Firestore and Google Drive appDataFolder in the background."
                  >
                    <FormRow label="Offline Mode">
                      <Switch
                        checked={settings.offlineMode}
                        onChange={(v) => updateSetting('offlineMode', v)}
                      />
                    </FormRow>
                    <FormRow label="Pending Outbox Operations">
                      <FormValue>{pendingCount} queued</FormValue>
                    </FormRow>
                    <FormRow label="Sync Status">
                      <FormValue>
                        {isSyncing ? 'Syncing with cloud…' : 'Up to date'}
                      </FormValue>
                    </FormRow>
                    <FormRow label="Manual Sync">
                      <Button
                        size="small"
                        variant="prominent"
                        icon="arrow-clockwise"
                        onClick={onSyncNow}
                      >
                        Sync Now
                      </Button>
                    </FormRow>
                  </FormSection>
                </Form>
              )}

              {pane === 'account' && (
                <Form>
                  <FormSection title="Signed-In Google Account">
                    <FormRow label="Name">
                      <FormValue>{user?.displayName || '—'}</FormValue>
                    </FormRow>
                    <FormRow label="Email">
                      <FormValue>{user?.email || '—'}</FormValue>
                    </FormRow>
                    <FormRow label="User ID">
                      <FormValue>{user?.uid || '—'}</FormValue>
                    </FormRow>
                    <FormRow label="Session">
                      <Button
                        size="small"
                        variant="destructive"
                        onClick={onSignOut}
                      >
                        Sign Out
                      </Button>
                    </FormRow>
                  </FormSection>
                </Form>
              )}

              {pane === 'about' && (
                <Form>
                  <FormSection title="Mario Note App (Electron)">
                    <FormRow label="Version">
                      <FormValue>2.0.0 (Electron + macOS 27 UI)</FormValue>
                    </FormRow>
                    <FormRow label="Data Directory">
                      <FormValue>
                        ~/.local/share/com.marionote.app.mario
                      </FormValue>
                    </FormRow>
                    <FormRow label="User Skills Directory">
                      <FormValue>
                        ~/.local/share/com.marionote.app.mario/skills/*.md
                      </FormValue>
                    </FormRow>
                  </FormSection>
                </Form>
              )}
            </Content>
          </WindowMain>
        </Window>
      </div>
    </Sheet>
  );
}
