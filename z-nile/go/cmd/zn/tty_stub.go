package main

import "errors"

// tcgetpgrp is the terminal's foreground process group (stub: the tests come first).
func tcgetpgrp(fd int) (int, error) { return 0, errors.New("not built") }
