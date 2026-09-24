@tool
class_name AntigravityAgent
extends BaseAgent

## Antigravity CLI (agy) Agent adapter for Agent Bridge.
## Wraps all Antigravity-specific execution, model discovery, quota checking,
## installation, and conversation history parsing.

const BaseAgent = preload("res://addons/cli_agent_bridge/base_agent.gd")

# --- Identity ---

func get_id() -> String:
	return "antigravity"

func get_name() -> String:
	return "Antigravity (agy)"

func get_short_name() -> String:
	return "Antigravity"

func get_description() -> String:
	return "Dedicated bridge to Google's Antigravity CLI (agy)"

# --- Binary & Path Resolution ---

func get_default_binary() -> String:
	var localapp = OS.get_environment("LOCALAPPDATA")
	if not localapp.is_empty():
		var direct_exe = (localapp + "/agy/bin/agy.exe").replace("\\", "/")
		if FileAccess.file_exists(direct_exe):
			return direct_exe
	return "agy"

func is_binary_available(cmd_name: String) -> bool:
	if cmd_name.is_empty():
		return false

	if FileAccess.file_exists(cmd_name):
		return true

	var localapp = OS.get_environment("LOCALAPPDATA")
	if not localapp.is_empty() and (cmd_name == "agy" or cmd_name.ends_with("/agy") or cmd_name.ends_with("\\agy") or cmd_name.ends_with("/agy.exe") or cmd_name.ends_with("\\agy.exe")):
		var direct_exe = (localapp + "/agy/bin/agy.exe").replace("\\", "/")
		if FileAccess.file_exists(direct_exe):
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
	return OS.get_name() == "Windows"

func get_install_button_text() -> String:
	return "⬇️ Install agy"

func get_install_tooltip() -> String:
	return "Download and install Antigravity CLI (agy) automatically"

func get_install_command() -> Dictionary:
	if OS.get_name() == "Windows":
		var ps_cmd = "irm https://antigravity.google/cli/install.ps1 | iex 2>&1"
		return {
			"exec": "powershell.exe",
			"args": ["-NoProfile", "-Command", ps_cmd]
		}
	return {}

func get_install_start_bbcode() -> String:
	var bb = "\n[color=cyan]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n"
	bb += "[b][color=yellow]⬇️ Downloading & Installing Antigravity CLI (agy)...[/color][/b]\n"
	bb += "[color=gray]Executing: irm https://antigravity.google/cli/install.ps1 | iex[/color]\n\n"
	return bb

func get_install_success_bbcode() -> String:
	return "[color=green]✓ Antigravity CLI (agy) installed successfully![/color]\n"

# --- Models & Reasoning Effort ---

func supports_models() -> bool:
	return true

func supports_effort() -> bool:
	return true

func build_fetch_models_command(bin_path: String) -> Dictionary:
	if OS.get_name() == "Windows":
		var escaped_bin = bin_path.replace("'", "''")
		var ps_cmd = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & '%s' models" % escaped_bin
		return {
			"exec": "powershell.exe",
			"args": ["-NoProfile", "-Command", ps_cmd]
		}
	else:
		return {
			"exec": bin_path,
			"args": ["models"]
		}

func parse_models_output(raw_output: String) -> Array[Dictionary]:
	var model_map: Dictionary = {}
	var ordered_ids: Array[String] = []

	var lines = raw_output.split("\n")
	for line in lines:
		var trimmed = line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("Fetching") or not ("\t" in trimmed):
			continue
		var parts = trimmed.split("\t")
		if parts.size() < 2:
			continue
		var full_id = parts[0].strip_edges()
		var full_name = parts[1].strip_edges()

		var base_id = full_id
		var base_name = full_name
		var effort = ""

		if full_id.ends_with("-high"):
			base_id = full_id.trim_suffix("-high")
			effort = "high"
		elif full_id.ends_with("-medium"):
			base_id = full_id.trim_suffix("-medium")
			effort = "medium"
		elif full_id.ends_with("-low"):
			base_id = full_id.trim_suffix("-low")
			effort = "low"

		if full_name.ends_with(" (High)"):
			base_name = full_name.trim_suffix(" (High)")
		elif full_name.ends_with(" (Medium)"):
			base_name = full_name.trim_suffix(" (Medium)")
		elif full_name.ends_with(" (Low)"):
			base_name = full_name.trim_suffix(" (Low)")

		if not model_map.has(base_id):
			ordered_ids.append(base_id)
			model_map[base_id] = {
				"id": base_id,
				"name": base_name,
				"efforts": [],
				"default_effort": "high"
			}

		if not effort.is_empty() and not (effort in model_map[base_id]["efforts"]):
			model_map[base_id]["efforts"].append(effort)

	if ordered_ids.is_empty():
		return []

	var result: Array[Dictionary] = []
	for id in ordered_ids:
		var entry = model_map[id]
		var efforts: Array = entry["efforts"]
		if "high" in efforts:
			entry["default_effort"] = "high"
		elif "medium" in efforts:
			entry["default_effort"] = "medium"
		elif "low" in efforts:
			entry["default_effort"] = "low"
		else:
			entry["default_effort"] = ""
		result.append(entry)

	result.append({
		"id": "default",
		"name": "Default (System)",
		"efforts": ["default", "high", "medium", "low"],
		"default_effort": "default"
	})

	return result

