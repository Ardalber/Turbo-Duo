extends Node3D
## "Turbo Duo" - course de voitures à 2 joueurs en écran partagé.
## Le premier à boucler 3 tours gagne. Tout est généré en code (formes simples).

const CarScript := preload("res://car.gd")
const TouchScript := preload("res://touch_controls.gd")
var touch   # commandes tactiles (visibles seulement sur téléphone)
const N := 64            # nombre de points du tracé
const HALF_W := 7.0      # demi-largeur de la piste
const LAPS := 3
const CP_STEP := 8       # un point de passage tous les 8 points

var center: Array[Vector3] = []
var left_edge: Array[Vector3] = []
var right_edge: Array[Vector3] = []
var checkpoints: Array[int] = []
var cars: Array = []     # { "car", "next", "laps" }
var cams: Array[Camera3D] = []
var hud_labels: Array[Label] = []
var big_label: Label

var state := "countdown"
var countdown := 3.99
var go_time := 0.0
var cam_yaw := [0.0, 0.0]        # rotation de caméra au joystick droit
var cam_height := [3.8, 3.8]
var spectators: Array = []
var anim_t := 0.0

const BRIDGE_IDX := 29   # point du tracé où se trouve le pont
var crowd_player: AudioStreamPlayer
var crowd_sources: Array = []    # [position, intensité]
var crowd_level := 0.0
var reverb: AudioEffectReverb

const LOOP_IDX := 17      # point du tracé où se trouve le looping (juste après un turbo)
const LOOP_R := 6.0       # rayon du looping (12 m de haut)
const LOOP_LANE := 2.25   # décalage latéral entrée/sortie (pour ne pas se croiser)
var loop_node: Node3D

var COLORS := [Color(0.9, 0.15, 0.15), Color(0.15, 0.45, 0.95)]


func _ready() -> void:
	_build_environment()
	_build_track()
	_build_touch()
	_spawn_cars()
	_build_screens()
	_update_cameras(1.0, true)


func _build_touch() -> void:
	# Téléphone : chaque joueur a ses boutons en bas de sa moitié d'écran
	#   < >  pour tourner (côté gauche de sa moitié), FREIN et GAZ (côté droit)
	touch = TouchScript.new()
	add_child(touch)
	for i in 2:
		var p := "p%d_" % (i + 1)
		var off := 0.5 * i
		touch.add_button(p + "left", "<", Vector2(0.06 + off, 0.8))
		touch.add_button(p + "right", ">", Vector2(0.16 + off, 0.8))
		touch.add_button(p + "brake", "FREIN", Vector2(0.33 + off, 0.86))
		touch.add_button(p + "gas", "GAZ", Vector2(0.42 + off, 0.72))
	touch.add_button("restart", "R", Vector2(0.5, 0.07), 34.0)
	touch.button_pressed.connect(_on_touch_button)


func _on_touch_button(id: String) -> void:
	if id == "restart":
		get_tree().reload_current_scene()


# ---------------------------------------------------------------- Monde

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skymat := ProceduralSkyMaterial.new()
	skymat.sky_top_color = Color(0.25, 0.5, 0.9)
	skymat.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky.sky_material = skymat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 40, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)


func mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


func _visual_box(parent: Node, size: Vector3, pos: Vector3, rot_y: float, material: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = material
	mi.mesh = bm
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)


func _tangent(i: int) -> Vector3:
	return (center[(i + 1) % N] - center[(i - 1 + N) % N]).normalized()


func _normal(i: int) -> Vector3:
	var t := _tangent(i)
	return Vector3(-t.z, 0.0, t.x)


