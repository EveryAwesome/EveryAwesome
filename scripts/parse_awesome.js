#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const MarkdownIt = require('markdown-it');

const EXCLUDE_HEADINGS = /^(table of contents|contents|toc|contributing|contributors?|license|about|acknowledg(e?)ments|related( awesome lists)?|index|footnotes|maintainers?|legend|see also|further reading|credits|thanks)$/i;

const MAX_TAG_WORDS = 3;
const MAX_TAG_LEN = 25;

function plainText(children) {
  let out = '';
  for (const c of children) {
    if (c.type === 'text' || c.type === 'code_inline') {
      out += c.content;
    } else if (c.type === 'softbreak' || c.type === 'hardbreak') {
      out += ' ';
    } else if (c.children) {
      out += plainText(c.children);
    }
  }
  return out;
}

function extractEntry(inlineToken) {
  const children = inlineToken.children || [];

  let linkOpenIdx = -1;
  for (let i = 0; i < children.length; i++) {
    if (children[i].type === 'link_open') {
      linkOpenIdx = i;
      break;
    }
  }
  if (linkOpenIdx === -1) return null;

  const href = children[linkOpenIdx].attrGet('href') || '';
  if (!href || href.startsWith('#') || href.startsWith('mailto:')) return null;

  let linkCloseIdx = -1;
  for (let i = linkOpenIdx + 1; i < children.length; i++) {
    if (children[i].type === 'link_close') {
      linkCloseIdx = i;
      break;
    }
  }
  if (linkCloseIdx === -1) return null;

  const name = plainText(children.slice(linkOpenIdx + 1, linkCloseIdx)).trim();
  if (!name) return null;

  let desc = plainText(children.slice(linkCloseIdx + 1)).trim();
  // Strip leading separators: ASCII -, en/em dash, horizontal bar, box-drawings,
  // bullet, middle dot, colon. Allow optional leading whitespace.
  desc = desc.replace(/^[\s\-—–―─•·:]+/, '').trim();

  const tags = [];
  desc = desc.replace(/\(([^)]{1,40})\)/g, (match, content) => {
    const norm = content.trim().toLowerCase();
    const words = norm.split(/\s+/);
    const allDigits = /^[0-9]+$/.test(norm.replace(/[\s\-]/g, ''));
    if (
      !allDigits &&
      norm.length <= MAX_TAG_LEN &&
      words.length <= MAX_TAG_WORDS &&
      /^[a-z0-9][a-z0-9 \-+./]*$/.test(norm)
    ) {
      tags.push(norm.replace(/\s+/g, '-'));
      return '';
    }
    return match;
  });

  desc = desc.replace(/\s{2,}/g, ' ').replace(/\s+([.,;:])/g, '$1').trim();

  return { name, url: href, description: desc, tags };
}

function parseList(listMeta, src) {
  const md = new MarkdownIt({ html: false, linkify: false });
  const tokens = md.parse(src, {});
  const entries = [];

  let category = null;
  let subcategory = null;
  let skipSection = false;

  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];

    if (t.type === 'heading_open') {
      const inline = tokens[i + 1];
      const title = (inline?.content || '').trim();
      if (t.tag === 'h2') {
        category = title;
        subcategory = null;
        skipSection = EXCLUDE_HEADINGS.test(title);
      } else if (t.tag === 'h3') {
        subcategory = title;
      }
      continue;
    }

    if (t.type === 'list_item_open' && !skipSection && category) {
      let depth = 1;
      for (let j = i + 1; j < tokens.length && depth > 0; j++) {
        const tt = tokens[j];
        if (tt.type === 'list_item_open') {
          depth++;
        } else if (tt.type === 'list_item_close') {
          depth--;
        } else if (tt.type === 'inline' && depth === 1) {
          const entry = extractEntry(tt);
          if (entry) {
            entries.push({
              list: listMeta.id,
              category,
              subcategory,
              ...entry,
            });
          }
          break;
        }
      }
    }
  }

  return entries;
}

function main() {
  const [, , listsJsonPath, rawDir, outPath] = process.argv;
  if (!listsJsonPath || !rawDir || !outPath) {
    console.error('Usage: node parse_awesome.js <lists.json> <rawDir> <out.json>');
    process.exit(1);
  }

  const lists = JSON.parse(fs.readFileSync(listsJsonPath, 'utf8'));
  const allEntries = [];
  const presentLists = [];

  for (const meta of lists) {
    const mdPath = path.join(rawDir, `${meta.id}.md`);
    if (!fs.existsSync(mdPath)) {
      console.warn(`! ${meta.id}: ${mdPath} missing — skipping`);
      continue;
    }
    const src = fs.readFileSync(mdPath, 'utf8');
    const entries = parseList(meta, src);
    console.log(`  ${meta.id.padEnd(20)} ${String(entries.length).padStart(5)} entries`);
    allEntries.push(...entries);
    presentLists.push({ id: meta.id, name: meta.name, repo: meta.repo });
  }

  const output = {
    lists: presentLists,
    entries: allEntries,
  };

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(output));
  console.log(`\nWrote ${allEntries.length} entries across ${presentLists.length} lists → ${outPath}`);
}

if (require.main === module) {
  main();
}

module.exports = { parseList, extractEntry, plainText };
