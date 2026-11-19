# Idea review 001

## Findings

- F1: The first Solution sentence can't be checked for the config spec's test-screen-lines case. That case's subject is `PaidPlay.testLines` itself (`config.spec.luau:178-185`), so "compare the test screen's lines through the library" there would compare the library with itself: it always passes and pins nothing. The idea doesn't say what the case still checks after the play's literal `toEqual` is removed. f0395's prototype narrowing (`experiments/c0397-narrowing.patch`) does something else. It drops the price line and pins the line count, the title line and the note line, which is what f0395's Regression guard relies on. Without that, a reader can't decide whether that case was narrowed correctly or emptied. The receipts case is fine: it compares what Receipts sends with the library's output. The Prices case is also fine: it reads the fields one by one.

## Verdict

revise
