import { describe, expect, it } from 'vitest';
import {
  buildPageWebDocument,
  isFullHtmlDocument,
  looksLikeHtmlSource,
  prepareWebDocument,
} from '../editor/web-page';

describe('Web pages from notes', () => {
  it('recognises pasted HTML source but not Markdown or inline tags', () => {
    expect(looksLikeHtmlSource('<!DOCTYPE html>\n<html lang="en"><head></head><body></body></html>')).toBe(true);
    expect(looksLikeHtmlSource('<!-- generated -->\n<html><body>x</body></html>')).toBe(true);
    expect(looksLikeHtmlSource('<div class="card">\n  <h2>Title</h2>\n  <p>Some text here.</p>\n</div>')).toBe(true);
    expect(looksLikeHtmlSource('# Heading\n\n- a list with <b>bold</b>')).toBe(false);
    expect(looksLikeHtmlSource('<b>bold</b> and <i>italic</i> words in a sentence')).toBe(false);
    expect(isFullHtmlDocument('<div>fragment</div>')).toBe(false);
  });

  it('puts its scripts in <head>, not in a <header>', () => {
    const doc = prepareWebDocument({
      html: ['<!doctype html><html><head><title>t</title></head><body><header>H</header></body></html>'],
    });
    const head = doc.slice(doc.indexOf('<head>'), doc.indexOf('</head>'));
    expect(head).toContain('localStorage');
    expect(head).toContain("location.hash");
    expect(doc).toContain('<header>H</header>');
    expect(doc.indexOf('<header>')).toBeGreaterThan(doc.indexOf('</head>'));
  });

  it('wraps a fragment without a head and leaves a <header> alone', () => {
    const doc = prepareWebDocument({ html: ['<header>Top</header><p>x</p>'] });
    expect(doc.startsWith('<!doctype html>')).toBe(true);
    expect(doc).toContain('<body><header>Top</header><p>x</p></body>');
  });

  it('combines HTML, CSS and JS code blocks, CodePen-style', () => {
    const doc = buildPageWebDocument({
      type: 'page',
      children: [
        { type: 'code', data: { language: 'html', code: '<h1 id="t">Hi</h1>' } },
        { type: 'code', data: { language: 'css', code: 'h1{color:red}' } },
        { type: 'code', data: { language: 'javascript', code: 'document.title = "</script>"' } },
        { type: 'paragraph', data: { delta: [{ insert: 'notes' }] } },
      ],
    });
    expect(doc).toContain('<style>h1{color:red}</style>');
    expect(doc).toContain('<h1 id="t">Hi</h1>');
    expect(doc).toContain('document.title = "<\\/script>"');
    expect(buildPageWebDocument({ type: 'page', children: [{ type: 'paragraph', data: {} }] })).toBeNull();
  });
});
