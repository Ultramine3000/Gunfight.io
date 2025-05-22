extends Resource
class_name CombatUnitData

@export var unit_icon: Texture2D
@export var unit_name: String
@export var health: int
@export var move_speed: float
@export var cost: int
@export var weapon_type: String
@export var abilities: Array[String]
@export_range(4, 7) var squad_size: int = 5
@export_range(0.0, 1.0, 0.01) var short_range_accuracy: float = 0.85
@export_range(0.0, 1.0, 0.01) var medium_range_accuracy: float = 0.65
@export_range(0.0, 1.0, 0.01) var long_range_accuracy: float = 0.4
@export_range(10.0, 50.0, 1.0) var vision_range: float = 20.0
