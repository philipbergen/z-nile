package live

import (
	"math"
	"strconv"
	"strings"
	"time"
)

// StartSecs reads a process start time to epoch seconds. Two spellings exist: "sec.usec" (the macOS kernel's, and what
// this daemon writes there) and ps's lstart ("Sat Nov 21 01:38:26 2026", local time), which step 1's logs hold. The
// second return is false when the text is neither.
func StartSecs(s string) (float64, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, false
	}
	if f, err := strconv.ParseFloat(s, 64); err == nil && f > 1e8 {
		return f, true
	}
	t, err := time.ParseInLocation("Mon Jan 2 15:04:05 2006", strings.Join(strings.Fields(s), " "), time.Local)
	if err != nil {
		return 0, false
	}
	return float64(t.Unix()), true
}

// sameStart reports whether two start times name one moment, within a second (ps keeps whole seconds). Texts that cannot
// be read as times are the same only when they are equal.
func sameStart(a, b string) bool {
	if a == b {
		return true
	}
	x, okx := StartSecs(a)
	y, oky := StartSecs(b)
	return okx && oky && math.Abs(x-y) <= 1
}

// startVerdict says what a live process's start time means for a worker that recorded start: "same", "reused" (a different
// moment), or "unknown" (one of them cannot be read: the record is refreshed from the live process, never counted as reuse).
func startVerdict(recorded, now string) string {
	x, okx := StartSecs(recorded)
	y, oky := StartSecs(now)
	switch {
	case !okx || !oky:
		return "unknown"
	case math.Abs(x-y) <= 1:
		return "same"
	}
	return "reused"
}