# --- Quota ---

func supports_quota() -> bool:
	return true

func build_fetch_quota_command(bin_path: String) -> Dictionary:
	if OS.get_name() == "Windows":
		var escaped_bin = bin_path.replace("'", "''")
		var ps_cmd = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & '%s' -p '/quota'" % escaped_bin
		return {
			"exec": "powershell.exe",
			"args": ["-NoProfile", "-Command", ps_cmd]
		}
	else:
		return {
			"exec": bin_path,
			"args": ["-p", "/quota"]
		}

func parse_quota_output(raw_output: String) -> Dictionary:
	var result: Dictionary = {}
	var lines = raw_output.split("\n")
	for line in lines:
		var trimmed = line.strip_edges()
		if trimmed.is_empty() or not ("\t" in trimmed):
			continue
		var parts = trimmed.split("\t")
		if parts.size() < 3:
			continue
		var family = parts[0].strip_edges().to_lower()
		var limit_name = parts[1].strip_edges().to_lower()
		var pct = parts[2].strip_edges()
		var reset_time = parts[3].strip_edges() if parts.size() > 3 else ""

		var key = "gemini"
		if "claude" in family or "gpt" in family:
			key = "claude_gpt"

		if not result.has(key):
			result[key] = {}

		if "five hour" in limit_name or "5 hour" in limit_name:
			result[key]["five_hour"] = pct
			result[key]["five_hour_reset"] = reset_time
		elif "weekly" in limit_name:
			result[key]["weekly"] = pct
			result[key]["weekly_reset"] = reset_time

	return result

func format_quota_display(cached_quota: Dictionary, selected_model_id: String) -> Dictionary:
	if cached_quota.is_empty():
		return {
			"text": "⚡ --%",
			"tooltip": "Remaining quota for selected model (Click to refresh)",
			"color": Color(0.7, 0.7, 0.7)
		}

	var model_id = selected_model_id.to_lower()
	var key = "gemini"
	var group_name = "Gemini Models"
	if model_id.begins_with("claude") or model_id.begins_with("gpt"):
		key = "claude_gpt"
		group_name = "Claude / GPT Models"

	var data = cached_quota.get(key, {})
	if data.is_empty():
		return {
			"text": "⚡ --%",
			"tooltip": "No quota data for %s. Click to refresh." % group_name,
			"color": Color(0.7, 0.7, 0.7)
		}

	var five_hour = data.get("five_hour", "--")
	var weekly = data.get("weekly", "--")
	var five_hour_reset = _format_iso_timestamp(data.get("five_hour_reset", ""))
	var weekly_reset = _format_iso_timestamp(data.get("weekly_reset", ""))

	var text = "⚡ %s (5h)" % five_hour

	var color = Color(0.4, 0.9, 0.4)
	var val_str = five_hour.trim_suffix("%")
	var pct_val = val_str.to_int() if val_str.is_valid_int() else 100
	if pct_val > 50:
		color = Color(0.4, 0.9, 0.4)
	elif pct_val > 20:
		color = Color(1.0, 0.8, 0.2)
	else:
		color = Color(1.0, 0.35, 0.35)

	var tooltip_lines = [
		"%s Quota:" % group_name,
		"• 5-Hour Limit Remaining: %s%s" % [five_hour, (" (Resets: " + five_hour_reset + ")") if not five_hour_reset.is_empty() else ""],
		"• Weekly Limit Remaining: %s%s" % [weekly, (" (Resets: " + weekly_reset + ")") if not weekly_reset.is_empty() else ""],
		"",
		"Click to refresh quota"
	]

	return {
		"text": text,
		"tooltip": "\n".join(tooltip_lines),
		"color": color
	}

