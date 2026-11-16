---
title: Readable text is a number checked on every screen, from the layout's own constants
when: design
tags: [ui, layout, proxies]
check: For each text a screen shows (titles, taglines, badges, rows), does a pure case compute its size from the layout's boxes and regions and a stated glyph-width model, on every screen shape the layout claims to fit (a landscape phone included), and require at least a stated minimum, so that a layout constant that shrinks a label below it turns the case red?
---
"Fits every screen" is checked by boxes staying inside the area. That says nothing about the text in them: a card that fits a landscape phone can hold a tagline drawn at 6 px, unreadable, while every layout case stays green.

**Why:** f0205 design review 001 F5: with a 0.6-aspect front card, the tagline on an 844 x 390 phone was about 6.6 px tall on one line and under 9 px wrapped; readability had no measurable proxy.

**How to apply:** state `MIN_TEXT` and a glyph-width model (`width / (GLYPH x characters)` on one line, the best of a few lines when the label wraps) in the pure layout feature, add a case over the same screen list the layout cases use that computes every label's text size from the real texts, and tune the constants (the card's aspect, the region heights) until it passes; leave only the true font's rendering to Observed.
