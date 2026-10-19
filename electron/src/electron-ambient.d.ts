declare module 'electron' {
  export interface BrowserWindow {
    show(): void;
    focus(): void;
    destroy(): void;
    isDestroyed(): boolean;
    loadURL(url: string): Promise<void>;
    loadFile(filePath: string): Promise<void>;
    webContents: {
      send(channel: string, ...args: unknown[]): void;
      once(event: string, listener: (...args: unknown[]) => void): void;
      capturePage(): Promise<{ toPNG(): Buffer }>;
      executeJavaScript(code: string): Promise<unknown>;
      setWindowOpenHandler(
        handler: (details: { url: string }) => { action: 'allow' | 'deny' },
      ): void;
      printToPDF(options?: Record<string, unknown>): Promise<Buffer>;
    };
  }

  export const BrowserWindow: {
    new (options?: Record<string, unknown>): BrowserWindow;
    getAllWindows(): BrowserWindow[];
  };

  export const app: {
    whenReady(): Promise<void>;
    on(event: string, listener: (...args: unknown[]) => void): void;
    quit(): void;
  };

  export const ipcMain: {
    handle(
      channel: string,
      listener: (event: unknown, ...args: any[]) => unknown,
    ): void;
  };

  export const ipcRenderer: {
    invoke(channel: string, ...args: unknown[]): Promise<any>;
    on(channel: string, listener: (event: unknown, ...args: any[]) => void): void;
    removeListener(
      channel: string,
      listener: (event: unknown, ...args: any[]) => void,
    ): void;
  };

  export const contextBridge: {
    exposeInMainWorld(apiKey: string, api: unknown): void;
  };

  export const dialog: {
    showOpenDialog(
      win: BrowserWindow,
      options: Record<string, unknown>,
    ): Promise<{ canceled: boolean; filePaths: string[] }>;
    showSaveDialog(
      win: BrowserWindow,
      options: Record<string, unknown>,
    ): Promise<{ canceled: boolean; filePath?: string }>;
  };

  export const shell: {
    openExternal(url: string): Promise<void>;
  };

  export const Menu: {
    buildFromTemplate(template: Array<Record<string, unknown>>): unknown;
  };

  export const nativeImage: {
    createFromPath(path: string): {
      resize(opts: { width: number; height: number }): unknown;
    };
  };

  export class Tray {
    constructor(image: unknown);
    setToolTip(tip: string): void;
    setContextMenu(menu: unknown): void;
    on(event: string, listener: () => void): void;
  }
}
