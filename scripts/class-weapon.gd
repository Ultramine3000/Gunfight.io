extends Resource
class_name Weapon

enum WEAPON_TYPES {PISTOL, RIFLE}

@export_category("BaseWeapon")
@export var name : String = ""
@export var weapon_type : WEAPON_TYPES
@export var bullet_tscn : PackedScene
@export var ammo_icon : Texture 
@export_range(0.0, 10.0) var cooldown := 0.2  # Rate of fire
@export_range(0.0, 10.0) var reload_time := 1.5
@export_range(1, 1000) var max_ammo := 10
var current_ammo := 0

@export_category("Weapon Sounds")  # Sounds
@export var fire_sound: AudioStream  
@export var reload_sound: AudioStream  
@export var draw_sound: AudioStream
@export var holster_sound: AudioStream
