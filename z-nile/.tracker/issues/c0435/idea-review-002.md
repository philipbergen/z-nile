# Idea review 002

## Findings

- F1: The first Problem sentence says design "costs the same whether the change is small or large", and the skill shows that is false. `z-nile/skills/z-design/SKILL.md:62` already caps design review at 2, 5 and 9 rounds for easy, normal and risky tickets, so review cost does scale with the ticket. The d0328 figure doesn't prove the cost is the same either: it shows a fixed minimum, not equal cost. What the rest of the Problem supports is narrower. Every ticket pays the same fixed drafting work (every section, acceptance specs, experiments, a size record) before its risk is known, and that minimum is about 195,000 tokens even for a three-line fix. The sentence should claim that minimum, not equal cost.

## Verdict

revise
