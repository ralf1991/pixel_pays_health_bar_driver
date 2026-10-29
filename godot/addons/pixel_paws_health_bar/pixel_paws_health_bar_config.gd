@tool
@icon("icon.svg")
class_name PixelPawsHealthBarConfig
extends Resource

# settings for PixelPawsHealthBar, every bar needs one
# save as .tres if several bars should share the same settings

@export_category("Setup")
## frame.png of the health bar pack, the other images are loaded from the same folder
@export var frame_texture: Texture2D:
	set(v):
		frame_texture = v
		emit_changed()

@export_category("Health")
## enable idle animation, does not affect animations on damage
@export var idle_animation: bool = true:
	set(v):
		idle_animation = v
		emit_changed()
@export var idle_interval: float = 1.6

## specifies when the low-health animation starts; 0 to deactivate
@export var low_health_threshold: int = 2:
	set(v):
		low_health_threshold = maxi(v, 0)
		emit_changed()

## true: heart_low.png loops every low_health_animation_interval
## false: heart_low.png plays once, holds its last frame and plays backwards when healed above the threshold
@export var loop_low_animation: bool = true:
	set(v):
		loop_low_animation = v
		emit_changed()
@export var low_health_animation_interval: float = 0.5

@export_category("Mana")
@export var mana_regeneration_interval: float = 2.0
@export var mana_regeneration_value: float = 0.05
@export var enable_mana_ghost: bool = true
## seconds without regeneration after mana was used
@export var mana_regen_pause: float = 1.0