func _build_track() -> void:
	# Tracé : une boucle ondulée
	for i in N:
		var a := TAU * float(i) / float(N)
		var rx := 50.0 + 6.0 * sin(2.0 * a)
		var rz := 30.0 + 5.0 * sin(3.0 * a)
		center.append(Vector3(rx * cos(a), 0.0, rz * sin(a)))
	for i in N:
		left_edge.append(center[i] + _normal(i) * HALF_W)
		right_edge.append(center[i] - _normal(i) * HALF_W)
	for i in range(0, N, CP_STEP):
		checkpoints.append(i)

	# Sol (herbe)
	var ground := StaticBody3D.new()
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)
	var gcs := CollisionShape3D.new()
	var gsh := BoxShape3D.new()
	gsh.size = Vector3(240, 1, 200)
	gcs.shape = gsh
	ground.add_child(gcs)
	_visual_box(ground, gsh.size, Vector3.ZERO, 0.0, mat(Color(0.3, 0.6, 0.25)))

	# Bitume (maillage plat entre les deux bords)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in N:
		var j := (i + 1) % N
		var a := left_edge[i]
		var b := right_edge[i]
		var c := left_edge[j]
		var d := right_edge[j]
		for v in [a, b, c, b, d, c]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v + Vector3.UP * 0.02)
	var road := MeshInstance3D.new()
	road.mesh = st.commit()
	var road_mat := mat(Color(0.22, 0.22, 0.25))
	road_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	road.material_override = road_mat
	add_child(road)

	# Pointillés au centre
	var white := mat(Color(0.95, 0.95, 0.95))
	for i in range(0, N, 2):
		var t := _tangent(i)
		_visual_box(self, Vector3(0.3, 0.03, 2.0), center[i] + Vector3.UP * 0.04, atan2(t.x, t.z), white)

	# Murs rouges et blancs des deux côtés
	var walls := StaticBody3D.new()
	add_child(walls)
	var red := mat(Color(0.85, 0.1, 0.1))
	for side in [left_edge, right_edge]:
		for i in N:
			var a: Vector3 = side[i]
			var b: Vector3 = side[(i + 1) % N]
			var dir := b - a
			var length := dir.length() + 0.8
			var rot := atan2(dir.x, dir.z)
			var mid := (a + b) * 0.5 + Vector3.UP * 0.6
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.8, 1.2, length)
			cs.shape = sh
			cs.position = mid
			cs.rotation.y = rot
			walls.add_child(cs)
			_visual_box(walls, sh.size, mid, rot, red if i % 2 == 0 else white)

	_build_finish_line()

	# Accélérateurs (bandes bleues lumineuses)
	for i in [12, 30, 46]:
		_add_boost_pad(i)

	# Arbres décoratifs
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var trunk_mat := mat(Color(0.4, 0.25, 0.12))
	var leaf_mat := mat(Color(0.15, 0.45, 0.2))
	for k in 90:
		var p := Vector3(rng.randf_range(-110, 110), 0, rng.randf_range(-90, 90))
		var ok := true
		for c in center:
			if Vector2(p.x - c.x, p.z - c.z).length() < HALF_W + 5.0:
				ok = false
				break
		if ok:
			_add_tree(p, rng.randf_range(0.8, 1.5), trunk_mat, leaf_mat)

	_add_crowds()
	_build_bridge(BRIDGE_IDX)
	_build_loop()
	_setup_crowd_sound()


# ---------------------------------------------------------------- Looping

func _loop_pos(u: float) -> Vector3:
	# u va de 0 (entrée, en bas) à 1 (sortie, en bas, décalée sur le côté)
	var th := TAU * u
	return Vector3(-LOOP_LANE + 2.0 * LOOP_LANE * u, LOOP_R - LOOP_R * cos(th), LOOP_R * sin(th))


func _loop_up(u: float) -> Vector3:
	var th := TAU * u
	return Vector3(0.0, cos(th), -sin(th))


func _loop_fwd(u: float) -> Vector3:
	var th := TAU * u
	return Vector3(2.0 * LOOP_LANE, TAU * LOOP_R * sin(th), TAU * LOOP_R * cos(th)).normalized()


