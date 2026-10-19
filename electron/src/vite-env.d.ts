/// <reference types="vite/client" />

import type { MarioElectronApi } from '../electron/preload';

declare global {
  interface Window {
    mario: MarioElectronApi;
  }
}
