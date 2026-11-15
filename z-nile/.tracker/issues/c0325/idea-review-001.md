# Idea review 001

## Findings

- F1: The Solution changes how the author's model is matched, but it doesn't say what happens to the code that already acts on that match. Today `models.tries` drops every challenger try that matches (`z-nile/engine/models.luau:570`) and stops with an error when only the author's model is left (`:574-577`). If that drop and that error stay on the new match (effort ignored, fallback counted), the chain stops more often than it does now. For example, the author falls back to kimi, every remaining challenger try is a kimi model, and the error fires. That is the blocking the Non-goal says this idea won't do, and the 2026-11-15 ruling takes it away. If the drop and error don't stay, the Solution leaves out the change that removes them. Either way the Non-goal doesn't work as a fence: it rules out a stop the code already makes, and the Solution would make that stop happen more often.

## Verdict

revise
