class_name IdleState
extends HeroState

func enter():
	hero.velocity = Vector3.ZERO
	pass

func exit():
	pass

func process_input(event: InputEvent) -> HeroState:
	return null

func process_physics(delta: float) -> Array:
	if hero.interrupted:
		hero.interrupted = false
		return []
	
	if hero.health <= 0:
		return [func(): sm.change_state(sm.death_state)]
		
	hero.move_and_slide() # force is_on_floor to update
	var airborne = not hero.is_on_floor()
	if airborne and not "Flying" in  sm.state_statuses:
		return [func(): sm.change_state(sm.fall_state)]
	if "Channeling" in sm.state_statuses:
		return [func(): sm.change_state(sm.channel_state)]
	if pending_state:
		return [func(): sm.change_state(pending_state)]
	return []

func process_frame(delta: float) -> HeroState:
	return null

func simulate_input(input: PlayerInput):
	if not input:
		return

	if input.key in SpellList.cast_keys:
		return sm.cast_state
	
	if input.key == MOUSE_BUTTON_RIGHT:
		return sm.move_state

func decode(dict: Dictionary):
	return self

func serialize():
	return {'state_name': 'Idle'}
