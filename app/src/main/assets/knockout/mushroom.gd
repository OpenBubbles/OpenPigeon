extends RigidBody2D

@export var trigger_radius: float = 26.0
@export var bounce_multiplier: float = 1.08
@export var extra_impulse: float = 110.0
@export var cooldown_msec: int = 200
@export var detect_layers: int = -1

@onready var spr: Sprite2D = $Sprite2D
@onready var area: Area2D = $Trigger
var _last_hit: Dictionary = {}
var _piece_container: Node = null

const _MAX_LAYERS := 32
const _MASK_ALL := (1 << _MAX_LAYERS) - 1

func set_piece_container(n: Node) -> void:
	_piece_container = n

func _ready() -> void:
	freeze = true
	gravity_scale = 0.0
	collision_layer = 0
	collision_mask  = 0
	sleeping = true

	if spr:
		spr.z_index = 0

	if area:
		area.monitoring  = true
		area.monitorable = true
		area.collision_layer = 0
		area.collision_mask  = (_MASK_ALL if detect_layers < 0 else detect_layers)

		var cs := area.get_node("CollisionShape2D") as CollisionShape2D
		if cs and cs.shape is CircleShape2D:
			(cs.shape as CircleShape2D).radius = trigger_radius

		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body is RigidBody2D and (body as Node).has_meta("player"):
		_bounce(body as RigidBody2D)

func _physics_process(_dt: float) -> void:
	if _piece_container == null:
		return

	for child in _piece_container.get_children():
		if child is RigidBody2D and (child as Node).has_meta("player"):
			var rb := child as RigidBody2D
			var r_sum := _world_radius(self, trigger_radius) + _world_radius(rb, _get_piece_radius(rb))
			if rb.global_position.distance_squared_to(global_position) <= r_sum * r_sum:
				_bounce(rb)

func _bounce(rb: RigidBody2D) -> void:
	var now := Time.get_ticks_msec()
	var last := int(_last_hit.get(rb, 0))
	if now - last < cooldown_msec:
		return
	_last_hit[rb] = now

	# Flip direction 180° and add a little extra energy
	var v := rb.linear_velocity
	if v.length() < 1.0:
		# If nearly stopped, push away from the center
		v = (rb.global_position - global_position).normalized() * 60.0

	rb.linear_velocity = -v * bounce_multiplier

	# Nudge outward so it doesn't sit inside the trigger
	var out_dir := (rb.global_position - global_position).normalized()
	rb.apply_impulse(out_dir * extra_impulse)

	_play_bounce_anim()

func _play_bounce_anim() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * 1.35, 0.06)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.15)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _get_piece_radius(rb: RigidBody2D) -> float:
	var cs := rb.find_child("CollisionShape2D", true, false) as CollisionShape2D
	if cs and cs.shape is CircleShape2D:
		return (cs.shape as CircleShape2D).radius
	return 24.0

func _world_radius(node: Node2D, local_r: float) -> float:
	var s := node.get_global_transform().get_scale()
	return local_r * max(absf(s.x), absf(s.y))
