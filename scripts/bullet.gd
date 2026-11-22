extends Node3D
## A simulated bullet: travel time, gravity drop and wind drift.
## Each physics frame it ray-casts along its path so it can never tunnel through anything.

const HIT_MASK := 3   # layer 1 = world, layer 2 = enemies

var velocity := Vector3.ZERO
var gravity := 9.81
var wind := Vector3.ZERO
var _life := 6.0


func launch(initial_velocity: Vector3, g: float, wind_accel: Vector3) -> void:
	velocity = initial_velocity
	gravity = g
	wind = wind_accel


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return

	var from := global_position
	velocity += (Vector3(0.0, -gravity, 0.0) + wind) * delta
	var to := from + velocity * delta

	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		global_position = to
		return

	var collider = result["collider"]
	var hit_enemy := false
	if collider != null and collider.has_method("register_hit"):
		hit_enemy = true
		var is_head := false
		if collider is CollisionObject3D:
			var owner_id: int = collider.shape_find_owner(result["shape"])
			var shape_node = collider.shape_owner_get_owner(owner_id)
			if shape_node != null and shape_node.name == &"HeadCollision":
				is_head = true
		collider.register_hit(result["position"], is_head)

	var surface := "dirt"
	if not hit_enemy and collider != null and not String(collider.name).begins_with("Terrain"):
		surface = "rock"
	var manager := get_tree().get_first_node_in_group("game_manager")
	if manager != null:
		manager.spawn_impact(result["position"], result["normal"], hit_enemy, surface)
	queue_free()
