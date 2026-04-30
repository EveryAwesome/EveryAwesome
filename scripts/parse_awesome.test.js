'use strict';

const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const { parseList } = require('./parse_awesome.js');

const meta = { id: 'test', name: 'Test', repo: 'owner/test' };

describe('parseList — link styles', () => {
  test('extracts inline-style links', () => {
    const md = `# T
## Tools
- [Foo](https://foo.com) - A foo tool.
- [Bar](https://bar.com) - A bar tool.
`;
    const entries = parseList(meta, md);
    assert.equal(entries.length, 2);
    assert.deepEqual(entries[0], {
      list: 'test',
      category: 'Tools',
      subcategory: null,
      name: 'Foo',
      url: 'https://foo.com',
      description: 'A foo tool.',
      tags: [],
    });
  });

  test('resolves reference-style links', () => {
    const md = `# T
## Tools
- [Foo] - A foo tool.
- [Bar] - A bar tool.

[Foo]: https://foo.com
[Bar]: https://bar.com
`;
    const entries = parseList(meta, md);
    assert.equal(entries.length, 2);
    assert.equal(entries[0].url, 'https://foo.com');
    assert.equal(entries[1].url, 'https://bar.com');
  });

  test('skips entries with no link', () => {
    const md = `# T
## Tools
- Just plain text, no link
- [Real](https://real.com) - has a link
`;
    const entries = parseList(meta, md);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].name, 'Real');
  });

  test('skips in-page anchor and mailto links', () => {
    const md = `# T
## Tools
- [Anchor](#section) - in-page link
- [Email](mailto:hi@example.com) - mailto
- [Real](https://real.com) - keep
`;
    const entries = parseList(meta, md);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].name, 'Real');
  });
});

describe('parseList — heading hierarchy', () => {
  test('tracks H2 category', () => {
    const md = `# T
## Cat A
- [A](https://a.com)
## Cat B
- [B](https://b.com)
`;
    const entries = parseList(meta, md);
    assert.equal(entries[0].category, 'Cat A');
    assert.equal(entries[1].category, 'Cat B');
  });

  test('tracks H3 subcategory and resets on new H2', () => {
    const md = `# T
## Software
### DAWs
- [A](https://a.com)
### Synths
- [B](https://b.com)
## Hardware
- [C](https://c.com)
`;
    const entries = parseList(meta, md);
    assert.equal(entries[0].subcategory, 'DAWs');
    assert.equal(entries[1].subcategory, 'Synths');
    assert.equal(entries[2].category, 'Hardware');
    assert.equal(entries[2].subcategory, null);
  });

  test('skips entries before any H2', () => {
    const md = `# T
- [Orphan](https://o.com)
## Real
- [Kept](https://k.com)
`;
    const entries = parseList(meta, md);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].name, 'Kept');
  });
});

describe('parseList — excluded sections', () => {
  test('skips Contributing/License/Related/etc.', () => {
    const md = `# T
## Tools
- [Real](https://real.com)
## Contributing
- [Skipped](https://skip.com)
## License
- [Skipped2](https://skip2.com)
## Related
- [Skipped3](https://skip3.com)
## Acknowledgements
- [Skipped4](https://skip4.com)
`;
    const entries = parseList(meta, md);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].name, 'Real');
  });
});

describe('parseList — descriptions', () => {
  test('strips leading separators (-, em/en dash, box-drawing)', () => {
    const md = `# T
## Tools
- [A](https://a.com) - dash
- [B](https://b.com) — em dash
- [C](https://c.com) – en dash
- [D](https://d.com) ─ box drawing
- [E](https://e.com) : colon
- [F](https://f.com) • bullet
`;
    const entries = parseList(meta, md);
    assert.equal(entries[0].description, 'dash');
    assert.equal(entries[1].description, 'em dash');
    assert.equal(entries[2].description, 'en dash');
    assert.equal(entries[3].description, 'box drawing');
    assert.equal(entries[4].description, 'colon');
    assert.equal(entries[5].description, 'bullet');
  });

  test('handles missing description', () => {
    const md = `# T
## Tools
- [Bare](https://bare.com)
`;
    const entries = parseList(meta, md);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].description, '');
  });
});

describe('parseList — tags', () => {
  test('extracts short parenthetical tags', () => {
    const md = `# T
## Tools
- [A](https://a.com) - desc (open source)
- [B](https://b.com) - desc (commercial) (linux)
`;
    const entries = parseList(meta, md);
    assert.deepEqual(entries[0].tags, ['open-source']);
    assert.deepEqual(entries[1].tags, ['commercial', 'linux']);
    assert.equal(entries[0].description, 'desc');
    assert.equal(entries[1].description, 'desc');
  });

  test('rejects all-numeric "tags" (years)', () => {
    const md = `# T
## Tools
- [A](https://a.com) - posted (2026)
`;
    const entries = parseList(meta, md);
    assert.deepEqual(entries[0].tags, []);
    assert.match(entries[0].description, /\(2026\)/);
  });

  test('rejects long parenthetical asides', () => {
    const md = `# T
## Tools
- [A](https://a.com) - desc (this is a long aside that should not be a tag)
`;
    const entries = parseList(meta, md);
    assert.deepEqual(entries[0].tags, []);
  });
});

describe('parseList — nested bullets', () => {
  test('emits nested list items with links, skips text-only sub-bullets', () => {
    // Permissive on purpose: most awesome lists don't use deep nesting,
    // and when they do, a nested entry with a link is usually a real entry
    // (e.g. a related project). Plain-text sub-bullets are correctly skipped
    // because extractEntry returns null when there's no link.
    const md = `# T
## Tools
- [A](https://a.com) - top-level
  - text-only sub-bullet — skipped (no link)
  - [Nested link](https://nested.com) — kept
- [B](https://b.com) - another top-level
`;
    const entries = parseList(meta, md);
    assert.equal(entries.length, 3);
    assert.deepEqual(entries.map((e) => e.name), ['A', 'Nested link', 'B']);
  });
});
