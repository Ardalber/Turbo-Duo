extends CharacterBody3D
## Voiture arcade. Les touches sont lues en "touches physiques" :
## W A S D = Z Q S D sur un clavier AZERTY.

const MAX_SPEED := 30.0
const ACCEL := 18.0
const BRAKE := 40.0
const REVERSE_MAX := 10.0
const DRAG := 8.0
const TURN_SPEED := 2.3

var key_up: Key = KEY_W
var key_down: Key = KEY_S
var key_left: Key = KEY_A
var key_right: Key = KEY_D
var car_color := Color(0.9, 0.15, 0.15)
var pad_id := -1   # numéro de manette (0 = 1re manette, 1 = 2e), -1 = aucune
var style := "sport"   # "sport" ou "bug" (petite voiture ronde style Volkswagen)
var touch = null          # commandes tactiles (téléphone), données par main.gd
var touch_prefix := "p1_" # "p1_" pour le joueur 1, "p2_" pour le joueur 2

var speed := 0.0
var can_drive := false
var boost_time := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var front_wheels: Array[Node3D] = []


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.0, 3.6)
	shape.shape = box
	shape.position.y = 0.5
	add_child(shape)

	if style == "bug":
		_build_bug()
	else:
		_build_sport()

	# Roues
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.08, 0.08, 0.08)
	for x in [-0.95, 0.95]:
		for z in [-1.2, 1.2]:
			var pivot := Node3D.new()
			pivot.position = Vector3(x, 0.4, z)
			add_child(pivot)
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.4
			cyl.bottom_radius = 0.4
			cyl.height = 0.35
			cyl.material = wheel_mat
			wheel.mesh = cyl
			wheel.rotation.z = PI / 2.0
			pivot.add_child(wheel)
			if z < 0.0:
				front_wheels.append(pivot)


func _build_sport() -> void:
	# Voiture de course carrée avec aileron
	_box(Vector3(1.8, 0.55, 3.6), Vector3(0, 0.55, 0), car_color)
	_box(Vector3(1.5, 0.5, 1.7), Vector3(0, 1.05, 0.35), Color(0.12, 0.14, 0.2))
	_box(Vector3(1.9, 0.12, 0.5), Vector3(0, 1.15, 1.65), car_color.darkened(0.35))
	_box(Vector3(0.4, 0.02, 3.62), Vector3(0, 0.835, 0), Color(1, 1, 1))
	for x in [-0.6, 0.6]:
		_box(Vector3(0.35, 0.18, 0.05), Vector3(x, 0.6, -1.81), Color(1.0, 1.0, 0.8), 3.0)
		_box(Vector3(0.35, 0.15, 0.05), Vector3(x, 0.6, 1.81), Color(1.0, 0.1, 0.1), 2.0)


func _build_bug() -> void:
	# Petite voiture ronde façon Volkswagen Coccinelle (sans logo)
	var glass := Color(0.12, 0.14, 0.2)
	var chrome := Color(0.85, 0.85, 0.9)
	_box(Vector3(1.6, 0.3, 3.2), Vector3(0, 0.45, 0), car_color.darkened(0.4))        # bas de caisse
	_ellipsoid(Vector3(0.85, 0.5, 1.8), Vector3(0, 0.75, 0), car_color)                # capot + coffre arrondis
	_ellipsoid(Vector3(0.74, 0.5, 0.95), Vector3(0, 1.12, 0.15), glass)                # vitres
	_ellipsoid(Vector3(0.68, 0.42, 0.82), Vector3(0, 1.25, 0.2), car_color)            # toit bombé
	for x in [-0.8, 0.8]:
		for z in [-1.2, 1.2]:
			_ellipsoid(Vector3(0.3, 0.38, 0.62), Vector3(x, 0.6, z), car_color)       # ailes rondes
		_ellipsoid(Vector3(0.16, 0.16, 0.08), Vector3(x, 0.78, -1.72), Color(1.0, 1.0, 0.8), 3.0)  # phares ronds
		_ellipsoid(Vector3(0.1, 0.14, 0.06), Vector3(x * 0.95, 0.75, 1.75), Color(1.0, 0.1, 0.1), 2.0)  # feux arrière
	for z in [-1.85, 1.85]:
		_box(Vector3(1.75, 0.12, 0.12), Vector3(0, 0.38, z), chrome)                    # pare-chocs chromés


