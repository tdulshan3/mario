import hljs from 'highlight.js';
import katex from 'katex';
import { Marked, type Tokens } from 'marked';
import { matchMathAt, normalizeLatexFormula } from './document-codec';

/**
 * Markdown → HTML for everything Mario shows rendered rather than edited: AI
 * answers and the page's HTML preview. GitHub-flavoured Markdown (what VS Code's
 * preview reads), `$…$` / `$$…$$` math through KaTeX, highlighted code, and the
 * result sanitised — AI answers are untrusted text, and the renderer they land
 * in has the `window.mario` bridge.
 */

type MathOutput = 'htmlAndMathml' | 'mathml';

function renderTex(tex: string, displayMode: boolean, output: MathOutput): string {
  return katex.renderToString(normalizeLatexFormula(tex.trim()), {
    displayMode,
    throwOnError: false,
    output,
  });
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function highlightCode(code: string, lang?: string): string {
  const language = (lang ?? '').trim().split(/\s+/)[0]?.toLowerCase();
  try {
    if (language && hljs.getLanguage(language)) {
      return hljs.highlight(code, { language, ignoreIllegals: true }).value;
    }
  } catch {
    /* fall through to plain */
  }
  return escapeHtml(code);
}

function createMarked(output: MathOutput): Marked {
  const instance = new Marked({ gfm: true, breaks: false });
  instance.use({
    extensions: [
      {
        name: 'blockMath',
        level: 'block',
        start: (src: string) => src.match(/^\$\$/m)?.index,
        tokenizer(src: string) {
          const m = /^\$\$([\s\S]+?)\$\$[ \t]*(?:\n+|$)/.exec(src);
          return m ? { type: 'blockMath', raw: m[0], text: m[1] } : undefined;
        },
        renderer: (token) => `<div class="mario-math-display">${renderTex(String(token.text), true, output)}</div>\n`,
      },
      {
        name: 'inlineMath',
        level: 'inline',
        start: (src: string) => {
          const i = src.indexOf('$');
          return i < 0 ? undefined : i;
        },
        tokenizer(src: string) {
          const span = matchMathAt(src, 0);
          return span
            ? { type: 'inlineMath', raw: src.slice(0, span.end), text: span.tex, display: span.display }
            : undefined;
        },
        renderer: (token) => renderTex(String(token.text), Boolean(token.display), output),
      },
    ],
    renderer: {
      code(token: Tokens.Code) {
        const lang = (token.lang ?? '').trim().split(/\s+/)[0] ?? '';
        const cls = lang ? ` class="hljs language-${escapeHtml(lang)}"` : ' class="hljs"';
        return `<pre><code${cls}>${highlightCode(token.text, lang)}</code></pre>\n`;
      },
    },
  });
  return instance;
}

const inApp = createMarked('htmlAndMathml');
// The preview iframe has neither KaTeX's stylesheet nor its fonts: MathML only.
const standalone = createMarked('mathml');

const DROP_ELEMENTS =
  'script,style,iframe,frame,frameset,object,embed,applet,link,meta,base,form,button,textarea,select,option,noscript,template,foreignObject,animate,animateMotion,animateTransform,set';
const URL_ATTRS = new Set(['href', 'src', 'xlink:href', 'action', 'formaction', 'background', 'poster', 'cite']);

/** Strips everything that can run script or navigate from rendered HTML. */
export function sanitizeHtml(html: string): string {
  const doc = new DOMParser().parseFromString(`<!doctype html><body>${html}</body>`, 'text/html');
  doc.body.querySelectorAll(DROP_ELEMENTS).forEach((el) => el.remove());
  doc.body.querySelectorAll('input').forEach((el) => {
    if (el.getAttribute('type') === 'checkbox') el.setAttribute('disabled', '');
    else el.remove();
  });
  doc.body.querySelectorAll('*').forEach((el) => {
    for (const attr of Array.from(el.attributes)) {
      const name = attr.name.toLowerCase();
      if (name.startsWith('on') || name === 'srcdoc') {
        el.removeAttribute(attr.name);
      } else if (URL_ATTRS.has(name)) {
        const v = attr.value.replace(/[\s\u0000-\u001f]/g, '').toLowerCase();
        const safe =
          !/^[a-z][a-z0-9+.-]*:/.test(v) ||
          /^(https?|mailto|file):/.test(v) ||
          /^data:image\/(png|jpe?g|gif|webp|avif);/.test(v);
        if (!safe) el.removeAttribute(attr.name);
      }
    }
    if (el.tagName === 'A') {
      // Opens in the browser (main process window-open handler), never in Mario's window.
      el.setAttribute('target', '_blank');
      el.setAttribute('rel', 'noopener noreferrer');
    }
  });
  return doc.body.innerHTML;
}

/** Markdown → sanitised HTML for use inside the app (KaTeX CSS is loaded). */
export function renderMarkdownHtml(md: string): string {
  if (!md) return '';
  return sanitizeHtml(String(inApp.parse(md, { async: false })));
}

/** One line of Markdown (a quiz question, an option) → sanitised inline HTML, no paragraph. */
export function renderInlineMarkdownHtml(md: string): string {
  if (!md) return '';
  return sanitizeHtml(String(inApp.parseInline(md, { async: false })));
}

/** Markdown → sanitised HTML for a standalone document (math as MathML). */
export function renderMarkdownStandalone(md: string): string {
  if (!md) return '';
  return sanitizeHtml(String(standalone.parse(md, { async: false })));
}

/**
 * A complete HTML document for the preview pane, styled like VS Code's Markdown
 * preview. The iframe can't see the app's CSS variables, so the current values
 * of the kit's tokens are copied in: the preview follows Light/Dark and accent.
 */
export function buildPreviewDocument(title: string, md: string): string {
  const root = getComputedStyle(document.documentElement);
  const token = (name: string) => root.getPropertyValue(name).trim();
  const vars = [
    '--mac-label-primary',
    '--mac-label-secondary',
    '--mac-label-tertiary',
    '--mac-separator',
    '--mac-fill-tertiary',
    '--mac-fill-quaternary',
    '--mac-window-bg',
    '--mac-accent',
    '--mac-font',
    '--mac-font-mono',
    '--mac-accent-pink',
    '--mac-accent-red',
    '--mac-accent-indigo',
    '--mac-accent-purple',
    '--mac-accent-teal',
    '--mac-accent-orange',
    '--mac-accent-green',
    '--mac-accent-cyan',
  ]
    .map((n) => `${n}:${token(n)};`)
    .join('');
  const scheme = root.getPropertyValue('color-scheme').trim() || 'light dark';
  const body = renderMarkdownStandalone(md);
  return `<!doctype html><html><head><meta charset="utf-8"><style>
:root{${vars}color-scheme:${scheme}}
body{margin:0;padding:24px 28px 48px;background:var(--mac-window-bg);color:var(--mac-label-primary);font-family:var(--mac-font);font-size:14px;line-height:22px;word-wrap:break-word}
h1,h2,h3,h4,h5,h6{font-weight:600;line-height:1.25;margin:18px 0}
h1{font-size:28px;padding-bottom:.3em;border-bottom:1px solid var(--mac-separator)}
h2{font-size:21px}h3{font-size:16.5px}h4,h5,h6{font-size:14px}
body>:first-child{margin-top:0}
p{margin:0 0 16px}ul,ol{margin:0 0 16px;padding-left:2em}li>p{margin:0}
li:has(>input[type=checkbox]){list-style:none}li>input[type=checkbox]{margin:0 .4em 0 -1.4em;vertical-align:middle}
a{color:var(--mac-accent);text-decoration:none}a:hover{text-decoration:underline}
code{font-family:var(--mac-font-mono);font-size:12.5px;padding:1px 4px;border-radius:4px;background:var(--mac-fill-tertiary)}
pre{background:var(--mac-fill-quaternary);border:1px solid var(--mac-separator);border-radius:6px;padding:10px 12px;overflow:auto;margin:0 0 16px}
pre code{padding:0;background:none;font-size:12.5px;line-height:19px}
blockquote{margin:0 0 16px;padding:0 12px;border-left:3px solid var(--mac-separator);color:var(--mac-label-secondary)}
hr{border:0;border-bottom:2px solid var(--mac-separator);margin:18px 0}
table{border-collapse:collapse;margin:0 0 16px}th,td{border:1px solid var(--mac-separator);padding:4px 10px}th{font-weight:600;background:var(--mac-fill-quaternary)}
img{max-width:100%}
.mario-math-display{margin:0 0 16px;overflow-x:auto}math[display=block]{font-size:1.15em}
.hljs-keyword,.hljs-selector-tag,.hljs-literal,.hljs-name{color:var(--mac-accent-pink)}
.hljs-string,.hljs-regexp,.hljs-attr-value{color:var(--mac-accent-red)}
.hljs-number,.hljs-symbol{color:var(--mac-accent-indigo)}
.hljs-comment,.hljs-quote{color:var(--mac-label-secondary)}
.hljs-title,.hljs-section{color:var(--mac-accent-purple)}
.hljs-type,.hljs-built_in,.hljs-class{color:var(--mac-accent-cyan)}
.hljs-attr,.hljs-attribute,.hljs-property,.hljs-variable{color:var(--mac-accent-teal)}
.hljs-meta{color:var(--mac-accent-orange)}
.hljs-addition{color:var(--mac-accent-green)}.hljs-deletion{color:var(--mac-accent-red)}
</style></head><body>${title ? `<h1>${escapeHtml(title)}</h1>` : ''}${body}</body></html>`;
}
