# Idea review 001

## Findings

- F1: The Solution makes the tracker refuse to land work with an unharvested escape, but it only requires recording design questions to a human. Nothing makes an agent record a question it asks during implementation, verification or merge. Those questions count as escapes, but the tracker has no record of them to refuse on. The 2026-11-12 case was exactly this kind: a question about a check's cost during the build. As written, that escape could still land with no lesson, so the Solution doesn't solve the second Problem for questions to a human. (Today `./zn lessons --uncovered` only sees review findings, because only they leave a file.)

## Verdict

revise
