---
title: Judge a drawing's legibility at the size the page renders it
when: both
tags: [ui, charts, judged]
check: For each drawing a page embeds (an SVG with a viewBox), what CSS width does the page give it, and how many pixels is its smallest text after that scaling; and is every unit, scale and lone series named in text the reader sees, not only in a tooltip?
---
A drawing made in a 640-wide viewBox and shown 320 px wide has half-size text: an 11 px label renders at 5.5 px. Its parts pass a unit spec while the picture fails the Judged criterion.

**Why:** R0083 (c0118) code review 001 F1: the board's charts inherited Stats' `.chart { width: 320px }`, so axis and legend text was unreadable at 1440×900, the token axis (k or M tokens) showed its unit only in hover tooltips, and a one-series chart had no legend at all.

**How to apply:** when a design or a review judges a chart or diagram, compute viewBox width against CSS width, put the unit and a lone series in the caption, and pin both in a spec that reads the model and the page. A reviewer opens or renders the page; it never rules on the SVG's source alone.
