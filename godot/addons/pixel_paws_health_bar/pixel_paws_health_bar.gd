@tool
@icon("icon.svg")
class_name PixelPawsHealthBar
extends Control
 
# needs a config with frame.png of a pack, everything else is loaded from the same folder
# (health/, heart/, mana/ next to frame.png)
 
#region Const/Vars/Signals
 
const SEGMENTS: int = 5
const FPS: float = 20.0 # all packs are exported with 50ms per frame: 1000 / 50 = 20
const FOLDER_HEALTH: String = "health"
const FOLDER_HEART: String = "heart"
const FOLDER_MANA: String = "mana"
 
signal health_changed(new_value: int, old_value: int)
signal mana_changed(new_value: float, old_value: float)
 
# one image strip + the frame we currently show from it
class DrawLayer:
	var tex: Texture2D
	var frames: int = 1
	var frame: int = 0
 
## frame.png and settings of the health bar
@export var config: PixelPawsHealthBarConfig:
	set(value):
		if config == value:
			return
		if config and config.changed.is_connected(_on_config_changed):
			config.changed.disconnect(_on_config_changed)
		config = value
		if config:
			config.changed.connect(_on_config_changed)
		update_minimum_size()
		update_configuration_warnings()
		if is_node_ready():
			_initialize()
 
## 1 image pixel = pixel_scale screen pixels
@export_range(1, 32)
var pixel_scale: int = 1:
	set(value):
		pixel_scale = maxi(value, 1)
		update_minimum_size()
		queue_redraw()
 
@export_category("Health")
@export_range(0, 10)
var health: int = 10:
	set = set_health
 
@export_category("Mana")
@export_range(0.0, 1.0)
var mana: float = 1.0:
	set = set_mana
 
var _frame_tex: Texture2D # the frame.png we are currently built for
var _frame_size: Vector2i = Vector2i.ZERO
var _asset_dir: String = ""
var _mana_steps: int = 1
var _mana_ghost: DrawLayer = DrawLayer.new()
var _mana: DrawLayer = DrawLayer.new()
var _segs: Array[DrawLayer] = [DrawLayer.new(), DrawLayer.new(), DrawLayer.new(), DrawLayer.new(), DrawLayer.new()]
var _heart: DrawLayer = DrawLayer.new()
var _seg_token: Array[int] = [0, 0, 0, 0, 0]
var _seg_busy: Array[bool] = [false, false, false, false, false]
# one shared clock for all segment idle loops -> the rhythm stays intact when segments are lost and healed
var _seg_idle_clock: float = 0.0
var _seg_idle_beat: Array[int] = [0, 0, 0, 0, 0] # last beat each segment has handled
var _heart_token: int = 0
var _heart_busy: bool = false
var _display_heart_low: bool = false
var _ghost_value: float = 1.0
var _ghost_tween: Tween
var _delta_sum_low_health: float = 0.0
var _delta_sum_mana: float = 0.0
var _is_ready: bool = false
var _tex_cache: Dictionary = {}
var _exists_cache: Dictionary = {}
 
#endregion
 
#region Setup/Loop
 
func _init() -> void:
	# pixel art -> no blurry filtering, and don't eat the clicks of buttons below
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
 
 
func _ready() -> void:
	_initialize()
 
 
func _get_minimum_size() -> Vector2:
	if config == null or config.frame_texture == null:
		return Vector2.ZERO
	return Vector2(config.frame_texture.get_size()) * pixel_scale
 
 
func _get_configuration_warnings() -> PackedStringArray:
	if config == null:
		return ["Needs a PixelPawsHealthBarConfig."]
	if config.frame_texture == null:
		return ["Set frame_texture in the config (frame.png of the health bar pack)."]
	return []
 
 
