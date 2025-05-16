extends AudioStreamPlayer3D

func _ready():
	play()
	# Start checking when the sound ends
	set_process(true)

func _process(_delta):
	if not playing:
		play()
