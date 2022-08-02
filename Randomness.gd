extends Node2D
class_name Randomness

var _noise = OpenSimplexNoise.new()
var _random = RandomNumberGenerator.new()


func _ready() -> void:
	pass
	
func get_random_int(minimum: int, maximum: int) -> int:
	_random.randomize()
	return _random.randi_range(minimum, maximum)


func get_random_float(minimum: float, maximum: float) ->float:
	_random.randomize()
	return _random.randf_range(minimum, maximum)


func get_random_noise(seed_value: int, octaves: int, period: float, persistence: float, iterations: int):
	for iteration in iterations:
		return(_noise.get_noise1(iteration))

#
#
## Configure the OpenSimplexNoise instance.
#	_noise.seed = randi()
#	_noise.octaves = 4
#	_noise.period = 20.0
#	_noise.persistence = 0.8
#
#	for i in 100:
#		# Prints a slowly-changing series of floating-point numbers
#		# between -1.0 and 1.0.
#		print(_noise.get_noise_1d(i))
