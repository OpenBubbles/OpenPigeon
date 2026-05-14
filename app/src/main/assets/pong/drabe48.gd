class_name Drand48
extends RefCounted

var _state: int = 0
const _MASK: int = (1 << 48) - 1
const _MULT: int = 0x5DEECE66D
const _INC: int = 0xB

func srand48(seed_val: int) -> void:
	var low32: int = seed_val & 0xFFFFFFFF
	_state = ((low32 << 16) | 0x330E) & _MASK

func drand48() -> float:
	_state = (_state * _MULT + _INC) & _MASK
	return float(_state) / float(1 << 48)
