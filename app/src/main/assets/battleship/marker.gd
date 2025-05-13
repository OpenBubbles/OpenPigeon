extends Node2D

class_name BattlegroundMarker

func play_anim():
	(get_node("AnimationPlayer") as AnimationPlayer).play()

enum MarkerMode {
	ELIMINATED,
	MISSED,
	TARGET
}

func set_mode(mode: MarkerMode):
	var target = get_node("Target") as Node2D
	var eliminated = get_node("Eliminated") as Node2D
	var missed = get_node("Missed") as Node2D
	target.visible = false
	eliminated.visible = false
	missed.visible = false
	match mode:
		MarkerMode.ELIMINATED:
			eliminated.visible = true
		MarkerMode.TARGET:
			target.visible = true
		MarkerMode.MISSED:
			missed.visible = true
