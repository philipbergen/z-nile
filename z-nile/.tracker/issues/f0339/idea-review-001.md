# Idea review 001

## Findings

- F1: "The approve command opens the ticket's page in the default editor" works against the problem it is meant to solve. The default editor (`$EDITOR`/`$VISUAL`) shows an HTML file as raw markup, so the approver gets tags instead of the before and after diagrams and the plain-words explanation. The reader still isn't shown an explanation before answering y or n. The page has to open in something that renders it, such as the default browser or the system's default app for `.html` (`open` on macOS). The sentence should name that.

## Verdict

revise
