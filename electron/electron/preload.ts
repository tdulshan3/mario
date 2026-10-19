import { contextBridge, ipcRenderer } from 'electron';
import {
  AiArtifactData,
  AuthUser,
  CollaboratorRole,
  DiscoveredEndpoint,
  LlmEffort,
  LlmProviderConfig,
  LlmProviderKind,
  Notebook,
  NotePage,
  PageContent,
  Section,
  SettingsState,
  TreeSnapshot,
} from '../src/shared/types';

export interface MarioElectronApi {
  auth: {
    restore: () => Promise<AuthUser | null>;
    signIn: () => Promise<AuthUser>;
    signOut: () => Promise<void>;
  };
  tree: {
    getSnapshot: () => Promise<TreeSnapshot>;
    refresh: () => Promise<TreeSnapshot>;
    syncNow: () => Promise<TreeSnapshot>;
    createNotebook: (name: string, colorIndex?: number) => Promise<Notebook>;
    updateNotebook: (nb: Notebook) => Promise<Notebook>;
    deleteNotebook: (notebookId: string) => Promise<void>;
    createSection: (
      notebookId: string,
      name: string,
      colorIndex?: number,
    ) => Promise<Section>;
    updateSection: (sec: Section) => Promise<Section>;
    deleteSection: (notebookId: string, sectionId: string) => Promise<void>;
    createPage: (
      notebookId: string,
      sectionId: string,
      title?: string,
      initialContent?: PageContent,
    ) => Promise<NotePage>;
    updatePage: (page: NotePage) => Promise<NotePage>;
    deletePage: (
      notebookId: string,
      sectionId: string,
      pageId: string,
    ) => Promise<void>;
    onChanged: (cb: (snap: TreeSnapshot) => void) => () => void;
  };
  page: {
    loadContent: (
      pageId: string,
      driveFileId: string | null,
      title?: string,
    ) => Promise<PageContent>;
    saveContent: (
      pageId: string,
      driveFileId: string | null,
      content: PageContent,
    ) => Promise<void>;
  };
  share: {
    inviteCollaborator: (
      notebookId: string,
      email: string,
      role: CollaboratorRole,
    ) => Promise<void>;
  };
  asset: {
    pickImage: () => Promise<{
      localPath: string;
      driveId: string;
      dataUrl: string;
    } | null>;
    resolveImage: (url?: string, driveId?: string) => Promise<string | null>;
  };
  settings: {
    load: () => Promise<SettingsState>;
    save: (next: SettingsState) => Promise<SettingsState>;
  };
  ai: {
    getProviders: () => Promise<{
      providers: LlmProviderConfig[];
      activeId: string | null;
      serperKeyConfigured: boolean;
      webSearchEnabled: boolean;
    }>;
    saveProvider: (
      config: LlmProviderConfig,
      apiKey?: string | null,
      setActive?: boolean,
    ) => Promise<{
      providers: LlmProviderConfig[];
      activeId: string | null;
      serperKeyConfigured: boolean;
      webSearchEnabled: boolean;
    }>;
    deleteProvider: (id: string) => Promise<{
      providers: LlmProviderConfig[];
      activeId: string | null;
      serperKeyConfigured: boolean;
      webSearchEnabled: boolean;
    }>;
    setActiveProvider: (id: string) => Promise<{
      providers: LlmProviderConfig[];
      activeId: string | null;
      serperKeyConfigured: boolean;
      webSearchEnabled: boolean;
    }>;
    setProviderModel: (
      id: string,
      model: string,
      effort?: LlmEffort,
    ) => Promise<{
      providers: LlmProviderConfig[];
      activeId: string | null;
      serperKeyConfigured: boolean;
      webSearchEnabled: boolean;
    }>;
    setSerperConfig: (apiKey: string | null, enabled: boolean) => Promise<void>;
    listModels: (config: {
      id?: string;
      kind: LlmProviderKind;
      baseUrl: string;
      apiKey?: string;
    }) => Promise<string[]>;
    discoverLocal: () => Promise<DiscoveredEndpoint[]>;
    chat: (opts: {
      systemPrompt: string;
      userPrompt: string;
      temperature?: number;
      effort?: LlmEffort;
    }) => Promise<{ text: string; reasoning: string }>;
    structured: (opts: {
      schemaName: string;
      schema: Record<string, unknown>;
      systemPrompt: string;
      userPrompt: string;
      temperature?: number;
    }) => Promise<Record<string, unknown>>;
    webSearch: (
      query: string,
    ) => Promise<Array<{ title: string; link: string; snippet: string }>>;
    getUserSkills: () => Promise<string[]>;
    readArtifacts: (notebookId: string) => Promise<AiArtifactData>;
    writeArtifacts: (notebookId: string, data: AiArtifactData) => Promise<void>;
  };
  exportFile: {
    markdown: (defaultFilename: string, markdownContent: string) => Promise<boolean>;
    pdf: (defaultFilename: string, htmlDocument: string) => Promise<boolean>;
  };
}

