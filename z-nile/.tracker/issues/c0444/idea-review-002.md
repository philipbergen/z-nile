# Idea review 002

## Findings

- F1: The Problem sentence "No page z-nile shows a person has both a light and a dark theme" is false. Both `z-nile/README.html` and `z-nile/.tracker/issues/f0425/mockup/index.html` already have a light theme and a warm dark theme, chosen with a theme button. They came in with f0425 (#723). README.html's own comment reads "Light is the default whatever the OS says, like philip-bergen.com; the theme button switches to this warm dark set" (line 31, button at line 231). The mockup also saves the choice in `localStorage` under `f0425-theme` (lines 1362 and 2781). So "follows `prefers-color-scheme`, with no switch on the page" is not adding a missing dark theme. It means removing a button and a saved choice the owner already accepted, and replacing light-only-like-the-site with following the OS. That removal breaks the non-goal "No page's content, structure, links or commands change". It is also more than the smallest fix for a problem that, as stated, does not exist. The Problem needs to say what is actually wrong with the current switch. Otherwise the theme sentences should only bring the board, the published board and the explainer up to what README.html and the mockup already do.

## Verdict

revise