func _draw() -> void:
	if not _is_ready:
		return
	var dst: Rect2 = Rect2(Vector2.ZERO, Vector2(_frame_size * pixel_scale))
	draw_texture_rect(_frame_tex, dst, false)
 
	# same order as the layers in aseprite: ghost, mana, seg 0-4, heart on top
	for layer: DrawLayer in [_mana_ghost, _mana] + _segs + [_heart]:
		if layer.tex == null:
			continue
		var src: Rect2 = Rect2(Vector2(layer.frame * _frame_size.x, 0), Vector2(_frame_size))
		draw_texture_rect_region(layer.tex, dst, src)
 
 
func _process(delta: float) -> void:
	if not _is_ready or health <= 0:
		return
	_delta_sum_low_health += delta
	var low: bool = _is_low()
	if low and not config.loop_low_animation:
		# low animation was played once and holds its last frame
		pass
	elif config.idle_animation and _delta_sum_low_health >= (config.low_health_animation_interval if low else config.idle_interval):
		# only reset when it really plays: if the heart is still busy (hit, previous loop),
		# the loop starts right after instead of being skipped
		if not _heart_busy:
			_delta_sum_low_health = 0.0
			_play_heart("heart_low.png" if low else "heart_beat.png")
	_process_segment_idle(delta)
	_process_mana_regeneration(delta)
 
 
func _process_segment_idle(delta: float) -> void:
	if not config.segment_idle_animation:
		return
	_seg_idle_clock += delta
	var interval: float = maxf(config.segment_idle_interval, 0.1)
	for i: int in SEGMENTS:
		# every segment runs on the same clock, shifted by its stagger offset; a segment that is
		# empty or busy at its beat just skips it and stays in sync for the next one
		var t: float = _seg_idle_clock - config.segment_idle_stagger * i
		if t < interval:
			continue
		var beat: int = floori(t / interval)
		if beat == _seg_idle_beat[i]:
			continue
		_seg_idle_beat[i] = beat
		var part: String = _part(health, i)
		if part == "empty" or _seg_busy[i]:
			continue
		var rel: String = "%s/seg%d_%s_idle.png" % [FOLDER_HEALTH, i, part]
		if _has_strip(rel):
			_play_segment(i, rel, part)
 
 
func _process_mana_regeneration(delta: float) -> void:
	if mana == 1.0:
		return
	_delta_sum_mana += delta
	if _delta_sum_mana >= config.mana_regeneration_interval:
		_delta_sum_mana -= config.mana_regeneration_interval
		restore_mana(config.mana_regeneration_value)
 
#endregion
 
#region Public API
 
func set_health(value: int) -> void:
	value = clampi(value, 0, SEGMENTS * 2)
	var old: int = health
	health = value
	if health <= 0:
		mana = 0.0
	if not _is_ready or value == old:
		return
 
	for i: int in SEGMENTS:
		var a: String = _part(old, i)
		var b: String = _part(value, i)
		if a != b:
			_animate_segment(i, a, b)
 
	var die_rel: String = "%s/heart_die.png" % FOLDER_HEART
	var low_hit_rel: String = "%s/heart_low_hit.png" % FOLDER_HEART
	var dead_low_rel: String = "%s/heart_dead_to_low.png" % FOLDER_HEART
	if value < old and value > 0:
		if _display_heart_low and _is_low() and _has_strip(low_hit_rel):
			# optional: hit while the low heart is held, keeps the low look
			_play_heart("heart_low_hit.png")
		else:
			_play_heart("heart_hit.png")
	elif value <= 0 and old > 0 and _has_strip(die_rel):
		# optional: transition into the dead heart
		_play_heart("heart_die.png")
	elif value > 0 and old <= 0 and not config.loop_low_animation and _is_low() and _has_strip(dead_low_rel):
		# optional: revived with low health, ends on the held low heart
		_display_heart_low = true
		_play_heart("heart_dead_to_low.png")
	elif value > 0 and old <= 0 and _has_strip(die_rel):
		# revived -> play it backwards
		_play_heart("heart_die.png", true)
	elif not _heart_busy:
		_set_heart_idle()
	health_changed.emit(value, old)
 
 
