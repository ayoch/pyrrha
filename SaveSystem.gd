extends Node2D


func _ready():
	GlobalSignals.connect("request_save", self, "save_game")
	GlobalSignals.connect("request_load", self, "load_game")

#
#func handle_save_requested():
#	print("Trying to save the game.")
#	save_game()


func save_game():
	var save_game = File.new()
	save_game.open("res://saves/.save", File.WRITE)
	var save_nodes = get_tree().get_nodes_in_group("persists")
	for node in save_nodes:
		if node.filename.empty():
			print("Node '%s' is not currently loaded, so it shouldn't be saved. Skipping." % node.name)
			continue
			
		if !node.has_method("save"):
			print("Node '%s' does not have a save() function. Skipping." % node.name)
			continue
			
		# Call the node's save function.
		var node_data = node.call("save")
		print("Object being saved: ", node.name)

		# Store the save dictionary as a new line in the save file.
		save_game.store_line(to_json(node_data))
	save_game.close()


func load_game():
	print("Trying to load a save.")
	var save_game = File.new()
	if not save_game.file_exists("res://saves/.save"):
		return 

	var save_nodes = get_tree().get_nodes_in_group("persists")
	for node in save_nodes:
		node.queue_free()

	# Load the file line by line and process that dictionary to restore
	# the object it represents.
	save_game.open("res://saves/.save", File.READ)
	while save_game.get_position() < save_game.get_len():
		# Get the saved dictionary from the next line in the save file
		var node_data = parse_json(save_game.get_line())

		# Firstly, we need to create the object and add it to the tree and set its position.
		var new_object = load(node_data["filename"]).instance()
		get_node(node_data["parent"]).add_child(new_object)
		new_object.position = Vector2(node_data["pos_x"], node_data["pos_y"])

		# Now we set the remaining variables.
		for i in node_data.keys():
			if i == "filename" or i == "parent" or i == "pos_x" or i == "pos_y":
				continue
			new_object.set(i, node_data[i])

	save_game.close()
