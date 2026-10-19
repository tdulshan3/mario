import {
  DiscoveredEndpoint,
  DiscoveredModel,
  LlmCapabilities,
  LlmEffort,
  LlmProviderConfig,
  LlmProviderKind,
} from '../src/shared/types';
import { KeyringStore, SharedPreferencesStore } from './storage';

export function defaultCapabilitiesFor(kind: LlmProviderKind): LlmCapabilities {
  switch (kind) {
    case 'ollama':
      return {
        strictJsonSchema: true,
        jsonMode: true,
        tools: true,
        embeddings: true,
        vision: false,
        contextTokens: 65536,
      };
    case 'openAi':
      return {
        strictJsonSchema: true,
        jsonMode: true,
        tools: true,
        embeddings: true,
        vision: true,
        contextTokens: 128000,
      };
    case 'anthropic':
      return {
        strictJsonSchema: true,
        jsonMode: true,
        tools: true,
        embeddings: false,
        vision: true,
        contextTokens: 200000,
      };
    case 'gemini':
      return {
        strictJsonSchema: false,
        jsonMode: true,
        tools: true,
        embeddings: true,
        vision: true,
        contextTokens: 1048576,
      };
    case 'openAiCompatible':
    default:
      return {
        strictJsonSchema: false,
        jsonMode: true,
        tools: false,
        embeddings: false,
        vision: false,
        contextTokens: 65536,
      };
  }
}

export function normalizeOpenAiBaseUrl(input: string): string {
  let u = input.trim();
  if (!u) return 'http://localhost:8080/v1';
  if (!/^https?:\/\//i.test(u)) {
    u = `http://${u}`;
  }
  u = u.replace(/\/+$/, '');
  for (const suffix of [
    '/v1/chat/completions',
    '/chat/completions',
    '/v1/completions',
    '/completions',
    '/v1/embeddings',
    '/embeddings',
    '/v1/models',
    '/models',
    '/api/tags',
    '/api/chat',
  ]) {
    if (u.toLowerCase().endsWith(suffix)) {
      u = u.slice(0, -suffix.length);
      break;
    }
  }
  try {
    const parsed = new URL(u);
    if (!parsed.pathname || parsed.pathname === '/') {
      parsed.pathname = '/v1';
    }
    return parsed.toString().replace(/\/+$/, '');
  } catch {
    return u.endsWith('/v1') ? u : `${u}/v1`;
  }
}

export function splitThinkTags(raw: string): { text: string; reasoning: string } {
  const thinkMatches: string[] = [];
  const cleaned = raw.replace(/<think>([\s\S]*?)<\/think>/gi, (_, inner) => {
    thinkMatches.push(String(inner).trim());
    return '';
  });
  return {
    text: cleaned.trim(),
    reasoning: thinkMatches.join('\n\n').trim(),
  };
}

export function extractJsonObject(raw: string): Record<string, unknown> | null {
  if (!raw) return null;
  const { text } = splitThinkTags(raw);
  const candidate = text || raw;

  // Try fenced ```json ... ```
  const fenced = /```(?:json)?\s*([\s\S]*?)```/i.exec(candidate);
  if (fenced?.[1]) {
    try {
      const parsed = JSON.parse(fenced[1].trim());
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // fall through
    }
  }

  // Find outer { ... }
  const firstBrace = candidate.indexOf('{');
  const lastBrace = candidate.lastIndexOf('}');
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    const sub = candidate.slice(firstBrace, lastBrace + 1);
    try {
      const parsed = JSON.parse(sub);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // fall through
    }
  }
  return null;
}

export class AiServiceMain {
  private readonly prefs: SharedPreferencesStore;
  private readonly keyring: KeyringStore;

  constructor(prefs: SharedPreferencesStore, keyring: KeyringStore) {
    this.prefs = prefs;
    this.keyring = keyring;
  }

