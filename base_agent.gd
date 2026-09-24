@tool
class_name BaseAgent
extends RefCounted

## Base class for CLI AI agents in Agent Bridge.
## Extend this class to support other CLI agents (e.g. Claude CLI, Aider, Ollama, etc.)

# --- Identity ---

func get_id() -> String:
	return "base"

func get_name() -> String:
	return "Base Agent"

func get_short_name() -> String:
	return "Agent"

func get_description() -> String:
	return ""

# --- Binary & Path Resolution ---

func get_default_binary() -> String:
	return ""

func get_path_placeholder() -> String:
	var def = get_default_binary()
	if def.is_empty():
		return "Executable command or full path"
	return "%s (or full path to executable)" % def

func is_binary_available(cmd_name: String) -> bool:
	if cmd_name.is_empty():
		return false
	if FileAccess.file_exists(cmd_name):
		return true
	var out: Array = []
	var exit_code = -1
	if OS.get_name() == "Windows":
		exit_code = OS.execute("where.exe", [cmd_name], out)
	else:
		exit_code = OS.execute("which", [cmd_name], out)
	return exit_code == 0 and not out.is_empty() and not str(out[0]).strip_edges().is_empty()

# --- Installation ---

func can_install() -> bool:
	return false

func get_install_button_text() -> String:
	return "⬇️ Install"

func get_install_tooltip() -> String:
	return "Install agent CLI automatically"

func get_install_command() -> Dictionary:
	# Returns { "exec": String, "args": Array }
	return {}

func get_install_start_bbcode() -> String:
	return ""

func get_install_success_bbcode() -> String:
	return "[color=green]Agent installed successfully![/color]\n"

# --- Models & Reasoning Effort ---

func supports_models() -> bool:
	return false

func supports_effort() -> bool:
	return false

func get_default_models() -> Array[Dictionary]:
	return []

func build_fetch_models_command(_bin_path: String) -> Dictionary:
	# Returns { "exec": String, "args": Array }
	return {}

func parse_models_output(_raw_output: String) -> Array[Dictionary]:
	# Returns Array of { "id": String, "name": String, "efforts": Array[String], "default_effort": String }
	return []

# --- Quota ---

func supports_quota() -> bool:
	return false

func build_fetch_quota_command(_bin_path: String) -> Dictionary:
	# Returns { "exec": String, "args": Array }
	return {}

func parse_quota_output(_raw_output: String) -> Dictionary:
	return {}

func format_quota_display(_cached_quota: Dictionary, _selected_model_id: String) -> Dictionary:
	# Returns { "text": String, "tooltip": String, "color": Color }
	return {
		"text": "⚡ --%",
		"tooltip": "Remaining quota",
		"color": Color(0.7, 0.7, 0.7)
	}

# --- Execution ---

func build_run_command(_bin_path: String, _full_prompt: String, _model_id: String, _effort: String, _session_id: String, _continue_session: bool) -> Dictionary:
	# Returns { "exec": String, "args": Array }
	return {}

func get_prompt_placeholder() -> String:
	return "Ask %s... (Ctrl+Enter to send)" % get_short_name()

func get_agent_tag(model_name: String, effort_label: String) -> String:
	if not effort_label.is_empty() and effort_label != "N/A (Thinking)" and effort_label != "Default":
		return "%s (%s • %s)" % [get_short_name(), model_name, effort_label]
	elif not model_name.is_empty() and model_name != "None" and model_name != "Default":
		return "%s (%s)" % [get_short_name(), model_name]
	return get_short_name()

# --- History & Sessions ---

func supports_history() -> bool:
	return false

func get_history_folder_path() -> String:
	return ""

func scan_conversations(_history_path: String) -> Array[Dictionary]:
	# Returns Array of { "id": String, "title": String, "mtime": int, "time_str": String, "full_time": String, "transcript_path": String, "turns": int }
	return []

func render_transcript(_conv: Dictionary) -> String:
	# Returns BBCode string to display in output log
	return ""

func detect_newest_conversation_id() -> String:
	return ""

func clean_prompt_title(raw_content: String) -> String:
	return raw_content.strip_edges()

func extract_clean_user_message(raw_content: String) -> String:
	return raw_content.strip_edges()

# --- Status & Log Previews ---

func get_ready_message(_bin_path: String, model_name: String, effort_label: String) -> String:
	var eff_text = " • " + effort_label + " Effort" if not effort_label.is_empty() and effort_label != "N/A (Thinking)" and effort_label != "Default" else ""
	var model_desc = (" Current agent: [b]%s%s[/b]." % [model_name, eff_text]) if supports_models() and not model_name.is_empty() and model_name != "None" else ""
	return "[color=gray]%s ready.%s Type a prompt below or click a preset above to begin.[/color]\n" % [get_name(), model_desc]

func get_not_found_bbcode(bin_path: String) -> String:
	return "[color=orange]⚠️ %s ('%s') is not found on your system PATH.[/color]\n" % [get_name(), bin_path]