func set_mana(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	var old: float = mana
	mana = value
	if not _is_ready or value == old:
		return
	_set_strip_frame(_mana, value)
 
	if value < old:
		# mana used -> pause regeneration for a moment
		_delta_sum_mana = -abs(config.mana_regen_pause)
		if _ghost_tween and _ghost_tween.is_valid():
			_ghost_tween.kill()
 
	if not _ghost_tween or not _ghost_tween.is_valid():
		if config.enable_mana_ghost and value < _ghost_value:
			# ghost stays for 0.35s, then drains down in 0.45s
			_ghost_tween = create_tween()
			_ghost_tween.tween_interval(0.35)
			_ghost_tween.tween_method(_set_ghost, _ghost_value, value, 0.45)
		else:
			_set_ghost(value)
	mana_changed.emit(value, old)
 
 
func damage(points: int = 1) -> void:
	set_health(health - points)
 
 
func heal(points: int = 1) -> void:
	set_health(health + points)
 
 
func use_mana(amount: float) -> bool:
	if amount > mana:
		return false
	set_mana(mana - amount)
	return true
 
 
func restore_mana(amount: float) -> void:
	set_mana(mana + amount)
 
#endregion
 
#region Private functions
 
func _initialize() -> void:
	# also called again when the config or its frame_texture is swapped
	_clear()
	if config == null or config.frame_texture == null:
		return
	_frame_tex = config.frame_texture
	_asset_dir = _frame_tex.resource_path.get_base_dir()
	_frame_size = Vector2i(_frame_tex.get_size())
	_set_layer(_mana_ghost, _tex("%s/mana_ghost_steps.png" % FOLDER_MANA))
	_set_layer(_mana, _tex("%s/mana_steps.png" % FOLDER_MANA))
	_mana_steps = _mana.frames - 1 # frame 0 = empty
	_is_ready = true
 
	for i: int in SEGMENTS:
		_show_segment(i, _part(health, i))
	_reset_segment_idle()
	_display_heart_low = not config.loop_low_animation and _is_low()
	_ghost_value = mana
	_set_strip_frame(_mana, mana)
	_set_strip_frame(_mana_ghost, mana)
	_set_heart_idle()
	# start the idle loop right away instead of showing a still heart for the first interval
	_delta_sum_low_health = INF
 
 
func _clear() -> void:
	_is_ready = false
	# bump all tokens -> running animations see they're outdated and stop
	_heart_token += 1
	for i: int in SEGMENTS:
		_seg_token[i] += 1
	_heart_busy = false
	for i: int in SEGMENTS:
		_seg_busy[i] = false
	if _ghost_tween and _ghost_tween.is_valid():
		_ghost_tween.kill()
	for layer: DrawLayer in [_mana_ghost, _mana] + _segs + [_heart]:
		_set_layer(layer, null)
	_tex_cache.clear()
	_exists_cache.clear()
	_frame_tex = null
	queue_redraw()
 
 
func _on_config_changed() -> void:
	if not is_node_ready():
		return
	update_minimum_size()
	update_configuration_warnings()
	if config.frame_texture != _frame_tex:
		# other pack -> build everything new
		_initialize()
		return
	if not _is_ready:
		return
	_display_heart_low = not config.loop_low_animation and _is_low()
	_heart_token += 1
	_heart_busy = false
	_set_heart_idle()
 
 
# 2 points per segment: 10 = all full, 9 = last one half, ...
func _part(h: int, i: int) -> String:
	if h >= (i + 1) * 2:
		return "full"
	if h == i * 2 + 1:
		return "half"
	return "empty"
 
 
func _animate_segment(i: int, a: String, b: String) -> void:
	# bumps the token -> also cancels a running idle loop of this segment
	await _play_segment(i, "%s/seg%d_%s_to_%s.png" % [FOLDER_HEALTH, i, a, b], b)
 
 
func _play_segment(i: int, rel: String, end_part: String) -> void:
	_seg_token[i] += 1
	var token: int = _seg_token[i]
	_seg_busy[i] = true
	await _run_strip(_segs[i], _tex(rel), func() -> bool: return token == _seg_token[i])
	if token == _seg_token[i]:
		_seg_busy[i] = false
		_show_segment(i, end_part)
 
 
func _reset_segment_idle() -> void:
	# segment i first plays at interval + stagger * i -> they start one after another
	_seg_idle_clock = 0.0
	for i: int in SEGMENTS:
		_seg_busy[i] = false
		_seg_idle_beat[i] = 0
 
 
func _show_segment(i: int, part: String) -> void:
	# there is no "empty" image, the frame just shows through
	_set_layer(_segs[i], null if part == "empty" else _tex("%s/seg%d_%s.png" % [FOLDER_HEALTH, i, part]))
 
 
func _play_heart(path: String, reverse: bool = false) -> void:
	_heart_token += 1
	var token: int = _heart_token
	_heart_busy = true
	await _run_strip(_heart, _tex("%s/%s" % [FOLDER_HEART, path]), func() -> bool: return token == _heart_token, reverse)
	if token == _heart_token:
		_heart_busy = false
		_set_heart_idle()
 
 
func _is_low() -> bool:
	var threshold: int = config.low_health_threshold
	return threshold > 0 and health > 0 and health <= threshold
 
 
func _set_heart_idle() -> void:
	if not _is_ready:
		return
	if health <= 0:
		_display_heart_low = false
		_heart_token += 1
		_heart_busy = false
		_set_layer(_heart, _tex("%s/heart_dead.png" % FOLDER_HEART))
		return
 
	if not config.loop_low_animation:
		var low: bool = _is_low()
		if low and not _display_heart_low:
			_display_heart_low = true
			_play_heart("heart_low.png")
			return
		if not low and _display_heart_low:
			# healed -> play it backwards
			_display_heart_low = false
			_play_heart("heart_low.png", true)
			return
		if low:
			# hold the last frame of the low animation
			_set_layer(_heart, _tex("%s/heart_low.png" % FOLDER_HEART), -1)
			return
	_set_layer(_heart, _tex("%s/heart_idle.png" % FOLDER_HEART))
 
 
# f = -1 -> last frame
func _set_layer(layer: DrawLayer, tex: Texture2D, f: int = 0) -> void:
	layer.tex = tex
	layer.frames = 1
	if tex and _frame_size.x > 0:
		@warning_ignore("integer_division")
		layer.frames = maxi(1, tex.get_width() / _frame_size.x)
	layer.frame = layer.frames - 1 if f < 0 else clampi(f, 0, layer.frames - 1)
	queue_redraw()
 
 
func _run_strip(layer: DrawLayer, tex: Texture2D, still_valid: Callable, reverse: bool = false) -> void:
	_set_layer(layer, tex)
	var n: int = layer.frames
	# frames are timed against the summed game time since the start, so the strip runs at
	# 20 fps on average (one timer per frame overshoots to the next rendered frame and the
	# error adds up); game time keeps Engine.time_scale and pausing working
	var elapsed: float = 0.0
	for i: int in n:
		if not still_valid.call():
			return
		layer.frame = n - 1 - i if reverse else i
		queue_redraw()
		var next_t: float = (i + 1) / FPS - 0.001 # tolerance for float rounding of delta
		while elapsed < next_t:
			await get_tree().process_frame
			if not still_valid.call():
				return
			elapsed += get_process_delta_time()
 
 
func _set_ghost(v: float) -> void:
	_ghost_value = v
	_set_strip_frame(_mana_ghost, v)
 
 
func _set_strip_frame(layer: DrawLayer, v: float) -> void:
	layer.frame = clampi(roundi(v * _mana_steps), 0, layer.frames - 1)
	queue_redraw()
 
 
func _has_strip(rel: String) -> bool:
	# optional strips: older packs don't have them
	if not _exists_cache.has(rel):
		_exists_cache[rel] = ResourceLoader.exists(_asset_dir.path_join(rel))
	return _exists_cache[rel]
 
 
func _tex(rel: String) -> Texture2D:
	if not _tex_cache.has(rel):
		_tex_cache[rel] = load(_asset_dir.path_join(rel))
	return _tex_cache[rel]
 
#endregion
