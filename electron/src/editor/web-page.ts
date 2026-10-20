import type { AppFlowyDocument, AppFlowyNode } from '../shared/types';
import { deltaToPlainText, flattenNodes } from '../shared/document-codec';

/**
 * Turning a page's HTML into a real webpage for the preview and for HTML
 * blocks. The page runs in an iframe sandboxed WITHOUT allow-same-origin (with
 * it, the page could reach the app's `window.mario` bridge), so it gets an
 * opaque origin where `localStorage` throws; a small in-memory stand-in keeps
 * pages that use it working.
 */

/** Sandbox for previewed pages: scripts, forms, dialogs, pop-ups (they open in the browser). */
export const WEB_SANDBOX = 'allow-scripts allow-forms allow-popups allow-modals allow-pointer-lock allow-downloads';

const STORAGE_SHIM = `<script>(function(){function mem(){var d=Object.create(null);return{getItem:function(k){k=String(k);return k in d?d[k]:null},setItem:function(k,v){d[String(k)]=String(v)},removeItem:function(k){delete d[String(k)]},clear:function(){d=Object.create(null)},key:function(i){var k=Object.keys(d);return i<k.length?k[i]:null},get length(){return Object.keys(d).length}}}['localStorage','sessionStorage'].forEach(function(n){try{window[n].length}catch(e){try{Object.defineProperty(window,n,{value:mem(),configurable:true})}catch(_){}}})})();</script>`;

const HEIGHT_REPORTER = `<script>(function(){var last=0;function post(){var h=Math.ceil(document.documentElement.getBoundingClientRect().height);if(h!==last){last=h;parent.postMessage({marioFrameHeight:h},'*')}}var ro=new ResizeObserver(post);ro.observe(document.documentElement);document.addEventListener('DOMContentLoaded',function(){if(document.body)ro.observe(document.body);post()});addEventListener('load',post)})();</script>`;

/**
 * Links. A srcdoc page takes the app's address as its base, so `href="#part"`
 * would load Mario itself into the frame: in-page links go to the fragment of
 * the page instead (scrolling, and firing hashchange for hash routers), and web
 * links open in the browser.
 */
const LINK_HANDLER = `<script>document.addEventListener('click',function(e){if(e.defaultPrevented||e.button!==0)return;var a=e.target&&e.target.closest?e.target.closest('a[href]'):null;if(!a)return;var h=a.getAttribute('href')||'';if(h.charAt(0)==='#'){e.preventDefault();try{location.hash=h}catch(_){var t=document.getElementById(decodeURIComponent(h.slice(1)));if(t)t.scrollIntoView()}}else if(/^(https?:|mailto:)/i.test(a.href)){e.preventDefault();window.open(a.href,'_blank')}});</script>`;

export const isFullHtmlDocument = (html: string) => /^\s*(<!--[\s\S]*?-->\s*)*(<!doctype html|<html[\s>])/i.test(html);
const isFullDocument = (html: string) => /<!doctype|<html[\s>]/i.test(html);

const BLOCK_TAGS =
  'html|head|body|main|section|article|header|footer|nav|aside|div|table|svg|canvas|form|style|script|iframe|figure|ul|ol|details|template|link|meta';

/** Text that is HTML source (copied from an editor or an AI chat), not Markdown. */
export function looksLikeHtmlSource(text: string): boolean {
  if (isFullHtmlDocument(text)) return true;
  const t = text.trim();
  if (t.length < 40) return false;
  return (
    new RegExp(`^<(${BLOCK_TAGS})[\\s>/]`, 'i').test(t) &&
    /<\/[a-z][a-z0-9-]*>\s*$|\/>\s*$/i.test(t) &&
    (t.match(/<\/?[a-z][^>]*>/gi)?.length ?? 0) >= 4
  );
}

