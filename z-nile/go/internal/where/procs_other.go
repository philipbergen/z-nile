//go:build !darwin

package where

import (
	"errors"

	"znile/internal/live"
)

func sysctlProcs([]int) (map[int]live.Proc, error) {
	return nil, errors.New("no sysctl process table here")
}