  getProvidersState(): {
    providers: LlmProviderConfig[];
    activeId: string | null;
    serperKeyConfigured: boolean;
    webSearchEnabled: boolean;
  } {
    const { providers, activeId } = this.prefs.loadAiProviders();
    const enriched = providers.map((p) => ({
      ...p,
      capabilities: p.capabilities ?? defaultCapabilitiesFor(p.kind),
      contextTokens: p.contextTokens ?? defaultCapabilitiesFor(p.kind).contextTokens,
      effort: p.effort ?? 'low',
      hasApiKey: Boolean(this.keyring.get(`mario.ai.key.${p.id}`)),
    }));
    const serperKey = this.keyring.get('mario.ai.serperKey');
    const webSearchEnabled = Boolean(
      this.prefs.get('mario.ai.webSearchEnabled', Boolean(serperKey)),
    );
    return {
      providers: enriched,
      activeId: activeId ?? enriched[0]?.id ?? null,
      serperKeyConfigured: Boolean(serperKey),
      webSearchEnabled,
    };
  }

  saveProvider(
    config: LlmProviderConfig,
    apiKey?: string | null,
    setActive = true,
  ): ReturnType<AiServiceMain['getProvidersState']> {
    const { providers, activeId } = this.prefs.loadAiProviders();
    const normalizedUrl =
      config.kind === 'anthropic'
        ? config.baseUrl.trim() || 'https://api.anthropic.com/v1'
        : normalizeOpenAiBaseUrl(config.baseUrl);

    if (apiKey !== undefined) {
      this.keyring.set(`mario.ai.key.${config.id}`, apiKey);
    }
    const hasKey = Boolean(this.keyring.get(`mario.ai.key.${config.id}`));
    const updatedConfig: LlmProviderConfig = {
      ...config,
      baseUrl: normalizedUrl,
      hasApiKey: hasKey,
      capabilities: config.capabilities ?? defaultCapabilitiesFor(config.kind),
    };

    const idx = providers.findIndex((p) => p.id === config.id);
    const next =
      idx >= 0
        ? providers.map((p, i) => (i === idx ? updatedConfig : p))
        : [...providers, updatedConfig];

    const nextActive = setActive ? config.id : activeId ?? config.id;
    this.prefs.saveAiProviders(next, nextActive);
    return this.getProvidersState();
  }

  deleteProvider(id: string): ReturnType<AiServiceMain['getProvidersState']> {
    const { providers, activeId } = this.prefs.loadAiProviders();
    this.keyring.set(`mario.ai.key.${id}`, null);
    const next = providers.filter((p) => p.id !== id);
    const nextActive = activeId === id ? next[0]?.id ?? null : activeId;
    this.prefs.saveAiProviders(next, nextActive);
    return this.getProvidersState();
  }

  setActiveProvider(id: string): ReturnType<AiServiceMain['getProvidersState']> {
    const { providers } = this.prefs.loadAiProviders();
    this.prefs.saveAiProviders(providers, id);
    return this.getProvidersState();
  }

  setProviderModel(
    id: string,
    model: string,
    effort?: LlmEffort,
  ): ReturnType<AiServiceMain['getProvidersState']> {
    const { providers, activeId } = this.prefs.loadAiProviders();
    const next = providers.map((p) =>
      p.id === id
        ? { ...p, model, ...(effort !== undefined ? { effort } : {}) }
        : p,
    );
    this.prefs.saveAiProviders(next, activeId);
    return this.getProvidersState();
  }

  setSerperConfig(apiKey: string | null, enabled: boolean): void {
    if (apiKey !== null) {
      this.keyring.set('mario.ai.serperKey', apiKey.trim() || null);
    }
    this.prefs.set('mario.ai.webSearchEnabled', enabled);
  }

  async listModelsForProvider(config: {
    id?: string;
    kind: LlmProviderKind;
    baseUrl: string;
    apiKey?: string;
  }): Promise<string[]> {
    if (config.kind === 'anthropic') {
      return [
        'claude-opus-4-6',
        'claude-sonnet-4-6',
        'claude-haiku-4-5',
        'claude-3-7-sonnet-latest',
      ];
    }
    const base = normalizeOpenAiBaseUrl(config.baseUrl);
    const key =
      config.apiKey ||
      (config.id ? this.keyring.get(`mario.ai.key.${config.id}`) : null) ||
      '';

    const headers: Record<string, string> = {};
    if (key) headers.Authorization = `Bearer ${key}`;

    try {
      const resp = await fetch(`${base}/models`, {
        headers,
        signal: AbortSignal.timeout(4000),
      });
      if (resp.ok) {
        const data = (await resp.json()) as {
          data?: Array<{ id?: string }>;
          models?: Array<{ name?: string; id?: string }>;
        };
        if (Array.isArray(data.data)) {
          return data.data.map((m) => String(m.id ?? '')).filter(Boolean);
        }
        if (Array.isArray(data.models)) {
          return data.models
            .map((m) => String(m.id ?? m.name ?? ''))
            .filter(Boolean);
        }
      }
    } catch {
      // Fallback for Ollama /api/tags
    }

    if (config.kind === 'ollama' || base.includes('11434')) {
      try {
        const root = base.replace(/\/v1$/, '');
        const resp = await fetch(`${root}/api/tags`, {
          signal: AbortSignal.timeout(3000),
        });
        if (resp.ok) {
          const data = (await resp.json()) as {
            models?: Array<{ name?: string }>;
          };
          return (data.models ?? []).map((m) => String(m.name ?? '')).filter(Boolean);
        }
      } catch {
        // ignore
      }
    }
    return [];
  }