func _build_loop() -> void:
	var t := _tangent(LOOP_IDX)
	loop_node = Node3D.new()
	loop_node.position = center[LOOP_IDX]
	loop_node.rotation.y = atan2(t.x, t.z)   # axe Z local = sens de la course
	add_child(loop_node)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 72
	var half := 2.0
	var rail_col := Color(0.25, 0.25, 0.3)
	for k in segs:
		var u0 := float(k) / segs
		var u1 := float(k + 1) / segs
		var p0 := _loop_pos(u0)
		var p1 := _loop_pos(u1)
		var n0 := _loop_up(u0)
		var n1 := _loop_up(u1)
		var col := Color(0.9, 0.15, 0.15) if int(k / 3.0) % 2 == 0 else Color(0.95, 0.95, 0.95)
		var l0 := p0 + Vector3(-half, 0, 0)
		var r0 := p0 + Vector3(half, 0, 0)
		var l1 := p1 + Vector3(-half, 0, 0)
		var r1 := p1 + Vector3(half, 0, 0)
		# piste du looping
		_tri(st, [l0, r0, l1, r0, r1, l1], [n0, n0, n1, n0, n1, n1], col)
		# petits rebords des deux côtés
		_tri(st, [l0, l0 + n0 * 0.5, l1, l0 + n0 * 0.5, l1 + n1 * 0.5, l1], [Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT], rail_col)
		_tri(st, [r0, r0 + n0 * 0.5, r1, r0 + n0 * 0.5, r1 + n1 * 0.5, r1], [Vector3.LEFT, Vector3.LEFT, Vector3.LEFT, Vector3.LEFT, Vector3.LEFT, Vector3.LEFT], rail_col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.5
	mi.material_override = m
	loop_node.add_child(mi)

	var sign3d := Label3D.new()
	sign3d.text = "LOOPING !"
	sign3d.font_size = 128
	sign3d.pixel_size = 0.015
	sign3d.modulate = Color(1.0, 0.85, 0.1)
	sign3d.outline_size = 24
	sign3d.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign3d.position = Vector3(0, LOOP_R * 2.0 + 1.8, 0)
	loop_node.add_child(sign3d)


func _tri(st: SurfaceTool, verts: Array, normals: Array, col: Color) -> void:
	for k in verts.size():
		st.set_color(col)
		st.set_normal(normals[k])
		st.add_vertex(verts[k] + Vector3.UP * 0.03)


func _update_loops(delta: float) -> void:
	var loop_fwd := loop_node.global_transform.basis.z
	for s in cars:
		var car = s["car"]
		var s_val: float = s["loop_s"]
		if s_val < 0.0:
			# Entrée : la voiture franchit la ligne juste avant le looping en roulant vers l'avant
			var lp: Vector3 = loop_node.to_local(car.global_position)
			var car_fwd: Vector3 = -car.global_transform.basis.z
			if lp.z > -(LOOP_R + 5.0) and lp.z < -(LOOP_R + 3.0) and absf(lp.x) < HALF_W \
					and car_fwd.dot(loop_fwd) > 0.5 and car.speed > 3.0:
				s["loop_s"] = 0.0
				s["loop_p0"] = Vector3(lp.x, 0.0, lp.z)
				car.in_loop = true
				car.collision_layer = 0
				car.collision_mask = 0
				car.velocity = Vector3.ZERO
			continue

		car.speed = maxf(car.speed, 22.0)   # assez d'élan pour faire le tour
		s_val += car.speed * delta
		var p0: Vector3 = s["loop_p0"]
		var start := _loop_pos(0.0)
		var approach := p0.distance_to(start)
		var arc := TAU * LOOP_R
		var pos: Vector3
		var fwd: Vector3
		var up := Vector3.UP
		if s_val < approach:
			pos = p0.lerp(start, s_val / approach)
			fwd = (start - p0).normalized()
		elif s_val < approach + arc:
			var u := (s_val - approach) / arc
			pos = _loop_pos(u)
			fwd = _loop_fwd(u)
			up = _loop_up(u)
		else:
			# Sortie du looping : on rend la main au joueur
			s["loop_s"] = -1.0
			car.in_loop = false
			car.collision_layer = 1
			car.collision_mask = 1
			car.global_transform = loop_node.global_transform * Transform3D(Basis(Vector3.UP, PI), _loop_pos(1.0) + Vector3.UP * 0.05)
			continue
		s["loop_s"] = s_val
		var z_axis := -fwd
		var x_axis := up.cross(z_axis).normalized()
		var y_axis := z_axis.cross(x_axis)
		car.global_transform = loop_node.global_transform * Transform3D(Basis(x_axis, y_axis, z_axis), pos)


func _build_bridge(i: int) -> void:
	# Pont de pierre au-dessus de la piste, avec des supporters dessus
	var t := _tangent(i)
	var bridge := Node3D.new()
	bridge.position = center[i]
	bridge.rotation.y = atan2(t.x, t.z)   # axe Z local = sens de la piste
	add_child(bridge)
	var stone := mat(Color(0.62, 0.58, 0.52))
	var dark := mat(Color(0.38, 0.35, 0.32))
	var span := HALF_W * 2.0 + 8.0
	for x in [-(HALF_W + 2.2), HALF_W + 2.2]:
		_visual_box(bridge, Vector3(1.6, 5.5, 4.5), Vector3(x, 2.75, 0), 0.0, stone)   # piliers
	_visual_box(bridge, Vector3(span, 0.7, 5.0), Vector3(0, 5.85, 0), 0.0, dark)        # tablier
	for z in [-2.35, 2.35]:
		_visual_box(bridge, Vector3(span, 0.9, 0.25), Vector3(0, 6.65, z), 0.0, stone)  # rambardes
	# Banderole côté arrivée des voitures
	_visual_box(bridge, Vector3(span * 0.7, 1.0, 0.05), Vector3(0, 5.0, -2.53), 0.0, mat(Color(1.0, 0.8, 0.1), 0.6))
	var banner := Label3D.new()
	banner.text = "ALLEZ ! ALLEZ !"
	banner.font_size = 96
	banner.pixel_size = 0.01
	banner.modulate = Color(0.1, 0.1, 0.1)
	banner.outline_size = 0
	banner.position = Vector3(0, 5.0, -2.57)
	banner.rotation.y = PI
	bridge.add_child(banner)

	# Supporters sur le pont
	var shirts := [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.95), Color(1, 0.8, 0.1), Color(0.2, 0.75, 0.3), Color(0.95, 0.5, 0.1), Color(0.7, 0.3, 0.85)]
	var skins := [Color(1.0, 0.82, 0.68), Color(0.85, 0.62, 0.45), Color(0.55, 0.36, 0.24)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 12:
		var x := -span * 0.5 + 1.5 + k * (span - 3.0) / 11.0
		for z in [-1.4, 1.4]:
			var person := _make_person(shirts[rng.randi() % shirts.size()], skins[rng.randi() % skins.size()])
			person.position = Vector3(x, 6.2, z)
			bridge.add_child(person)
			spectators.append({"node": person, "base_y": 6.2, "phase": rng.randf() * TAU})

	crowd_sources.append([center[i] + Vector3.UP * 6.0, 1.0])


# ---------------------------------------------------------------- Son du public

func _make_crowd_sound() -> AudioStreamWAV:
	# Clameur de foule générée par le code (bruit filtré + "voix" qui ondulent),
	# 4 secondes jouées en boucle : aucun fichier audio nécessaire.
	var rate := 16000
	var n := rate * 4
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var voices: Array = []
	for v in 6:
		voices.append({"f": rng.randf_range(250.0, 650.0), "m": rng.randi_range(1, 6), "ph": rng.randf() * TAU, "acc": 0.0})
	var lp1 := 0.0
	var lp2 := 0.0
	for s in n:
		var tt := float(s) / rate
		var x := rng.randf_range(-1.0, 1.0)
		lp1 += (x - lp1) * 0.3
		lp2 += (lp1 - lp2) * 0.3
		var env := 0.6 + 0.25 * sin(TAU * tt * 0.5) + 0.15 * sin(TAU * tt * 1.25 + 1.0)
		var out := lp2 * 2.2 * env
		for vo in voices:
			var f: float = vo["f"] + 40.0 * sin(TAU * tt * 0.75 + vo["ph"])
			vo["acc"] = fmod(vo["acc"] + TAU * f / rate, TAU)
			var a := maxf(0.0, sin(TAU * tt * vo["m"] / 4.0 + vo["ph"]))
			out += sin(vo["acc"]) * a * a * 0.05
		data.encode_s16(s * 2, int(clampf(out, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


func _setup_crowd_sound() -> void:
	crowd_player = AudioStreamPlayer.new()
	crowd_player.stream = _make_crowd_sound()
	crowd_player.volume_db = -20.0
	add_child(crowd_player)
	crowd_player.play()
	# Écho (réverbération) qui s'active quand une voiture passe sous le pont
	if AudioServer.get_bus_effect_count(0) > 0 and AudioServer.get_bus_effect(0, 0) is AudioEffectReverb:
		reverb = AudioServer.get_bus_effect(0, 0)
	else:
		reverb = AudioEffectReverb.new()
		reverb.room_size = 0.6
		reverb.damping = 0.3
		AudioServer.add_bus_effect(0, reverb, 0)
	reverb.wet = 0.0


func _update_crowd_sound(delta: float) -> void:
	if crowd_player == null:
		return
	var level := 0.12   # rumeur lointaine permanente
	var under := 0.0
	var bridge_pos: Vector3 = center[BRIDGE_IDX]
	for s in cars:
		var cp: Vector3 = s["car"].global_position
		for src in crowd_sources:
			var src_pos: Vector3 = src[0]
			var weight: float = src[1]
			level = maxf(level, clampf(1.0 - cp.distance_to(src_pos) / 45.0, 0.0, 1.0) * weight)
		var dist_bridge := Vector2(cp.x - bridge_pos.x, cp.z - bridge_pos.z).length()
		under = maxf(under, clampf(1.0 - dist_bridge / 8.0, 0.0, 1.0))
	if state == "finished":
		level = 1.0   # ovation pour le vainqueur
	crowd_level = lerpf(crowd_level, level, clampf(3.0 * delta, 0.0, 1.0))
	crowd_player.volume_db = linear_to_db(maxf(crowd_level, 0.001))
	crowd_player.pitch_scale = 1.0 + crowd_level * 0.08
	reverb.wet = lerpf(reverb.wet, under * 0.6, clampf(5.0 * delta, 0.0, 1.0))


func _add_crowds() -> void:
	# Tribunes de supporters qui sautent au bord de la route
	var shirts := [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.95), Color(1, 0.8, 0.1), Color(0.2, 0.75, 0.3), Color(0.95, 0.5, 0.1), Color(0.7, 0.3, 0.85)]
	var skins := [Color(1.0, 0.82, 0.68), Color(0.85, 0.62, 0.45), Color(0.55, 0.36, 0.24)]
	var stand_mat := mat(Color(0.5, 0.5, 0.55))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for idx in [5, 21, 37, 53]:
		var t := _tangent(idx)
		var n := _normal(idx)
		if (center[idx] + n).length() < center[idx].length():
			n = -n   # toujours du côté extérieur du circuit
		var stand_pos := center[idx] + n * (HALF_W + 2.5)
		crowd_sources.append([stand_pos, 0.8])
		_visual_box(self, Vector3(3.0, 0.3, 11.0), stand_pos + Vector3.UP * 0.15, atan2(t.x, t.z), stand_mat)
		for k in 8:
			var p := stand_pos + t * ((k - 3.5) * 1.3) + Vector3.UP * 0.3
			var person := _make_person(shirts[rng.randi() % shirts.size()], skins[rng.randi() % skins.size()])
			person.position = p
			person.rotation.y = atan2(n.x, n.z)   # regarde la piste
			add_child(person)
			spectators.append({"node": person, "base_y": p.y, "phase": rng.randf() * TAU})


func _make_person(shirt: Color, skin: Color) -> Node3D:
	var root := Node3D.new()
	_visual_box(root, Vector3(0.4, 0.6, 0.25), Vector3(0, 0.3, 0), 0.0, mat(Color(0.15, 0.2, 0.4)))
	_visual_box(root, Vector3(0.55, 0.7, 0.35), Vector3(0, 0.95, 0), 0.0, mat(shirt))
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.material = mat(skin)
	head.mesh = sm
	head.position = Vector3(0, 1.55, 0)
	root.add_child(head)
	for x in [-0.37, 0.37]:
		_visual_box(root, Vector3(0.15, 0.6, 0.15), Vector3(x, 1.5, 0), 0.0, mat(skin))   # bras levés
	return root


func _build_finish_line() -> void:
	var t := _tangent(0)
	var line := Node3D.new()
	line.position = center[0]
	line.rotation.y = atan2(t.x, t.z)
	add_child(line)
	var black := mat(Color(0.05, 0.05, 0.05))
	var white := mat(Color(0.95, 0.95, 0.95))
	var squares := 10
	var sq := HALF_W * 2.0 / squares
	for col in squares:
		for row in 2:
			var x := -HALF_W + sq * (col + 0.5)
			var z := (row - 0.5) * sq
			_visual_box(line, Vector3(sq, 0.03, sq), Vector3(x, 0.05, z), 0.0, black if (col + row) % 2 == 0 else white)
	# Portique d'arrivée
	var yellow := mat(Color(1.0, 0.8, 0.1), 0.5)
	for x in [-(HALF_W + 1.0), HALF_W + 1.0]:
		_visual_box(line, Vector3(0.5, 5.0, 0.5), Vector3(x, 2.5, 0), 0.0, yellow)
	_visual_box(line, Vector3(HALF_W * 2.0 + 2.5, 0.8, 0.5), Vector3(0, 5.2, 0), 0.0, yellow)


func _add_boost_pad(i: int) -> void:
	var t := _tangent(i)
	var pad := Area3D.new()
	pad.position = center[i] + Vector3.UP * 0.05
	pad.rotation.y = atan2(t.x, t.z)
	add_child(pad)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(HALF_W * 1.2, 1.5, 3.0)
	cs.shape = sh
	pad.add_child(cs)
	_visual_box(pad, Vector3(HALF_W * 1.2, 0.06, 3.0), Vector3.ZERO, 0.0, mat(Color(0.1, 0.8, 1.0), 2.5))
	pad.body_entered.connect(_on_boost_pad_body_entered)


func _on_boost_pad_body_entered(body: Node3D) -> void:
	if body.has_method("boost"):
		body.boost()


func _add_tree(p: Vector3, s: float, trunk_mat: Material, leaf_mat: Material) -> void:
	var trunk := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.3 * s
	tc.bottom_radius = 0.4 * s
	tc.height = 2.0 * s
	tc.material = trunk_mat
	trunk.mesh = tc
	trunk.position = p + Vector3.UP * s
	add_child(trunk)
	var leaves := MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.top_radius = 0.0
	lc.bottom_radius = 1.8 * s
	lc.height = 4.0 * s
	lc.material = leaf_mat
	leaves.mesh = lc
	leaves.position = p + Vector3.UP * (2.0 * s + 2.0 * s)
	add_child(leaves)


func _spawn_cars() -> void:
	var t0 := _tangent(0)
	var n0 := _normal(0)
	var base := center[0] - t0 * 6.0
	var keys := [[KEY_W, KEY_S, KEY_A, KEY_D], [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]]
	for i in 2:
		var car = CarScript.new()
		car.car_color = COLORS[i]
		car.key_up = keys[i][0]
		car.key_down = keys[i][1]
		car.key_left = keys[i][2]
		car.key_right = keys[i][3]
		car.pad_id = i   # 1re manette -> J1, 2e manette -> J2
		car.touch = touch
		car.touch_prefix = "p%d_" % (i + 1)
		car.style = "sport" if i == 0 else "bug"   # J2 conduit la voiture style Volkswagen
		car.position = base + n0 * (2.5 if i == 0 else -2.5) + Vector3.UP * 0.2
		car.rotation.y = atan2(-t0.x, -t0.z)
		add_child(car)
		cars.append({"car": car, "next": 1, "laps": 0, "loop_s": -1.0, "loop_p0": Vector3.ZERO})


# ---------------------------------------------------------------- Écran partagé

func _make_label(parent: Node, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_screens() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hbox := HBoxContainer.new()
	layer.add_child(hbox)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 4)

	for i in 2:
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hbox.add_child(svc)
		var sv := SubViewport.new()
		sv.world_3d = get_world_3d()   # les deux écrans montrent le même monde
		sv.msaa_3d = Viewport.MSAA_2X
		svc.add_child(sv)
		var cam := Camera3D.new()
		cam.fov = 70.0
		cam.far = 400.0
		sv.add_child(cam)
		cam.current = true
		cams.append(cam)
		var lbl := _make_label(sv, 28)
		lbl.position = Vector2(20, 14)
		lbl.add_theme_color_override("font_color", COLORS[i].lightened(0.35))
		hud_labels.append(lbl)

	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	big_label = _make_label(top, 90)
	big_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_label.add_theme_constant_override("outline_size", 16)
	var help := _make_label(top, 18)
	help.text = "J1 : Z Q S D ou manette 1     J2 : flèches ou manette 2     Manette : RT/A accélérer, LT/B freiner, stick gauche tourner, stick droit caméra     R / Start : recommencer     Échap : quitter"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.anchor_right = 1.0
	help.offset_top = -36.0
	help.offset_bottom = -10.0
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if touch.enabled:
		help.visible = false   # sur téléphone, les boutons à l'écran suffisent


func _update_cameras(delta: float, snap := false) -> void:
	for i in cams.size():
		var car = cars[i]["car"]
		# Joystick droit : gauche/droite = tourner autour de la voiture, haut/bas = hauteur.
		# Quand on le lâche, la caméra revient doucement derrière la voiture.
		var pad: int = car.pad_id
		var rx := Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X)
		var ry := Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y)
		if absf(rx) > 0.2:
			cam_yaw[i] = wrapf(cam_yaw[i] - rx * 3.0 * delta, -PI, PI)
		else:
			cam_yaw[i] = lerp_angle(cam_yaw[i], 0.0, clampf(2.0 * delta, 0.0, 1.0))
		if absf(ry) > 0.2:
			cam_height[i] = clampf(cam_height[i] + ry * 6.0 * delta, 1.5, 9.0)
		var back: Vector3 = car.global_transform.basis.z.rotated(Vector3.UP, cam_yaw[i])
		var target: Vector3 = car.global_position + back * 8.0 + Vector3.UP * cam_height[i]
		if cars[i]["loop_s"] >= 0.0:
			# Pendant le looping : vue de côté, depuis l'intérieur du circuit
			var side := loop_node.global_transform.basis.x
			if (loop_node.global_position + side).length() > loop_node.global_position.length():
				side = -side
			target = loop_node.to_global(Vector3(0, LOOP_R, 0)) + side * 20.0
		if snap:
			cams[i].global_position = target
		else:
			cams[i].global_position = cams[i].global_position.lerp(target, clampf(6.0 * delta, 0.0, 1.0))
		cams[i].look_at(car.global_position + Vector3.UP * 1.0, Vector3.UP)


# ---------------------------------------------------------------- Course

func _physics_process(delta: float) -> void:
	anim_t += delta
	for sp in spectators:
		sp["node"].position.y = sp["base_y"] + absf(sin(anim_t * 6.0 + sp["phase"])) * 0.3

	if state == "countdown":
		countdown -= delta
		if countdown <= 0.0:
			state = "race"
			for s in cars:
				s["car"].can_drive = true
			big_label.text = "GO !"
			go_time = 1.0
		else:
			big_label.text = str(int(ceil(countdown)))
	elif state == "race":
		if go_time > 0.0:
			go_time -= delta
			if go_time <= 0.0:
				big_label.text = ""
		for i in cars.size():
			_check_progress(i)
			if state != "race":
				break

	_update_loops(delta)
	_update_cameras(delta)
	_update_hud()
	_update_crowd_sound(delta)


func _dist_to_next(i: int) -> float:
	var s: Dictionary = cars[i]
	var car: Node3D = s["car"]
	var p: Vector3 = center[checkpoints[s["next"]]]
	return Vector2(car.global_position.x - p.x, car.global_position.z - p.z).length()


func _check_progress(i: int) -> void:
	var s: Dictionary = cars[i]
	if _dist_to_next(i) < HALF_W + 3.0:
		if s["next"] == 0:
			s["laps"] += 1
			if s["laps"] >= LAPS:
				_win(i)
				return
			s["next"] = 1
		else:
			s["next"] = (s["next"] + 1) % checkpoints.size()


func _progress(i: int) -> float:
	var s: Dictionary = cars[i]
	var cpn := checkpoints.size()
	var passed: int = (s["next"] - 1 + cpn) % cpn
	return s["laps"] * cpn + passed - _dist_to_next(i) * 0.001


func _update_hud() -> void:
	var lead := 0 if _progress(0) >= _progress(1) else 1
	for i in cars.size():
		var s: Dictionary = cars[i]
		var car = s["car"]
		var lap: int = mini(s["laps"] + 1, LAPS)
		var txt := "JOUEUR %d   %s\nTour %d / %d\n%d km/h" % [i + 1, "1er" if i == lead else "2e", lap, LAPS, int(absf(car.speed) * 3.6)]
		if s["laps"] == LAPS - 1 and state == "race":
			txt += "\nDERNIER TOUR !"
		if car.boost_time > 0.0:
			txt += "\nTURBO !"
		if s["loop_s"] >= 0.0:
			txt += "\nLOOPING !"
		hud_labels[i].text = txt


func _win(i: int) -> void:
	state = "finished"
	for s in cars:
		s["car"].can_drive = false
	big_label.add_theme_color_override("font_color", COLORS[i].lightened(0.3))
	big_label.text = "JOUEUR %d GAGNE !\n\nR pour rejouer" % (i + 1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := event as InputEventKey
		if k.physical_keycode == KEY_R:
			get_tree().reload_current_scene()
		elif k.physical_keycode == KEY_ESCAPE and not OS.has_feature("web"):
			get_tree().quit()
	elif event is InputEventJoypadButton and event.is_pressed():
		var jb := event as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_START:
			get_tree().reload_current_scene()
