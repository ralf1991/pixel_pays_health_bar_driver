extends Node2D

const HEALTH: String = "ff6b5a"
const MANA: String = "57b3ff"
const WARN: String= "ffd25a"

@onready var bar: PixelPawsHealthBar = %PixelPawsHealthBar
@onready var status: RichTextLabel = %Status
@onready var damage_button: Button = %DamageButton
@onready var heal_button: Button = %HealButton
@onready var mana_button: Button = %ManaButton

func _ready() -> void:
	damage_button.pressed.connect(_damage)
	heal_button.pressed.connect(_heal)
	mana_button.pressed.connect(_use_mana)
	bar.health_changed.connect(func(_new: int, _old: int) -> void: _update_status())
	bar.mana_changed.connect(func(_new: float, _old: float) -> void: _update_status())
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_KP_1:
				_flash(damage_button)
				_damage()
			KEY_2, KEY_KP_2:
				_flash(heal_button)
				_heal()
			KEY_3, KEY_KP_3:
				_flash(mana_button)
				_use_mana()


func _damage() -> void:
	bar.damage(3)


func _heal() -> void:
	bar.heal(4)


func _use_mana() -> void:
	bar.use_mana(0.2)


func _update_status() -> void:
	var text: String = "[color=#%s]HEALTH %d/10[/color]    [color=#%s]MANA %d%%[/color]" % [HEALTH, bar.health, MANA, roundi(bar.mana * 100.0)]
	status.text = "[center]%s[/center]" % text


func _flash(button: Button) -> void:
	button.toggle_mode = true
	button.set_pressed_no_signal(true)
	await get_tree().create_timer(0.12).timeout
	button.set_pressed_no_signal(false)
	button.toggle_mode = false