  async discoverLocalEndpoints(): Promise<DiscoveredEndpoint[]> {
    const probes: Array<{
      port: number;
      serverName: string;
      kind: LlmProviderKind;
    }> = [
      { port: 11434, serverName: 'Ollama', kind: 'ollama' },
      { port: 8080, serverName: 'llama.cpp', kind: 'openAiCompatible' },
      { port: 8081, serverName: 'llama.cpp (8081)', kind: 'openAiCompatible' },
      { port: 1234, serverName: 'LM Studio', kind: 'openAiCompatible' },
      { port: 8000, serverName: 'vLLM', kind: 'openAiCompatible' },
      { port: 1337, serverName: 'Jan', kind: 'openAiCompatible' },
    ];

    const discovered: DiscoveredEndpoint[] = [];
    await Promise.all(
      probes.map(async (p) => {
        const baseUrl = `http://127.0.0.1:${p.port}/v1`;
        try {
          if (p.port === 11434) {
            const resp = await fetch(`http://127.0.0.1:11434/api/tags`, {
              signal: AbortSignal.timeout(1500),
            });
            if (resp.ok) {
              const data = (await resp.json()) as {
                models?: Array<{ name: string; size?: number }>;
              };
              const models: DiscoveredModel[] = (data.models ?? []).map((m) => ({
                name: m.name,
                sizeLabel: m.size
                  ? `${(m.size / (1024 * 1024 * 1024)).toFixed(1)} GB`
                  : '',
              }));
              if (models.length > 0) {
                discovered.push({
                  serverName: p.serverName,
                  kind: p.kind,
                  baseUrl,
                  models,
                });
                return;
              }
            }
          }

          const resp = await fetch(`${baseUrl}/models`, {
            signal: AbortSignal.timeout(1500),
          });
          if (resp.ok) {
            const data = (await resp.json()) as {
              data?: Array<{ id: string }>;
            };
            const models: DiscoveredModel[] = (data.data ?? []).map((m) => ({
              name: m.id,
              sizeLabel: '',
            }));
            if (models.length > 0) {
              discovered.push({
                serverName: p.serverName,
                kind: p.kind,
                baseUrl,
                models,
              });
            }
          }
        } catch {
          // port closed
        }
      }),
    );
    return discovered;
  }

  private getActiveProvider(): {
    config: LlmProviderConfig;
    apiKey: string | null;
  } {
    const { providers, activeId } = this.getProvidersState();
    const active =
      providers.find((p) => p.id === activeId) ?? providers[0] ?? null;
    if (!active) {
      throw new Error('No AI model configured. Set up a model in Settings → AI.');
    }
    const apiKey = this.keyring.get(`mario.ai.key.${active.id}`);
    return { config: active, apiKey };
  }

  async chatCompletion(opts: {
    systemPrompt: string;
    userPrompt: string;
    temperature?: number;
    effort?: LlmEffort;
    jsonSchema?: { name: string; schema: Record<string, unknown> };
    disableThinking?: boolean;
  }): Promise<{ text: string; reasoning: string }> {
    const { config, apiKey } = this.getActiveProvider();
    if (config.kind === 'anthropic') {
      return this.callAnthropic(config, apiKey, opts);
    }
    return this.callOpenAiCompatible(config, apiKey, opts);
  }

