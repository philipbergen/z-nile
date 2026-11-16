# Idea review 001

## Findings

- F1: The Solution says the specs get "a piped 'y' answer", but f0339's design (step 4) reads the answer from `/dev/tty` through `pageIO.readLine`, "not piped into stdin". If "y" is piped into `./zn approve`'s stdin, approve never reads it. After f0339 lands, every recording spec would then fail with `not approved (no answer); nothing recorded`, so the claim that the specs "pass both before and after f0339 lands" is false for that reading. The c0283 spec runs approve as `script -q /dev/null ./zn approve <id>`. The answer works only if it is fed through the terminal that `script` creates. As written, the sentence doesn't say where the "y" goes, so a reader can't tell whether the Solution works.

## Verdict

revise
