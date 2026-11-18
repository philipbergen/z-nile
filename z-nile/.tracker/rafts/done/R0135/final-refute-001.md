# Final refute 001

- F1: fixed: the record is corrected here and the file is left as it is: after review-001 F2 the 153-character line is gone and the comment sits on `ondisk.items`, and seven comment lines of `c0042/ondisk.luau` (2 to 7 and 27) are still 112 to 117 characters, over the 110 of `column_width`, which stylua does not apply to comments; refute-001's "under 110 columns" was not measured; consequences: none for the gate (stylua and selene pass); the source is not changed after finish, so the trace's `Commit:` line stays true.
