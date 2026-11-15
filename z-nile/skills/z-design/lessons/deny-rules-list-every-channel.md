---
title: A "nothing gets through" rule lists every channel
when: design
tags: [guards, security, specs]
check: For a rule that promises nothing of a kind happens (nothing fetched, nothing written, nothing run), has the design listed every channel by which it can happen in that format (attributes, styles, scripts, handlers, meta tags, redirects, includes), refused or closed each, added a backstop for what the list misses, and given the spec's refused list one entry per channel?
---
A scan that covers the channel the author thought of passes inputs that use another. The promise in the acceptance criterion is then false.

**Why:** f0339 design review 001 F5: the explainer page's "nothing fetched" check read attribute values, CSS `url(` and `@import`, but allowed inline scripts, so `import "https://..."`, `fetch(...)`, an `onload=` handler, a `<meta http-equiv="refresh">` and CSS `image-set(` all passed. The fix refuses scripts, handlers and refresh, checks `image-set(`, and adds a backstop that refuses any `://` outside `xmlns` values.

**How to apply:** write the channel list in the Design next to the rule, give each a refused entry and a mutant, and add one backstop rule that is coarse but fails closed (with its own exemptions listed and pinned by a fine-list entry).
