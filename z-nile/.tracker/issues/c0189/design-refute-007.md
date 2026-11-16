# Answers to design review 007 (c0189)

- F1: fixed (documents only): new Guess G5 (pending user) with both orders and their costs; the Risks bullet names the chain R0078, R0070, this chore, c0123 and the unenforced "ahead of c0157"; consequences: none for specs; the order stays `depends_on: [c0194]` until the user answers.
- F2: fixed: this chore is rafted only after R0070 is done (Existing work); R0070's note stays and is harmless.
- F3: fixed: step 1 (base 99913e40, `git apply --3way`, the four conflicts), step 7 and the c0194 bullet say c0194 lands first; `mutate.py`'s runner argument is optional.
- F4: fixed by exact wording in the M4 row (the `sh.writeReplacing` case's remainder stated); consequences: none.
- F5: fixed: 006 F2 harvested on z-design/restated-rules-move-together; the peers-scan proposal stays as the harvest of R0070 F2.
- F6: fixed: stated in Risks as prose-only.
