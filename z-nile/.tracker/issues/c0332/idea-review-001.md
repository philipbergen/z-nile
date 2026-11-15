# Idea review 001

## Findings

- F1: The Solution points AGENTS.md at the wrong rule. zz-review (`z-nile/skills/zz-review/SKILL.md:18`) says an interactive session starts its reviewer subagent on the model that `.models.toml` names for that review's role. That is Opus for design, raft and code reviews, and `claude-fable-5-2` for the final review. The list of review models that c0306 adds to zz-review's "Who reviews" is different: it says which recorded models `./zn status`, `ready` and `done` will accept (any Opus, any Fable, kimi-code-k3, or grok at xhigh). With the pointer as written, a lead would read the exception to the sonnet default as "any model on the list", so starting a final reviewer on Opus would look fine, even though zz-review says to use the role's model, Fable. The exception should point to zz-review's rule that a reviewer runs on its role's model, not to the list of accepted models.

## Verdict

revise