static func _format_iso_timestamp(iso_str: String) -> String:
	if iso_str.is_empty():
		return ""
	var clean_iso = iso_str.replace("Z", "").split(".")[0]
	var dt = Time.get_datetime_dict_from_datetime_string(clean_iso, false)
	if dt.is_empty():
		return iso_str
	var unix_t = Time.get_unix_time_from_datetime_dict(dt)
	var local_dt = Time.get_datetime_dict_from_unix_time(unix_t)
	var now_unix = Time.get_unix_time_from_system()
	var diff_sec = unix_t - int(now_unix)
	var rel_str = ""
	if diff_sec > 0:
		var hours = diff_sec / 3600
		var mins = (diff_sec % 3600) / 60
		if hours > 24:
			var days = hours / 24
			hours = hours % 24
			rel_str = "in %dd %dh" % [days, hours]
		elif hours > 0:
			rel_str = "in %dh %dm" % [hours, mins]
		else:
			rel_str = "in %dm" % maxi(1, mins)
	var time_str = "%02d:%02d" % [local_dt.hour, local_dt.minute]
	if not rel_str.is_empty():
		return "%s (%s)" % [time_str, rel_str]
	return time_str

# --- Execution ---

func build_run_command(bin_path: String, full_prompt: String, model_id: String, effort: String, session_id: String, continue_session: bool) -> Dictionary:
	var model_args = ""
	if model_id != "default" and not model_id.is_empty():
		model_args += " --model " + model_id
	if effort != "default" and not effort.is_empty():
		model_args += " --effort " + effort

	var session_flag = ""
	if not session_id.is_empty():
		session_flag = " --conversation " + session_id
	elif continue_session:
		session_flag = " -c"

	if OS.get_name() == "Windows":
		var escaped_bin = bin_path.replace("'", "''")
		var escaped_prompt = full_prompt.replace("'", "''")
		var ps_cmd = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & '%s' --dangerously-skip-permissions%s%s -p '%s' *>&1" % [escaped_bin, session_flag, model_args, escaped_prompt]
		return {
			"exec": "powershell.exe",
			"args": ["-NoProfile", "-Command", ps_cmd]
		}
	else:
		var escaped_sh_prompt = full_prompt.replace("'", "'\\''")
		var sh_cmd = "'%s' --dangerously-skip-permissions%s%s -p '%s' 2>&1" % [bin_path, session_flag, model_args, escaped_sh_prompt]
		return {
			"exec": "sh",
			"args": ["-c", sh_cmd]
		}

func get_prompt_placeholder() -> String:
	return "Ask Antigravity (agy)... (Ctrl+Enter to send)"

# --- History & Sessions ---

func supports_history() -> bool:
	return true

func get_history_folder_path() -> String:
	var user_profile = OS.get_environment("USERPROFILE")
	if user_profile.is_empty():
		user_profile = OS.get_environment("HOME")
	if not user_profile.is_empty():
		return (user_profile + "/.gemini/antigravity-cli/brain").replace("\\", "/")
	return ""