func _ellipsoid(scl: Vector3, pos: Vector3, color: Color, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.material = _make_mat(color, emission)
	mi.mesh = sm
	mi.position = pos
	mi.scale = scl
	add_child(mi)
	return mi


func _make_mat(color: Color, emission: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.3
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


func _box(size: Vector3, pos: Vector3, color: Color, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.35
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return mi


var in_loop := false   # pendant le looping, c'est main.gd qui guide la voiture


func _physics_process(delta: float) -> void:
	if in_loop:
		return
	var throttle := 0.0
	var steer := 0.0
	if can_drive:
		if Input.is_physical_key_pressed(key_up):
			throttle += 1.0
		if Input.is_physical_key_pressed(key_down):
			throttle -= 1.0
		if Input.is_physical_key_pressed(key_left):
			steer += 1.0
		if Input.is_physical_key_pressed(key_right):
			steer -= 1.0
		# Manette Xbox : stick gauche = tourner, RT / A = accélérer, LT / B / X = freiner
		if pad_id >= 0:
			var sx := Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X)
			if absf(sx) > 0.2:
				steer -= sx
			var rt := Input.get_joy_axis(pad_id, JOY_AXIS_TRIGGER_RIGHT)
			var lt := Input.get_joy_axis(pad_id, JOY_AXIS_TRIGGER_LEFT)
			if rt > 0.1:
				throttle += rt
			if lt > 0.1:
				throttle -= lt
			if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_A):
				throttle += 1.0
			if Input.is_joy_button_pressed(pad_id, JOY_BUTTON_B) or Input.is_joy_button_pressed(pad_id, JOY_BUTTON_X):
				throttle -= 1.0
		# Téléphone : boutons à l'écran (chaque joueur a les siens sur sa moitié)
		if touch != null:
			if touch.is_pressed(touch_prefix + "gas"):
				throttle += 1.0
			if touch.is_pressed(touch_prefix + "brake"):
				throttle -= 1.0
			if touch.is_pressed(touch_prefix + "left"):
				steer += 1.0
			if touch.is_pressed(touch_prefix + "right"):
				steer -= 1.0
	steer = clampf(steer, -1.0, 1.0)
	throttle = clampf(throttle, -1.0, 1.0)

	if throttle > 0.0:
		speed += (BRAKE if speed < 0.0 else ACCEL) * throttle * delta
	elif throttle < 0.0:
		speed -= (BRAKE if speed > 0.0 else ACCEL * 0.6) * -throttle * delta
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)

	var top := MAX_SPEED
	if boost_time > 0.0:
		boost_time -= delta
		top = MAX_SPEED * 1.5
		speed += ACCEL * delta
	if speed > top:
		speed = move_toward(speed, top, 25.0 * delta)
	speed = maxf(speed, -REVERSE_MAX)

	# Direction : on tourne seulement si la voiture roule (inversé en marche arrière)
	var grip := clampf(absf(speed) / 6.0, 0.0, 1.0) * signf(speed)
	rotate_y(steer * TURN_SPEED * grip * delta)
	for w in front_wheels:
		w.rotation.y = steer * 0.45

	var fwd := -global_transform.basis.z
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	velocity.y -= gravity * delta
	move_and_slide()

	# Les chocs contre les murs (ou l'autre voiture) ralentissent
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) < 0.5:
			var impact := absf(fwd.dot(n))
			if impact > 0.4 and absf(speed) > 8.0 and pad_id >= 0:
				Input.start_joy_vibration(pad_id, 0.4, 0.8, 0.2)
			speed *= 1.0 - impact * 0.5


func boost() -> void:
	boost_time = 1.2
	if pad_id >= 0:
		Input.start_joy_vibration(pad_id, 0.6, 0.2, 0.4)
