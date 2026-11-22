extends CanvasLayer
## Commandes tactiles à l'écran pour téléphone / tablette.
## Elles n'apparaissent QUE sur mobile : sur ordinateur, rien ne change.
## (Pour les essayer sur PC : Projet > Paramètres du projet > Input Devices >
##  Pointing > "Emulate Touch From Mouse", puis jouer à la souris.)
##
## Utilisation depuis un jeu :
##   touch.add_button("jump", "SAUT", Vector2(0.9, 0.78))   # position en % de l'écran
##   touch.is_pressed("jump")        -> bool
##   touch.use_joystick = true        -> joystick virtuel (moitié gauche) : touch.joystick
##   touch.use_look = true            -> glisser à droite pour la caméra : touch.consume_look()
##   signal button_pressed(id)        -> émis quand un bouton est touché

signal button_pressed(id: String)

const JOY_RADIUS := 90.0

var enabled := false
var buttons: Array = []          # { id, label, pos, radius }
var use_joystick := false
var use_look := false
var joystick := Vector2.ZERO

var _pressed := {}               # id du bouton -> nombre de doigts dessus
var _finger := {}                # index du doigt -> "joy", "look" ou id du bouton
var _joy_active := false
var _joy_center := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_acc := Vector2.ZERO
var _drawer: Node2D


func _ready() -> void:
	layer = 50
	enabled = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") \
			or bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false))
	visible = enabled
	_drawer = Node2D.new()
	add_child(_drawer)
	_drawer.draw.connect(_draw_controls)
	get_viewport().size_changed.connect(_drawer.queue_redraw)


func add_button(id: String, label: String, pos: Vector2, radius := 62.0) -> void:
	buttons.append({"id": id, "label": label, "pos": pos, "radius": radius})
	if _drawer != null:
		_drawer.queue_redraw()


func is_pressed(id: String) -> bool:
	return enabled and int(_pressed.get(id, 0)) > 0


func consume_look() -> Vector2:
	var v := _look_acc
	_look_acc = Vector2.ZERO
	return v


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


func _button_at(p: Vector2) -> String:
	var s := _screen()
	for b in buttons:
		var c: Vector2 = b["pos"] * s
		if p.distance_to(c) <= float(b["radius"]) * 1.2:
			return b["id"]
	return ""


func _press(id: String) -> void:
	_pressed[id] = int(_pressed.get(id, 0)) + 1
	button_pressed.emit(id)


func _release(id: String) -> void:
	_pressed[id] = maxi(int(_pressed.get(id, 0)) - 1, 0)


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			var btn := _button_at(st.position)
			if btn != "":
				_finger[st.index] = btn
				_press(btn)
			elif use_joystick and st.position.x < _screen().x * 0.45:
				_finger[st.index] = "joy"
				_joy_active = true
				_joy_center = st.position
				_joy_pos = st.position
				joystick = Vector2.ZERO
			elif use_look:
				_finger[st.index] = "look"
		else:
			var who: String = _finger.get(st.index, "")
			_finger.erase(st.index)
			if who == "joy":
				_joy_active = false
				joystick = Vector2.ZERO
			elif who != "" and who != "look":
				_release(who)
		_drawer.queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		var who: String = _finger.get(sd.index, "")
		if who == "joy":
			_joy_pos = sd.position
			joystick = ((_joy_pos - _joy_center) / JOY_RADIUS).limit_length(1.0)
			_drawer.queue_redraw()
		elif who == "look":
			_look_acc += sd.relative
		elif who != "":
			# glisser le doigt d'un bouton à l'autre (pratique pour gauche/droite)
			var btn := _button_at(sd.position)
			if btn != "" and btn != who:
				_release(who)
				_finger[sd.index] = btn
				_press(btn)
				_drawer.queue_redraw()
		get_viewport().set_input_as_handled()


func _draw_controls() -> void:
	var s := _screen()
	var font := ThemeDB.fallback_font
	for b in buttons:
		var c: Vector2 = b["pos"] * s
		var r: float = b["radius"]
		var on := is_pressed(b["id"])
		_drawer.draw_circle(c, r, Color(1, 1, 1, 0.38 if on else 0.16))
		_drawer.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.65), 3.0)
		var fs := 26
		var label: String = b["label"]
		var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		_drawer.draw_string(font, c + Vector2(-size.x * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	if use_joystick:
		var base := _joy_center if _joy_active else Vector2(s.x * 0.13, s.y * 0.74)
		_drawer.draw_circle(base, JOY_RADIUS, Color(1, 1, 1, 0.12))
		_drawer.draw_arc(base, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		_drawer.draw_circle(base + joystick * JOY_RADIUS, 38.0, Color(1, 1, 1, 0.4))
