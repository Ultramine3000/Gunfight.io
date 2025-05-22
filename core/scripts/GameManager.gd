# File: GameManager.gd
extends Node
class_name GameManager

# Singleton to manage game state and modular loading

var factions = {}
var units = {}
var buildings = {}
var abilities = {}

var current_faction_id = ""

# Path to modular data folders
const FACTION_PATH := "res://data/factions/"
const UNIT_PATH := "res://data/units/"
const BUILDING_PATH := "res://data/buildings/"
const ABILITY_PATH := "res://data/abilities/"

func _ready():
	load_all_data()

func load_all_data():
	factions = load_data_from_dir(FACTION_PATH)
	units = load_data_from_dir(UNIT_PATH)
	buildings = load_data_from_dir(BUILDING_PATH)
	abilities = load_data_from_dir(ABILITY_PATH)
	print("[GameManager] All data loaded.")

func load_data_from_dir(path: String) -> Dictionary:
	var result = {}
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var resource_path = path + file_name
				var res = load(resource_path)
				if res:
					result[file_name.get_basename()] = res
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		print("[Error] Could not open directory: ", path)
	return result

func get_unit_data(unit_id: String):
	return units.get(unit_id, null)

func get_faction_data(faction_id: String):
	return factions.get(faction_id, null)

func set_current_faction(faction_id: String):
	if factions.has(faction_id):
		current_faction_id = faction_id
	else:
		push_error("Invalid faction ID: %s" % faction_id)
