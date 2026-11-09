---
title: A page that renders documents into a page holding a secret allows only safe link schemes
when: both
tags: [servers, security, rendering]
check: Which link schemes does the renderer keep in a document's markdown (marked keeps `javascript:`), and can a script link read the page's session token or post its actions?
---
A document an agent or a contributor wrote can contain `[x](javascript:...)`. On a served page that holds a session token and posts actions, a click runs it in the page.

**Why:** R0084 (c0121) code review 001 F3: the vendored marked keeps `javascript:` hrefs.

**How to apply:** override the renderer's link so only no-scheme, `http`, `https` and `mailto` targets keep their href (strip control characters and spaces before the test), render anything else as its text, and pin it with a page spec that renders such a document.
