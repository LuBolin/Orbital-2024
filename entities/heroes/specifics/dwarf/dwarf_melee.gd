class_name DwarfMelee
extends ShapeCast3D

@onready var attack_mesh: CurveMesh3D = $AttackMesh

const bullet_scene = preload("res://entities/heroes/specifics/dwarf/dwarf_melee.tscn")

var id: int
var type = "DwarfMelee"
var direction: Vector2
var lifespan: float = 0.15
var hit_scanned: bool = false
var hero : Hero
var spawn_offset = 15

static func create(hero: Hero, target: Vector2, offset: float = 0):
	var bullet = bullet_scene.instantiate()
	var dirn: Vector2 = \
		target - Vector2(
			hero.global_position.x,
			hero.global_position.z)
	dirn = dirn.normalized()
	
	var manager: UnitManager = hero.unit_manager
	var b_id = manager.add(bullet)
	bullet.init(b_id, dirn, hero, offset)
	return bullet

var hits = []

func init(b_id: int, dirn: Vector2, h: Hero, offset = 0):
	id = b_id
	direction = dirn
	hero = h
	add_exception(hero)

	var dirn_v3: Vector3 = Vector3(direction.x, 0, direction.y)
	global_position += dirn_v3 * spawn_offset
	global_position += dirn_v3.normalized() * offset
	
	var look_target = global_position + dirn_v3.normalized()
	look_at(look_target)

func simulate(unit_states):
	var interactions = []
	global_position = unit_states['position']
	direction = unit_states['direction']
	var dirn: Vector3 = Vector3(direction.x, 0, direction.y)
	lifespan = unit_states['lifespan']
	hit_scanned = unit_states['hit_scanned']
	var delta = get_physics_process_delta_time()

	var look_target = global_position + dirn.normalized()
	look_at(look_target)
	
	if not hit_scanned:
		hit_scanned = true
		target_position = dirn
		force_shapecast_update()
		var hits = []
		for target in collision_result:
			var collider = target['collider']
			if collider in hits:
				continue
			hits.append(collider)
			if collider.get("health"):
				interactions.append(func(): collider.health -= 2)
	
	lifespan -= delta
	if lifespan < 0:
		var node = self
		var parent = get_parent()
		interactions.append(func(): parent.remove_child(node); queue_free())
	return interactions


func get_state():
	return {'id' : id,\
		'type' : type, \
		'direction' : direction,\
		'position' : global_position,\
		'lifespan' : lifespan,
		'hit_scanned' : hit_scanned,
		}