const api: MarioElectronApi = {
  auth: {
    restore: () => ipcRenderer.invoke('auth:restore'),
    signIn: () => ipcRenderer.invoke('auth:signIn'),
    signOut: () => ipcRenderer.invoke('auth:signOut'),
  },
  tree: {
    getSnapshot: () => ipcRenderer.invoke('tree:getSnapshot'),
    refresh: () => ipcRenderer.invoke('tree:refresh'),
    syncNow: () => ipcRenderer.invoke('tree:syncNow'),
    createNotebook: (name, colorIndex) =>
      ipcRenderer.invoke('tree:createNotebook', name, colorIndex),
    updateNotebook: (nb) => ipcRenderer.invoke('tree:updateNotebook', nb),
    deleteNotebook: (notebookId) =>
      ipcRenderer.invoke('tree:deleteNotebook', notebookId),
    createSection: (notebookId, name, colorIndex) =>
      ipcRenderer.invoke('tree:createSection', notebookId, name, colorIndex),
    updateSection: (sec) => ipcRenderer.invoke('tree:updateSection', sec),
    deleteSection: (notebookId, sectionId) =>
      ipcRenderer.invoke('tree:deleteSection', notebookId, sectionId),
    createPage: (notebookId, sectionId, title, initialContent) =>
      ipcRenderer.invoke(
        'tree:createPage',
        notebookId,
        sectionId,
        title,
        initialContent,
      ),
    updatePage: (page) => ipcRenderer.invoke('tree:updatePage', page),
    deletePage: (notebookId, sectionId, pageId) =>
      ipcRenderer.invoke('tree:deletePage', notebookId, sectionId, pageId),
    onChanged: (cb) => {
      const listener = (_: unknown, snap: TreeSnapshot) => cb(snap);
      ipcRenderer.on('tree:changed', listener);
      return () => ipcRenderer.removeListener('tree:changed', listener);
    },
  },
  page: {
    loadContent: (pageId, driveFileId, title) =>
      ipcRenderer.invoke('page:loadContent', pageId, driveFileId, title),
    saveContent: (pageId, driveFileId, content) =>
      ipcRenderer.invoke('page:saveContent', pageId, driveFileId, content),
  },
  share: {
    inviteCollaborator: (notebookId, email, role) =>
      ipcRenderer.invoke('share:inviteCollaborator', notebookId, email, role),
  },
  asset: {
    pickImage: () => ipcRenderer.invoke('asset:pickImage'),
    resolveImage: (url, driveId) =>
      ipcRenderer.invoke('asset:resolveImage', url, driveId),
  },
  settings: {
    load: () => ipcRenderer.invoke('settings:load'),
    save: (next) => ipcRenderer.invoke('settings:save', next),
  },
  ai: {
    getProviders: () => ipcRenderer.invoke('ai:getProviders'),
    saveProvider: (config, apiKey, setActive) =>
      ipcRenderer.invoke('ai:saveProvider', config, apiKey, setActive),
    deleteProvider: (id) => ipcRenderer.invoke('ai:deleteProvider', id),
    setActiveProvider: (id) => ipcRenderer.invoke('ai:setActiveProvider', id),
    setProviderModel: (id, model, effort) =>
      ipcRenderer.invoke('ai:setProviderModel', id, model, effort),
    setSerperConfig: (apiKey, enabled) =>
      ipcRenderer.invoke('ai:setSerperConfig', apiKey, enabled),
    listModels: (config) => ipcRenderer.invoke('ai:listModels', config),
    discoverLocal: () => ipcRenderer.invoke('ai:discoverLocal'),
    chat: (opts) => ipcRenderer.invoke('ai:chat', opts),
    structured: (opts) => ipcRenderer.invoke('ai:structured', opts),
    webSearch: (query) => ipcRenderer.invoke('ai:webSearch', query),
    getUserSkills: () => ipcRenderer.invoke('ai:getUserSkills'),
    readArtifacts: (notebookId) =>
      ipcRenderer.invoke('ai:readArtifacts', notebookId),
    writeArtifacts: (notebookId, data) =>
      ipcRenderer.invoke('ai:writeArtifacts', notebookId, data),
  },
  exportFile: {
    markdown: (defaultFilename, markdownContent) =>
      ipcRenderer.invoke('export:markdown', defaultFilename, markdownContent),
    pdf: (defaultFilename, htmlDocument) =>
      ipcRenderer.invoke('export:pdf', defaultFilename, htmlDocument),
  },
};

contextBridge.exposeInMainWorld('mario', api);
