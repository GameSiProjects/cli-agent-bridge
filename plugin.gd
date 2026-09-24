@tool
extends EditorPlugin

var dock: Control
var bottom_btn: Button

func _enter_tree() -> void:
	dock = preload("res://addons/cli_agent_bridge/dock.tscn").instantiate()
	dock.editor_plugin = self
	bottom_btn = add_control_to_bottom_panel(dock, "CLI Agent")
	
	var icon_path = "res://addons/cli_agent_bridge/icon.svg"
	if ResourceLoader.exists(icon_path):
		var icon = load(icon_path)
		if bottom_btn and icon is Texture2D:
			bottom_btn.icon = icon

func _exit_tree() -> void:
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
		dock = null