func scan_conversations(history_path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if history_path.is_empty() or not DirAccess.dir_exists_absolute(history_path):
		return result

	var dir = DirAccess.open(history_path)
	if not dir:
		return result

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var transcript_file = history_path + "/" + folder_name + "/.system_generated/logs/transcript.jsonl"
			if FileAccess.file_exists(transcript_file):
				var mtime = FileAccess.get_modified_time(transcript_file)
				var conv_info = _read_conversation_summary(folder_name, transcript_file, mtime)
				if not conv_info.is_empty():
					result.append(conv_info)
		folder_name = dir.get_next()
	dir.list_dir_end()

	result.sort_custom(func(a, b): return a.get("mtime", 0) > b.get("mtime", 0))
	return result

func _read_conversation_summary(conv_id: String, transcript_path: String, mtime: int) -> Dictionary:
	var file = FileAccess.open(transcript_path, FileAccess.READ)
	if not file:
		return {}

	var first_prompt = ""
	var turn_count = 0
	var bytes_read = 0

	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		bytes_read += line.length()
		if line.is_empty():
			continue
		var json = JSON.parse_string(line)
		if json is Dictionary:
			var step_type = json.get("type", "")
			if step_type == "USER_INPUT" and first_prompt.is_empty():
				first_prompt = json.get("content", "")
			if step_type == "USER_INPUT":
				turn_count += 1
		if turn_count > 0 and bytes_read > 4096:
			break
	file.close()

	var title = clean_prompt_title(first_prompt)
	if title.is_empty():
		title = "Session " + conv_id.substr(0, 8)

	var dt = Time.get_datetime_dict_from_unix_time(mtime)
	var time_str = "%02d/%02d %02d:%02d" % [dt.day, dt.month, dt.hour, dt.minute]
	var full_time = "%04d-%02d-%02d %02d:%02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]

	return {
		"id": conv_id,
		"title": title,
		"mtime": mtime,
		"time_str": time_str,
		"full_time": full_time,
		"transcript_path": transcript_path,
		"turns": turn_count
	}

func render_transcript(conv: Dictionary) -> String:
	var conv_id = conv.get("id", "")
	var transcript_path = conv.get("transcript_path", "")
	if not FileAccess.file_exists(transcript_path):
		return "[color=red]Transcript file not found: %s[/color]" % transcript_path

	var file = FileAccess.open(transcript_path, FileAccess.READ)
	if not file:
		return "[color=red]Failed to open transcript.[/color]"

	var output_bbcode = ""
	output_bbcode += "[color=gray]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n"
	output_bbcode += "[b][color=cyan]📜 Conversation: %s[/color][/b]\n" % conv.get("title", conv_id)
	output_bbcode += "[color=gray]ID: %s • Recorded: %s[/color]\n" % [conv_id, conv.get("full_time", "")]
	output_bbcode += "[color=gray]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n\n"

	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue
		var json = JSON.parse_string(line)
		if not (json is Dictionary):
			continue

		var step_type = json.get("type", "")
		var source = json.get("source", "")
		var content = json.get("content", "")

		if step_type == "USER_INPUT" or source == "USER_EXPLICIT":
			var clean_prompt = extract_clean_user_message(content)
			output_bbcode += "[b][color=#60A5FA]You:[/color][/b] " + clean_prompt + "\n\n"
		elif step_type == "PLANNER_RESPONSE" or source == "MODEL":
			if not content.is_empty():
				output_bbcode += "[b][color=#F59E0B]Antigravity:[/color][/b] " + content + "\n\n"
		elif step_type == "TOOL_CALL" or json.has("tool_calls"):
			var tool_calls = json.get("tool_calls", [])
			if tool_calls is Array and not tool_calls.is_empty():
				for tc in tool_calls:
					if tc is Dictionary:
						var tname = tc.get("name", "tool")
						output_bbcode += "[color=#6B7280]  🛠️ %s[/color]\n" % tname
				output_bbcode += "\n"

	file.close()
	return output_bbcode

func detect_newest_conversation_id() -> String:
	var brain_path = get_history_folder_path()
	if brain_path.is_empty() or not DirAccess.dir_exists_absolute(brain_path):
		return ""
	var dir = DirAccess.open(brain_path)
	if not dir:
		return ""
	dir.list_dir_begin()
	var newest_id = ""
	var newest_time: int = 0
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var transcript_file = brain_path + "/" + folder_name + "/.system_generated/logs/transcript.jsonl"
			if FileAccess.file_exists(transcript_file):
				var mtime = FileAccess.get_modified_time(transcript_file)
				if mtime > newest_time:
					newest_time = mtime
					newest_id = folder_name
		folder_name = dir.get_next()
	dir.list_dir_end()
	return newest_id

func clean_prompt_title(raw_content: String) -> String:
	var text = extract_clean_user_message(raw_content)
	var newline_pos = text.find("\n")
	if newline_pos != -1:
		text = text.substr(0, newline_pos).strip_edges()
	if text.length() > 65:
		text = text.substr(0, 62) + "..."
	return text

func extract_clean_user_message(raw_content: String) -> String:
	var text = raw_content
	if "<USER_REQUEST>" in text and "</USER_REQUEST>" in text:
		var s = text.find("<USER_REQUEST>") + 14
		var e = text.find("</USER_REQUEST>")
		if e > s:
			text = text.substr(s, e - s)

	var ctx_start = text.find("[Context:")
	if ctx_start != -1:
		var ctx_end = text.find("]", ctx_start)
		if ctx_end != -1:
			text = text.substr(0, ctx_start) + text.substr(ctx_end + 1)

	var focus_start = text.find("[Active Editor Focus:")
	if focus_start != -1:
		var focus_end = text.find("]", focus_start)
		if focus_end != -1:
			text = text.substr(0, focus_start) + text.substr(focus_end + 1)

	return text.strip_edges()

# --- Status & Log Previews ---

func get_not_found_bbcode(bin_path: String) -> String:
	return "[color=orange]⚠️ Antigravity CLI ('%s') is not found on your system PATH.[/color]\n[color=yellow]Click the [b]⬇️ Install agy[/b] button in the toolbar above to install it automatically.[/color]\n" % bin_path
