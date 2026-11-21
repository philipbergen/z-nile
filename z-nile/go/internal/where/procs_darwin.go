//go:build darwin

package where

import (
	"encoding/binary"
	"errors"
	"fmt"
	"syscall"
	"unsafe"

	"znile/internal/live"
)

// sysctlProcs reads each pid's kinfo_proc with sysctl(kern.proc.pid), so no ps is started: macOS's ps is a setuid
// program that a sandbox (the spec runner's jail) refuses to run. The start time is the process's p_starttime
// (seconds.microseconds) and a zombie has p_stat SZOMB. A pid the kernel does not know is absent from the result.
func sysctlProcs(pids []int) (map[int]live.Proc, error) {
	const (
		ctlKern     = 1
		kernProc    = 14
		kernProcPID = 1
		szomb       = 5
		statOffset  = 36 // extern_proc: p_un (16) p_vmspace (8) p_sigacts (8) p_flag (4), then p_stat
	)
	res := map[int]live.Proc{}
	for _, pid := range pids {
		mib := [4]int32{ctlKern, kernProc, kernProcPID, int32(pid)}
		buf := make([]byte, 1024)
		n := uintptr(len(buf))
		_, _, e := syscall.Syscall6(syscall.SYS___SYSCTL, uintptr(unsafe.Pointer(&mib[0])), 4,
			uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&n)), 0, 0)
		if e != 0 {
			return nil, fmt.Errorf("sysctl kern.proc.pid %d: %w", pid, e)
		}
		if n < statOffset+1 {
			continue // no such process
		}
		sec := int64(binary.LittleEndian.Uint64(buf[0:8]))
		usec := int64(int32(binary.LittleEndian.Uint32(buf[8:12])))
		if sec == 0 {
			return nil, errors.New("sysctl kern.proc.pid gave no start time")
		}
		res[pid] = live.Proc{Start: fmt.Sprintf("%d.%06d", sec, usec), Zombie: buf[statOffset] == szomb}
	}
	return res, nil
}
