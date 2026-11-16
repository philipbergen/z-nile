# Idea review 001

## Findings

- F1: The Solution says the end line after a landing means "take no other raft", but that contradicts z-work step 6 (`z-nile/skills/z-work/SKILL.md:15`). For a session started with no raft named, step 6 says that after an end line the worker says one line, including "what you take next", and runs `./zn work next` again with no raft. The landed line in `z-nile/engine/work.luau:209` ("…landed. Stop. Tell the person to start a fresh session…") agrees with the lesson, so the skill and the engine already disagree. Written as proposed, the lesson would be false under step 6 for no-raft sessions. Either it applies only when a raft was named, or the idea has to say which of the two texts is right, and that changes step 6's meaning, which the Non-goals don't fence.

## Verdict

revise
