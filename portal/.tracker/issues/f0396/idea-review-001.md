# Idea review 001

## Findings

- F1: The Solution's third sentence says the start level is one "which the server decides and never accepts from the client", but the picker's whole purpose is to send the player's choice from the client. In f0148 the client sends the level (`StartGame:FireServer(level)`), and the server keeps it only when it is a whole number from 1 to the stored best (`Best.choose`; anything else becomes level 1). As written, a reader can't tell whether this sentence is true or false: taken literally it rules out the feature. It should say what the server enforces: it bounds the client's choice by the stored best, and nothing the client sends, including TeleportData, reaches the game place.

## Verdict

revise
