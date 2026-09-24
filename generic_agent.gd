@tool
class_name GenericCliAgent
extends BaseAgent

## Generic CLI Agent adapter that allows executing any CLI command tool directly.

const BaseAgent = preload("res://addons/cli_agent_bridge/base_agent.gd")

func get_id() -> String:
	return "generic"

func get_name() -> String:
	return "Generic CLI"

func get_short_name() -> String:
	return "CLI Agent"

func get_description() -> String:
	return "Executes prompts directly with any custom CLI tool or script"

func get_default_binary() -> String:
	return ""

func get_path_placeholder() -> String:
	return "Enter executable command or full path (e.g. aider, claude, ollama)"

func build_run_command(bin_path: String, full_prompt: String, _model_id: String, _effort: String, _session_id: String, _continue_session: bool) -> Dictionary:
	if OS.get_name() == "Windows":
		var escaped_bin = bin_path.replace("'", "''")
		var escaped_prompt = full_prompt.replace("'", "''")
		var ps_cmd = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & '%s' '%s' *>&1" % [escaped_bin, escaped_prompt]
		return {
			"exec": "powershell.exe",
			"args": ["-NoProfile", "-Command", ps_cmd]
		}
	else:
		var escaped_sh_prompt = full_prompt.replace("'", "'\\''")
		var sh_cmd = "'%s' '%s' 2>&1" % [bin_path, escaped_sh_prompt]
		return {
			"exec": "sh",
			"args": ["-c", sh_cmd]
		}