  private async callAnthropic(
    config: LlmProviderConfig,
    apiKey: string | null,
    opts: {
      systemPrompt: string;
      userPrompt: string;
      temperature?: number;
      effort?: LlmEffort;
      jsonSchema?: { name: string; schema: Record<string, unknown> };
    },
  ): Promise<{ text: string; reasoning: string }> {
    if (!apiKey) {
      throw new Error('Anthropic API key is missing. Add it in Settings → AI.');
    }
    const base = config.baseUrl.replace(/\/+$/, '');
    const sys = opts.jsonSchema
      ? `${opts.systemPrompt}\n\nRespond ONLY with a valid JSON object matching this schema:\n${JSON.stringify(opts.jsonSchema.schema)}`
      : opts.systemPrompt;

    const resp = await fetch(`${base}/messages`, {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: config.model || 'claude-sonnet-4-6',
        max_tokens: 4096,
        system: sys,
        messages: [{ role: 'user', content: opts.userPrompt }],
      }),
    });

    if (!resp.ok) {
      const errText = await resp.text();
      throw new Error(`Anthropic error (${resp.status}): ${errText}`);
    }

    const data = (await resp.json()) as {
      content?: Array<{ type: string; text?: string; thinking?: string }>;
    };
    let text = '';
    let reasoning = '';
    for (const block of data.content ?? []) {
      if (block.type === 'text' && block.text) text += block.text;
      if (block.type === 'thinking' && block.thinking) reasoning += block.thinking;
    }
    return { text: text.trim(), reasoning: reasoning.trim() };
  }

  private async callOpenAiCompatible(
    config: LlmProviderConfig,
    apiKey: string | null,
    opts: {
      systemPrompt: string;
      userPrompt: string;
      temperature?: number;
      effort?: LlmEffort;
      jsonSchema?: { name: string; schema: Record<string, unknown> };
      disableThinking?: boolean;
    },
  ): Promise<{ text: string; reasoning: string }> {
    const base = normalizeOpenAiBaseUrl(config.baseUrl);
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (apiKey) headers.Authorization = `Bearer ${apiKey}`;

    const sys = opts.jsonSchema
      ? `${opts.systemPrompt}\n\nReturn ONLY valid JSON conforming to the schema:\n${JSON.stringify(opts.jsonSchema.schema)}`
      : opts.systemPrompt;

    const buildBody = (
      schemaMode: 'nested' | 'flat' | 'json_object' | 'none',
      includeThinkingParams: boolean,
    ) => {
      const payload: Record<string, unknown> = {
        model: config.model,
        messages: [
          { role: 'system', content: sys },
          { role: 'user', content: opts.userPrompt },
        ],
        temperature: opts.temperature ?? 0.3,
      };

      if (opts.jsonSchema) {
        if (schemaMode === 'nested') {
          payload.response_format = {
            type: 'json_schema',
            json_schema: {
              name: opts.jsonSchema.name,
              strict: true,
              schema: opts.jsonSchema.schema,
            },
          };
        } else if (schemaMode === 'flat') {
          payload.response_format = {
            type: 'json_schema',
            schema: opts.jsonSchema.schema,
          };
        } else if (schemaMode === 'json_object') {
          payload.response_format = { type: 'json_object' };
        }
      }

      if (includeThinkingParams) {
        const eff = opts.disableThinking ? 'off' : (opts.effort ?? config.effort ?? 'low');
        if (config.kind === 'ollama' || config.kind === 'openAiCompatible') {
          payload.think = eff !== 'off';
          payload.chat_template_kwargs = { enable_thinking: eff !== 'off' };
        }
      }

      return payload;
    };

    const modes: Array<'nested' | 'flat' | 'json_object' | 'none'> = opts.jsonSchema
      ? config.capabilities?.strictJsonSchema
        ? ['nested', 'flat', 'json_object', 'none']
        : ['flat', 'json_object', 'none']
      : ['none'];

    let lastError = '';
    for (const mode of modes) {
      for (const withThinking of [true, false]) {
        const resp = await fetch(`${base}/chat/completions`, {
          method: 'POST',
          headers,
          body: JSON.stringify(buildBody(mode, withThinking)),
        });

        if (resp.ok) {
          const data = (await resp.json()) as {
            choices?: Array<{
              message?: {
                content?: string;
                reasoning_content?: string;
                reasoning?: string;
              };
            }>;
          };
          const msg = data.choices?.[0]?.message;
          const rawContent = String(msg?.content ?? '');
          const split = splitThinkTags(rawContent);
          const reasoning =
            String(msg?.reasoning_content ?? msg?.reasoning ?? '') ||
            split.reasoning;
          return { text: split.text, reasoning };
        }

        lastError = `HTTP ${resp.status}: ${await resp.text()}`;
        if (resp.status !== 400 && resp.status !== 422 && resp.status !== 501) {
          throw new Error(lastError);
        }
      }
    }

    throw new Error(`LLM request failed: ${lastError}`);
  }

  /**
   * Structured JSON completion with automatic thinking-budget fallback and 1 repair retry.
   */
  async completeStructured(opts: {
    schemaName: string;
    schema: Record<string, unknown>;
    systemPrompt: string;
    userPrompt: string;
    temperature?: number;
  }): Promise<Record<string, unknown>> {
    let res = await this.chatCompletion({
      systemPrompt: opts.systemPrompt,
      userPrompt: opts.userPrompt,
      temperature: opts.temperature ?? 0.2,
      jsonSchema: { name: opts.schemaName, schema: opts.schema },
    });

    let parsed = extractJsonObject(res.text) ?? extractJsonObject(res.reasoning);
    if (parsed) return parsed;

    // Thinking safety net: if answer is empty and reasoning is non-empty, retry with thinking off
    if (!res.text && res.reasoning) {
      res = await this.chatCompletion({
        systemPrompt: opts.systemPrompt,
        userPrompt: opts.userPrompt,
        temperature: opts.temperature ?? 0.2,
        jsonSchema: { name: opts.schemaName, schema: opts.schema },
        disableThinking: true,
      });
      parsed = extractJsonObject(res.text) ?? extractJsonObject(res.reasoning);
      if (parsed) return parsed;
    }

    // 1 repair attempt at temperature 0
    const repairRes = await this.chatCompletion({
      systemPrompt: `Convert the following text into a valid JSON object matching this schema:\n${JSON.stringify(opts.schema)}`,
      userPrompt: res.text || res.reasoning || opts.userPrompt,
      temperature: 0,
      jsonSchema: { name: opts.schemaName, schema: opts.schema },
      disableThinking: true,
    });
    parsed =
      extractJsonObject(repairRes.text) ?? extractJsonObject(repairRes.reasoning);
    if (parsed) return parsed;

    throw new Error('Model did not return valid structured JSON.');
  }

  async webSearch(
    query: string,
  ): Promise<Array<{ title: string; link: string; snippet: string }>> {
    const q = query.trim();
    if (!q) return [];
    const serperKey = this.keyring.get('mario.ai.serperKey');

    if (serperKey) {
      const resp = await fetch('https://google.serper.dev/search', {
        method: 'POST',
        headers: {
          'X-API-KEY': serperKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ q, num: 5 }),
      });
      if (resp.ok) {
        const data = (await resp.json()) as {
          organic?: Array<{ title?: string; link?: string; snippet?: string }>;
        };
        const today = new Date();
        const dayStr = `${today.getFullYear()}-${today.getMonth() + 1}-${today.getDate()}`;
        const prevDay = this.prefs.get<string>('mario.ai.webSearchDay', '');
        const count =
          prevDay === dayStr
            ? Number(this.prefs.get<number>('mario.ai.webSearchCount', 0)) + 1
            : 1;
        this.prefs.set('mario.ai.webSearchDay', dayStr);
        this.prefs.set('mario.ai.webSearchCount', count);

        return (data.organic ?? []).slice(0, 5).map((r) => ({
          title: String(r.title ?? ''),
          link: String(r.link ?? ''),
          snippet: String(r.snippet ?? ''),
        }));
      }
    }

    // Fallback: Wikipedia OpenSearch API (keyless, fast, reliable)
    try {
      const url = `https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=${encodeURIComponent(q)}&utf8=&format=json&srlimit=5`;
      const resp = await fetch(url, { signal: AbortSignal.timeout(4000) });
      if (resp.ok) {
        const data = (await resp.json()) as {
          query?: {
            search?: Array<{ title: string; snippet: string }>;
          };
        };
        return (data.query?.search ?? []).map((s) => ({
          title: s.title,
          link: `https://en.wikipedia.org/wiki/${encodeURIComponent(s.title.replace(/ /g, '_'))}`,
          snippet: s.snippet.replace(/<[^>]+>/g, ''),
        }));
      }
    } catch {
      // ignore
    }
    return [];
  }
}
