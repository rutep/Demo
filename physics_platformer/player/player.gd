class_name Player
extends RigidBody2D

# Character Demo, written by Juan Linietsky.
#
#  Implementation of a 2D Character controller.
#  This implementation uses the physics engine for
#  controlling a character, in a very similar way
#  than a 3D character controller would be implemented.
#
#  Using the physics engine for this has the main advantages:
#    - Easy to write.
#    - Interaction with other physics-based objects is free
#    - Only have to deal with the object linear velocity, not position
#    - All collision/area framework available
#
#  But also has the following disadvantages:
#    - Objects may bounce a little bit sometimes
#    - Going up ramps sends the chracter flying up, small hack is needed.
#    - A ray collider is needed to avoid sliding down on ramps and
#      undesiderd bumps, small steps and rare numerical precision errors.
#      (another alternative may be to turn on friction when the character is not moving).
#    - Friction cant be used, so floor velocity must be considered
#      for moving platforms.

const WALK_ACCEL = 500.0
const WALK_DEACCEL = 500.0
const WALK_MAX_VELOCITY = 140.0
const AIR_ACCEL = 100.0
const AIR_DEACCEL = 100.0
const JUMP_VELOCITY = 380
const STOP_JUMP_FORCE = 450.0
const MAX_SHOOT_POSE_TIME = 0.3
const MAX_FLOOR_AIRBORNE_TIME = 0.15

var anim = ""
var siding_left = false
var jumping = false
var stopping_jump = false
var shooting = false

var floor_h_velocity = 0.0

var airborne_time = 1e20
var shoot_time = 1e20

var Bullet = preload("res://player/Bullet.tscn")
var Enemy = preload("res://enemy/Enemy.tscn")

func _integrate_forces(s):
	var lv = s.get_linear_velocity()
	var step = s.get_step()
	
	var new_anim = anim
	var new_siding_left = siding_left
	var yes = anim
	
	# Get the controls.
	var move_left = Input.is_action_pressed("move_left")
	var move_right = Input.is_action_pressed("move_right")
	var jump = Input.is_action_pressed("jump")
	var shoot = Input.is_action_pressed("shoot")
	var spawn = Input.is_action_pressed("spawn")
	
	if spawn:
		call_deferred("_spawn_enemy_above")
	
	# Deapply prev floor velocity.
	lv.x -= floor_h_velocity
	floor_h_velocity = 0.0
	
	# Find the floor (a contact with upwards facing collision normal).
	var found_floor = false
	var floor_index = -1
	
	for x in range(s.get_contact_count()):
		var ci = s.get_contact_local_normal(x)
		
		if ci.dot(Vector2(0, -1)) > 0.6:
			found_floor = true
			floor_index = x
	
	# A good idea when implementing characters of all kinds,
	# compensates for physics imprecision, as well as human reaction delay.
	if shoot and not shooting:
		call_deferred("_shot_bullet")
	else:
		shoot_time += step
	
	if found_floor:
		airborne_time = 0.0
	else:
		airborne_time += step # Time it spent in the air.
	
	var on_floor = airborne_time < MAX_FLOOR_AIRBORNE_TIME

	# Process jump.
	if jumping:
		if lv.y > 0:
			# Set off the jumping flag if going down.
			jumping = false
		elif not jump:
			stopping_jump = true
		
		if stopping_jump:
			lv.y += STOP_JUMP_FORCE * step
	
	if on_floor:
		# Process logic when character is on floor.
		if move_left and not move_right:
			if lv.x > -WALK_MAX_VELOCITY:
				lv.x -= WALK_ACCEL * step
		elif move_right and not move_left:
			if lv.x < WALK_MAX_VELOCITY:
				lv.x += WALK_ACCEL * step
		else:
			var xv = abs(lv.x)
			xv -= WALK_DEACCEL * step
			if xv < 0:
				xv = 0
			lv.x = sign(lv.x) * xv
		
		# Check jump.
		if not jumping and jump:
			lv.y = -JUMP_VELOCITY
			jumping = true
			stopping_jump = false
			($SoundJump as AudioStreamPlayer2D).play()
		
		# Check siding.
		if lv.x < 0 and move_left:
			new_siding_left = true
		elif lv.x > 0 and move_right:
			new_siding_left = false
		if jumping:
			new_anim = "jumping"
		elif abs(lv.x) < 0.1:
			if shoot_time < MAX_SHOOT_POSE_TIME:
				new_anim = "idle_weapon"
			else:
				new_anim = "idle"
		else:
			if shoot_time < MAX_SHOOT_POSE_TIME:
				new_anim = "run_weapon"
			else:
				new_anim = "run"
	else:
		# Process logic when the character is in the air.
		if move_left and not move_right:
			if lv.x > -WALK_MAX_VELOCITY:
				lv.x -= AIR_ACCEL * step
		elif move_right and not move_left:
			if lv.x < WALK_MAX_VELOCITY:
				lv.x += AIR_ACCEL * step
		else:
			var xv = abs(lv.x)
			xv -= AIR_DEACCEL * step
			
			if xv < 0:
				xv = 0
			lv.x = sign(lv.x) * xv
		
		if lv.y < 0:
			if shoot_time < MAX_SHOOT_POSE_TIME:
				new_anim = "jumping_weapon"
			else:
				new_anim = "jumping"
		else:
			if shoot_time < MAX_SHOOT_POSE_TIME:
				new_anim = "falling_weapon"
			else:
				new_anim = "falling"
	
	# Update siding.
	if new_siding_left != siding_left:
		if new_siding_left:
			($AnimatedSprite as AnimatedSprite).scale.x = -0.03
			($AnimatedSprite as AnimatedSprite).scale.y = 0.03
		else:
			($AnimatedSprite as AnimatedSprite).scale.x = 0.03
			($AnimatedSprite as AnimatedSprite).scale.y = 0.03
		
		siding_left = new_siding_left
	
	# Change animation.
	if new_anim != anim:
		anim = new_anim
		($AnimatedSprite as AnimatedSprite).play(anim)
		
	shooting = shoot
	
	# Apply floor velocity.
	if found_floor:
		floor_h_velocity = s.get_contact_collider_velocity_at_position(floor_index).x
		lv.x += floor_h_velocity
	
	# Finally, apply gravity and set back the linear velocity.
	lv += s.get_total_gravity() * step
	s.set_linear_velocity(lv)


func _shot_bullet():
	shoot_time = 0
	var bi = Bullet.instance()
	var ss
	if siding_left:
		ss = -1.0
	else:
		ss = 1.0
	var pos = position + ($BulletShoot as Position2D).position * Vector2(ss, 1.0)
		
	bi.position = pos
	get_parent().add_child(bi)
	
	bi.linear_velocity = Vector2(400.0 * ss, -40)
	
	($Sprite/Smoke as Particles2D).restart()
	($SoundShoot as AudioStreamPlayer2D).play()
	
	add_collision_exception_with(bi) # Make bullet and this not collide.


func _spawn_enemy_above():
	var e = Enemy.instance()
	e.position = position + 100 * Vector2.UP
	get_parent().add_child(e)

