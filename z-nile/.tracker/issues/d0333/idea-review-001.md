# Idea review 001

## Findings

- F1: The non-goal doesn't fence anything. "The raft's allowed post-finish files" is the very set this fix changes, so it's true of any fix by definition: add `spend.md`, or any other path, to the list and the sentence still holds. It's also unclear which list it means. `layergit.isPostFinishPath` (`z-nile/engine/layergit.luau:118`) and trace's two lists (`isTrackerFileOf` and `isAllowedAfterTrace`, `z-nile/engine/trace.luau:437` and `:463`) are separate and accept different paths. R0102's final review shows each giving its own refusal. To be a real fence, the non-goal has to name a fixed set. For example: no path is added except the raft's `spend.md`, and a post-finish change to code, specs or any other tracker file still unfinishes the layer.

## Verdict

revise