function injectIntoHead(doc: string, snippet: string): string {
  // `<head` alone would also match `<header>`.
  if (/<head(\s[^>]*)?>/i.test(doc)) return doc.replace(/<head(\s[^>]*)?>/i, (m) => m + snippet);
  if (/<html[^>]*>/i.test(doc)) return doc.replace(/<html[^>]*>/i, (m) => `${m}<head>${snippet}</head>`);
  return snippet + doc;
}

function injectAtBodyEnd(doc: string, snippet: string): string {
  const i = doc.search(/<\/body>(?![\s\S]*<\/body>)/i);
  return i >= 0 ? doc.slice(0, i) + snippet + doc.slice(i) : doc + snippet;
}

const scriptTag = (js: string) => `<script>${js.replace(/<\/script/gi, '<\\/script')}</script>`;
const styleTag = (css: string) => `<style>${css.replace(/<\/style/gi, '<\\/style')}</style>`;

export interface WebPageParts {
  html: string[];
  css?: string[];
  js?: string[];
}

/** One HTML document from HTML (a fragment or a whole page), plus CSS and JavaScript. */
export function prepareWebDocument(parts: WebPageParts, opts: { reportHeight?: boolean } = {}): string {
  const htmlParts = parts.html.filter((h) => h.trim());
  const full = htmlParts.find(isFullDocument);
  // A whole page wins; fragments are joined into one body.
  let doc =
    full ??
    `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body>${htmlParts.join('\n')}</body></html>`;
  if (full) {
    const extra = htmlParts.filter((h) => h !== full);
    if (extra.length) doc = injectAtBodyEnd(doc, extra.join('\n'));
  }
  doc = injectIntoHead(doc, STORAGE_SHIM + LINK_HANDLER + (opts.reportHeight ? HEIGHT_REPORTER : ''));
  for (const css of parts.css ?? []) if (css.trim()) doc = injectIntoHead(doc, styleTag(css));
  for (const js of parts.js ?? []) if (js.trim()) doc = injectAtBodyEnd(doc, scriptTag(js));
  return doc;
}

const HTML_LANGS = new Set(['html', 'htm', 'xhtml', 'svg']);
const CSS_LANGS = new Set(['css']);
const JS_LANGS = new Set(['javascript', 'js', 'jsx', 'mjs']);

function codeOf(node: AppFlowyNode): string {
  return typeof node.data?.code === 'string' ? node.data.code : deltaToPlainText(node.data?.delta);
}

function partsOf(nodes: AppFlowyNode[]): WebPageParts {
  const parts: Required<WebPageParts> = { html: [], css: [], js: [] };
  for (const n of nodes) {
    if (n.type === 'html' || n.type === 'html_preview') {
      parts.html.push(String(n.data?.html ?? ''));
    } else if (n.type === 'code') {
      const lang = String(n.data?.language ?? '').toLowerCase();
      if (HTML_LANGS.has(lang)) parts.html.push(codeOf(n));
      else if (CSS_LANGS.has(lang)) parts.css.push(codeOf(n));
      else if (JS_LANGS.has(lang)) parts.js.push(codeOf(n));
    }
  }
  return parts;
}

/**
 * The page as a webpage, CodePen-style: its HTML code blocks and HTML blocks,
 * with its CSS and JavaScript code blocks applied. Null when it has none.
 */
export function buildPageWebDocument(doc: AppFlowyDocument): string | null {
  const parts = partsOf(flattenNodes(doc?.children ?? []));
  if (parts.html.length === 0) return null;
  return prepareWebDocument(parts);
}

/** One block (an HTML block or an HTML code block) as a webpage. */
export function buildBlockWebDocument(doc: AppFlowyDocument, blockId: string): string | null {
  const node = flattenNodes(doc?.children ?? []).find((n) => n.id === blockId);
  if (!node) return null;
  const parts = partsOf([node]);
  if (parts.html.length === 0) return null;
  return prepareWebDocument(parts);
}

/** Ask the editor to open a block in the full-pane preview. */
export function requestBlockPreview(blockId: string): void {
  window.dispatchEvent(new CustomEvent('mario-preview-block', { detail: { blockId } }));
}
