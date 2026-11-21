package where

// The two readers of the process table, for the test that they agree.
var (
	SysctlProcs = sysctlProcs
	PsProcs     = psProcs
)
