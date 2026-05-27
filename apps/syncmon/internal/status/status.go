package status

type State int

const (
	StateUnknown State = iota
	StateIdle
	StateSyncing
	StateError
	StateInactive
	StateActive
)

func (s State) String() string {
	switch s {
	case StateIdle:
		return "Idle"
	case StateSyncing:
		return "Syncing"
	case StateError:
		return "Error"
	case StateInactive:
		return "Inactive"
	case StateActive:
		return "Active"
	default:
		return "Unknown"
	}
}

type Status struct {
	Name    string
	State   State
	Details string
	Devices []Status // Nested statuses for sub-items like devices
}

type StatusMsg struct {
	Service string
	Status  Status
	Err     error
}
