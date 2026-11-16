# Idea review 001

## Findings

- F1: The Solution's scope ("Every README sentence about when a z-work session stops or continues agrees with the z-work skill") contradicts the Non-goal that fences off c0264's two sections, because those sections contain such sentences and they disagree with the skill. In Intent (`z-nile/README.md:28`), a worker "takes a raft and stays with it until it merges … then clears its context and takes the next raft". The worker (`z-nile/README.md:81`) says a worker "clears its context and picks up the next raft whenever a raft ends". Neither has the named-raft stop, and both say the context is cleared, which the skill's step 8 says no CLI can do. If those sections are left alone, the Solution as written is false. The only sentences outside c0264's sections are the two the Problem names (`z-nile/README.md:210` and `:246`), so the Solution should be limited to the README outside c0264's two sections. Without that limit the fence and the goal overlap. The Problem itself checks out: #330 (50c313e6) landed the change, and both sentences still say the session ends when the raft lands or is released.

## Verdict

revise
