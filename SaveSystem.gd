extends Node2D


func _ready():
	GlobalSignals.connect("request_save", Callable(self, "save_game"))
	GlobalSignals.connect("request_load", Callable(self, "load_game"))


func save_game():
	var save_file = FileAccess.open("user://saves/.save", FileAccess.WRITE)
	if not save_file:
		print("Failed to open save file for writing.")
		return
	var save_nodes = get_tree().get_nodes_in_group("persists")
	for node in save_nodes:
		if node.scene_file_path.is_empty():
			print("Node '%s' is not currently loaded, so it shouldn't be saved. Skipping." % node.name)
			continue

		if !node.has_method("save"):
			print("Node '%s' does not have a save() function. Skipping." % node.name)
			continue

		var node_data = node.call("save")
		print("Object being saved: ", node.name)
		save_file.store_line(JSON.stringify(node_data))


func load_game():
	print("Trying to load a save.")
	if not FileAccess.file_exists("user://saves/.save"):
		return

	var save_nodes = get_tree().get_nodes_in_group("persists")
	for node in save_nodes:
		node.queue_free()

	var save_file = FileAccess.open("user://saves/.save", FileAccess.READ)
	if not save_file:
		print("Failed to open save file for reading.")
		return
	while save_file.get_position() < save_file.get_length():
		var test_json_conv = JSON.new()
		test_json_conv.parse(save_file.get_line())
		var node_data = test_json_conv.get_data()

		var new_object = load(node_data["filename"]).instantiate()
		get_node(node_data["parent"]).add_child(new_object)
		new_object.position = Vector2(node_data["pos_x"], node_data["pos_y"])

		for i in node_data.keys():
			if i == "filename" or i == "parent" or i == "pos_x" or i == "pos_y":
				continue
			new_object.set(i, node_data[i])
