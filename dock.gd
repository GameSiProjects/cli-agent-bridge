@tool
extends Control

const BaseAgent = preload("res://addons/cli_agent_bridge/base_agent.gd")
const AntigravityAgent = preload("res://addons/cli_agent_bridge/antigravity/antigravity_agent.gd")
const GenericCliAgent = preload("res://addons/cli_agent_bridge/generic_agent.gd")

var editor_plugin: EditorPlugin

@onready var btn_new_chat: Button = $VBox/TopBar/BtnNewChat
@onready var chk_continue: CheckBox = $VBox/TopBar/ChkContinue
@onready var btn_history: Button = $VBox/TopBar/BtnHistory
@onready var sep_1: VSeparator = $VBox/TopBar/Sep1
@onready var lbl_agent: Label = $VBox/TopBar/LblAgent
@onready var opt_agent: OptionButton = $VBox/TopBar/OptAgent
@onready var sep_agent: VSeparator = $VBox/TopBar/SepAgent
@onready var btn_install: Button = $VBox/TopBar/BtnInstallAgy

@onready var lbl_model: Label = $VBox/TopBar/LblModel
@onready var opt_model: OptionButton = $VBox/TopBar/OptModel
@onready var lbl_effort: Label = $VBox/TopBar/LblEffort
@onready var opt_effort: OptionButton = $VBox/TopBar/OptEffort
@onready var btn_quota: Button = $VBox/TopBar/BtnQuota

@onready var btn_explain: Button = $VBox/TopBar/BtnExplain
@onready var btn_review: Button = $VBox/TopBar/BtnReview
@onready var btn_bugs: Button = $VBox/TopBar/BtnBugs
@onready var btn_test: Button = $VBox/TopBar/BtnTest

@onready var btn_copy_output: Button = $VBox/TopBar/BtnCopyOutput
@onready var btn_clear_output: Button = $VBox/TopBar/BtnClearOutput
@onready var btn_settings_toggle: Button = $VBox/TopBar/BtnSettingsToggle

@onready var history_drawer: VBoxContainer = $VBox/BodySplit/HistoryDrawer
@onready var btn_open_history_folder: Button = $VBox/BodySplit/HistoryDrawer/HistoryHeader/BtnOpenHistoryFolder
@onready var btn_refresh_history: Button = $VBox/BodySplit/HistoryDrawer/HistoryHeader/BtnRefreshHistory
@onready var btn_close_history: Button = $VBox/BodySplit/HistoryDrawer/HistoryHeader/BtnCloseHistory
@onready var history_search: LineEdit = $VBox/BodySplit/HistoryDrawer/HistorySearch
@onready var history_list: ItemList = $VBox/BodySplit/HistoryDrawer/HistoryList
@onready var btn_resume_session: Button = $VBox/BodySplit/HistoryDrawer/HistoryActions/BtnResumeSession

@onready var history_banner: HBoxContainer = $VBox/BodySplit/ChatArea/HistoryBanner
@onready var lbl_history_banner: Label = $VBox/BodySplit/ChatArea/HistoryBanner/LblHistoryBanner
@onready var btn_back_to_active_chat: Button = $VBox/BodySplit/ChatArea/HistoryBanner/BtnBackToActiveChat
@onready var output_log: RichTextLabel = $VBox/BodySplit/ChatArea/OutputLog

@onready var chk_scene: CheckBox = $VBox/ContextBar/ChkScene
@onready var chk_script: CheckBox = $VBox/ContextBar/ChkScript
@onready var chk_nodes: CheckBox = $VBox/ContextBar/ChkNodes
@onready var status_label: Label = $VBox/ContextBar/StatusLabel

@onready var prompt_edit: TextEdit = $VBox/PromptContainer/PromptEdit
@onready var send_button: Button = $VBox/PromptContainer/SendButton

@onready var settings_box: HBoxContainer = $VBox/Settings
@onready var path_edit: LineEdit = $VBox/Settings/PathEdit
@onready var btn_refresh_models: Button = $VBox/Settings/BtnRefreshModels
@onready var status_timer: Timer = $StatusTimer

const CONFIG_FILE_PATH = "user://cli_agent_bridge.cfg"
const LEGACY_CONFIG_FILE_PATH = "user://agent_bridge.cfg"

# --- Agent Management ---
var registered_agents: Array[BaseAgent] = []
var active_agent: BaseAgent = null

var available_models: Array[Dictionary] = []
var models_thread: Thread = null
var is_fetching_models: bool = false
var has_fetched_initial_models: bool = false
var _saved_model_preference: String = ""
var _saved_effort_preference: String = ""
var cached_quota: Dictionary = {}
var quota_thread: Thread = null
var is_fetching_quota: bool = false

var active_conversation_id: String = ""
var viewing_history_id: String = ""
var active_chat_bbcode: String = ""
var cached_conversations: Array[Dictionary] = []

var has_active_session: bool = false
var worker_thread: Thread = null
var output_mutex: Mutex = null
var pending_chunks: Array[String] = []
var is_worker_active: bool = false
var worker_has_finished: bool = false
var active_pid: int = -1
var is_installing: bool = false
var response_received_bytes: int = 0
var context_update_accum: float = 0.0
var _binary_availability_cache: Dictionary = {}

func _ready() -> void:
	output_mutex = Mutex.new()
	if status_label:
		status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_register_default_agents()
	_connect_signals()
	_load_config()
	_update_context_previews()

func _exit_tree() -> void:
	_stop_worker_process()
	if models_thread and models_thread.is_started():
		models_thread.wait_to_finish()
		models_thread = null
	if quota_thread and quota_thread.is_started():
		quota_thread.wait_to_finish()
		quota_thread = null

func _connect_signals() -> void:
	if btn_new_chat and not btn_new_chat.pressed.is_connected(_on_new_chat_pressed):
		btn_new_chat.pressed.connect(_on_new_chat_pressed)
	if opt_agent and not opt_agent.item_selected.is_connected(_on_agent_selected):
		opt_agent.item_selected.connect(_on_agent_selected)
	if btn_install and not btn_install.pressed.is_connected(_on_install_pressed):
		btn_install.pressed.connect(_on_install_pressed)
	if opt_model and not opt_model.item_selected.is_connected(_on_model_selected):
		opt_model.item_selected.connect(_on_model_selected)
	if opt_effort and not opt_effort.item_selected.is_connected(_on_effort_selected):
		opt_effort.item_selected.connect(_on_effort_selected)
	if btn_quota and not btn_quota.pressed.is_connected(_on_quota_pressed):
		btn_quota.pressed.connect(_on_quota_pressed)
	if btn_refresh_models and not btn_refresh_models.pressed.is_connected(_on_refresh_models_pressed):
		btn_refresh_models.pressed.connect(_on_refresh_models_pressed)
	if send_button and not send_button.pressed.is_connected(_on_send_pressed):
		send_button.pressed.connect(_on_send_pressed)
	if btn_explain and not btn_explain.pressed.is_connected(_on_preset_explain):
		btn_explain.pressed.connect(_on_preset_explain)
	if btn_review and not btn_review.pressed.is_connected(_on_preset_review):
		btn_review.pressed.connect(_on_preset_review)
	if btn_bugs and not btn_bugs.pressed.is_connected(_on_preset_bugs):
		btn_bugs.pressed.connect(_on_preset_bugs)
	if btn_test and not btn_test.pressed.is_connected(_on_preset_test):
		btn_test.pressed.connect(_on_preset_test)
	if btn_clear_output and not btn_clear_output.pressed.is_connected(_on_clear_output):
		btn_clear_output.pressed.connect(_on_clear_output)
	if btn_copy_output and not btn_copy_output.pressed.is_connected(_on_copy_output):
		btn_copy_output.pressed.connect(_on_copy_output)
	if btn_settings_toggle and not btn_settings_toggle.pressed.is_connected(_on_settings_toggle_pressed):
		btn_settings_toggle.pressed.connect(_on_settings_toggle_pressed)
	if prompt_edit and not prompt_edit.gui_input.is_connected(_on_prompt_gui_input):
		prompt_edit.gui_input.connect(_on_prompt_gui_input)
	if status_timer and not status_timer.timeout.is_connected(_on_status_timeout):
		status_timer.timeout.connect(_on_status_timeout)
	if path_edit and not path_edit.text_changed.is_connected(_on_path_changed):
		path_edit.text_changed.connect(_on_path_changed)
	if btn_history and not btn_history.pressed.is_connected(_on_history_toggle_pressed):
		btn_history.pressed.connect(_on_history_toggle_pressed)
	if btn_open_history_folder and not btn_open_history_folder.pressed.is_connected(_on_open_history_folder_pressed):
		btn_open_history_folder.pressed.connect(_on_open_history_folder_pressed)
	if btn_refresh_history and not btn_refresh_history.pressed.is_connected(_on_refresh_history_pressed):
		btn_refresh_history.pressed.connect(_on_refresh_history_pressed)
	if btn_close_history and not btn_close_history.pressed.is_connected(_on_close_history_pressed):
		btn_close_history.pressed.connect(_on_close_history_pressed)
	if history_search and not history_search.text_changed.is_connected(_on_history_search_changed):
		history_search.text_changed.connect(_on_history_search_changed)
	if history_list and not history_list.item_selected.is_connected(_on_history_item_selected):
		history_list.item_selected.connect(_on_history_item_selected)
	if btn_resume_session and not btn_resume_session.pressed.is_connected(_on_resume_session_pressed):
		btn_resume_session.pressed.connect(_on_resume_session_pressed)
	if btn_back_to_active_chat and not btn_back_to_active_chat.pressed.is_connected(_on_back_to_active_chat_pressed):
		btn_back_to_active_chat.pressed.connect(_on_back_to_active_chat_pressed)

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	context_update_accum += delta
	if context_update_accum >= 0.2:
		context_update_accum = 0.0
		_update_context_previews()

	# Read streaming chunks from worker thread without blocking editor UI
	var chunks: Array[String] = []
	var finished: bool = false

	if output_mutex:
		output_mutex.lock()
		while not pending_chunks.is_empty():
			chunks.append(pending_chunks.pop_front())
		finished = worker_has_finished
		output_mutex.unlock()

	var had_no_bytes: bool = (response_received_bytes == 0)
	for chunk in chunks:
		response_received_bytes += chunk.length()
		_append_output(chunk)

	if had_no_bytes and response_received_bytes > 0 and is_worker_active and not is_installing:
		var cur_model_name = _get_selected_model_name() if active_agent and active_agent.supports_models() else ""
		var status_info = (" (%s)" % cur_model_name) if not cur_model_name.is_empty() and cur_model_name != "None" else ""
		_set_status("Responding...%s" % status_info, Color.CYAN, false)

	# When worker thread signals completion
	if is_worker_active and finished:
		if worker_thread and worker_thread.is_started():
			worker_thread.wait_to_finish()
			worker_thread = null

		is_worker_active = false
		worker_has_finished = false
		active_pid = -1

		_append_output("\n")
		_update_ui_state(false)

		if is_installing:
			is_installing = false
			_binary_availability_cache.clear()
			has_fetched_initial_models = false
			_validate_current_binary()
			var resolved = _get_resolved_binary()
			if active_agent and active_agent.is_binary_available(resolved):
				_append_output(active_agent.get_install_success_bbcode())
				_set_status("Installation complete.", Color.GREEN, true)
			else:
				_set_status("Installer finished. Please check output above.", Color.YELLOW, true)
		elif response_received_bytes == 0:
			var agent_name = active_agent.get_short_name() if active_agent else "agent"
			_append_output("[color=yellow](No response output received from %s. If an error occurred, check agent logs.)[/color]\n" % agent_name)
			_set_status("Finished (no output)", Color.YELLOW, true)
		else:
			_set_status("Response complete.", Color.GREEN, true)
			if active_agent and active_agent.supports_history():
				if active_conversation_id.is_empty():
					active_conversation_id = active_agent.detect_newest_conversation_id()
				cached_conversations.clear()
			if active_agent and active_agent.supports_quota():
				_fetch_quota_async()

# --- Agent Registry & Lifecycle ---

func _register_default_agents() -> void:
	registered_agents.clear()
	register_agent(AntigravityAgent.new())
	register_agent(GenericCliAgent.new())

func register_agent(agent: BaseAgent) -> void:
	if not agent:
		return
	for existing in registered_agents:
		if existing.get_id() == agent.get_id():
			return
	registered_agents.append(agent)
	_populate_agent_options()

func _populate_agent_options(preferred_id: String = "") -> void:
	if not opt_agent:
		return
	opt_agent.clear()
	var select_idx = 0
	for i in range(registered_agents.size()):
		var agent = registered_agents[i]
		opt_agent.add_item(agent.get_name())
		opt_agent.set_item_metadata(i, agent.get_id())
		if not preferred_id.is_empty() and agent.get_id() == preferred_id:
			select_idx = i

	if opt_agent.item_count > 0:
		opt_agent.select(select_idx)
		_set_active_agent_by_index(select_idx)

func _set_active_agent_by_index(index: int) -> void:
	if index < 0 or index >= registered_agents.size():
		return
	var new_agent = registered_agents[index]
	if active_agent == new_agent:
		return

	active_agent = new_agent
	_binary_availability_cache.clear()
	available_models.clear()
	cached_quota.clear()
	cached_conversations.clear()
	has_fetched_initial_models = false
	active_conversation_id = ""
	viewing_history_id = ""
	has_active_session = false

	# Update visibility of agent-specific UI controls
	var supports_models = active_agent.supports_models()
	var supports_effort = active_agent.supports_effort()
	var supports_quota = active_agent.supports_quota()
	var supports_history = active_agent.supports_history()

	if lbl_model:
		lbl_model.visible = supports_models
	if opt_model:
		opt_model.visible = supports_models
	if lbl_effort:
		lbl_effort.visible = supports_effort
	if opt_effort:
		opt_effort.visible = supports_effort
	if btn_quota:
		btn_quota.visible = supports_quota
	if btn_history:
		btn_history.visible = supports_history
	if btn_refresh_models:
		btn_refresh_models.visible = supports_models
		btn_refresh_models.tooltip_text = "Reload available models and reasoning effort from %s" % active_agent.get_short_name()
	if not supports_history and history_drawer:
		history_drawer.visible = false
	if history_banner:
		history_banner.visible = false

	if prompt_edit:
		prompt_edit.placeholder_text = active_agent.get_prompt_placeholder()

	# Restore saved config for this agent
	_load_agent_specific_config(active_agent.get_id())

	_init_models()
	_update_ui_state(false)
	_validate_current_binary()

func _on_agent_selected(index: int) -> void:
	_set_active_agent_by_index(index)
	_save_config()
	if active_agent:
		_set_status("Switched agent to: %s" % active_agent.get_name(), Color.SKY_BLUE, true)

func _update_ui_state(busy: bool) -> void:
	var supports_models = active_agent and active_agent.supports_models()
	var has_model: bool = not available_models.is_empty() or not supports_models
	var can_action: bool = not busy and has_model

	if send_button:
		send_button.text = "🛑 Stop" if busy else "🚀 Send"
		send_button.disabled = not busy and not has_model
	if btn_explain:
		btn_explain.disabled = not can_action
	if btn_review:
		btn_review.disabled = not can_action
	if btn_bugs:
		btn_bugs.disabled = not can_action
	if btn_test:
		btn_test.disabled = not can_action
	if btn_install and btn_install.visible:
		btn_install.disabled = busy
	if opt_agent:
		opt_agent.disabled = busy
	if opt_model:
		opt_model.disabled = busy or not has_model
	if opt_effort:
		var current_model = _get_selected_model_entry()
		var supported_efforts: Array = current_model.get("efforts", [])
		opt_effort.disabled = busy or not has_model or supported_efforts.is_empty()
	if btn_quota:
		btn_quota.disabled = busy

func _stop_worker_process() -> void:
	var pid_to_kill = -1
	if output_mutex:
		output_mutex.lock()
		pid_to_kill = active_pid
		output_mutex.unlock()

	if pid_to_kill > 0 and OS.is_process_running(pid_to_kill):
		if OS.get_name() == "Windows":
			OS.execute("taskkill.exe", ["/F", "/T", "/PID", str(pid_to_kill)])
		OS.kill(pid_to_kill)

	if worker_thread and worker_thread.is_started():
		worker_thread.wait_to_finish()
		worker_thread = null

	if output_mutex:
		output_mutex.lock()
		active_pid = -1
		is_worker_active = false
		worker_has_finished = false
		pending_chunks.clear()
		output_mutex.unlock()

func _start_process_worker(exec_cmd: String, args: Array, installing: bool) -> void:
	_stop_worker_process()

	if status_timer and status_timer.is_inside_tree():
		status_timer.stop()

	is_installing = installing
	response_received_bytes = 0
	is_worker_active = true
	worker_has_finished = false

	_update_ui_state(true)

	worker_thread = Thread.new()
	var err = worker_thread.start(_thread_worker.bind(exec_cmd, args))
	if err != OK:
		is_worker_active = false
		_update_ui_state(false)
		_set_status("Failed to start background worker thread (error %d)." % err, Color.RED, true)
		_append_output("[color=red]Failed to start background thread.[/color]\n")

func _thread_worker(exec_cmd: String, args: Array) -> void:
	var pipe = OS.execute_with_pipe(exec_cmd, args)
	var pid = pipe.get("pid", -1)
	var stdio = pipe.get("stdio") as FileAccess

	output_mutex.lock()
	active_pid = pid
	output_mutex.unlock()

	if pid <= 0 or not stdio or not stdio.is_open():
		output_mutex.lock()
		worker_has_finished = true
		output_mutex.unlock()
		return

	var remainder = PackedByteArray()

	while stdio.is_open():
		var chunk = stdio.get_buffer(4096)
		if chunk.size() > 0:
			var to_process = remainder
			to_process.append_array(chunk)
			var extracted = _extract_valid_utf8(to_process)
			var text_to_emit: String = extracted[0]
			remainder = extracted[1]

			if not text_to_emit.is_empty():
				output_mutex.lock()
				pending_chunks.append(text_to_emit)
				output_mutex.unlock()
		else:
			break

	stdio.close()

	if remainder.size() > 0:
		var last_text = remainder.get_string_from_utf8()
		if last_text.is_empty():
			last_text = remainder.get_string_from_ascii()
		if not last_text.is_empty():
			output_mutex.lock()
			pending_chunks.append(last_text)
			output_mutex.unlock()

	output_mutex.lock()
	worker_has_finished = true
	output_mutex.unlock()

static func _extract_valid_utf8(bytes: PackedByteArray) -> Array:
	var n = bytes.size()
	if n == 0:
		return ["", PackedByteArray()]

	var cutoff = n
	for i in range(1, mini(5, n + 1)):
		var b = bytes[n - i]
		if (b & 0x80) == 0:
			break
		elif (b & 0xC0) == 0xC0:
			var expected_len = 0
			if (b & 0xE0) == 0xC0:
				expected_len = 2
			elif (b & 0xF0) == 0xE0:
				expected_len = 3
			elif (b & 0xF8) == 0xF0:
				expected_len = 4

			if i < expected_len:
				cutoff = n - i
			break

	var to_decode = bytes.slice(0, cutoff)
	var rem = bytes.slice(cutoff)
	return [to_decode.get_string_from_utf8(), rem]

func _update_context_previews() -> void:
	if not editor_plugin:
		return

	var scene_path = _get_active_scene_path()
	if chk_scene:
		var target_scene_text = "Scene: " + scene_path.get_file() if not scene_path.is_empty() else "Scene: (none)"
		if chk_scene.text != target_scene_text:
			chk_scene.text = target_scene_text
			chk_scene.tooltip_text = scene_path if not scene_path.is_empty() else "No active scene open in Godot"

	var script_path = _get_active_script_path()
	if chk_script:
		var target_script_text = "Script: " + script_path.get_file() if not script_path.is_empty() else "Script: (none)"
		if chk_script.text != target_script_text:
			chk_script.text = target_script_text
			chk_script.tooltip_text = script_path if not script_path.is_empty() else "No active script open in Godot"

	var nodes_str = _get_selected_nodes_summary()
	if chk_nodes:
		var target_nodes_text = "Nodes: (none)"
		if not nodes_str.is_empty():
			var selection = editor_plugin.get_editor_interface().get_selection().get_selected_nodes()
			if selection.size() == 1:
				target_nodes_text = "Nodes: " + selection[0].name
			elif selection.size() > 1:
				target_nodes_text = "Nodes: %s (+%d)" % [selection[0].name, selection.size() - 1]
		if chk_nodes.text != target_nodes_text:
			chk_nodes.text = target_nodes_text
			chk_nodes.tooltip_text = "Selected: " + nodes_str if not nodes_str.is_empty() else "No node currently selected"

func _get_resolved_binary() -> String:
	if active_agent == null:
		return ""
	var path = path_edit.text.strip_edges() if path_edit else ""
	var default_bin = active_agent.get_default_binary()
	if path.is_empty() or path == default_bin:
		return default_bin
	return path

func _is_binary_available(cmd_name: String) -> bool:
	if cmd_name.is_empty():
		return false
	var cache_key = "%s:%s" % [active_agent.get_id() if active_agent else "none", cmd_name]
	if _binary_availability_cache.has(cache_key):
		return _binary_availability_cache[cache_key]

	var available = false
	if active_agent:
		available = active_agent.is_binary_available(cmd_name)
	else:
		available = FileAccess.file_exists(cmd_name)

	_binary_availability_cache[cache_key] = available
	return available

func _validate_current_binary() -> bool:
	if active_agent == null:
		return false

	var bin_path = _get_resolved_binary()
	var default_bin = active_agent.get_default_binary()
	if path_edit and path_edit.text != bin_path and bin_path != default_bin:
		path_edit.text = bin_path

	var available = _is_binary_available(bin_path)

	if btn_install:
		btn_install.visible = not available and active_agent.can_install()
		btn_install.text = active_agent.get_install_button_text()
		btn_install.tooltip_text = active_agent.get_install_tooltip()

	# Keep the log view in sync with actual status when idle
	if not has_active_session and output_log:
		if available:
			if active_agent.supports_models() and available_models.is_empty():
				output_log.text = "[color=gray]%s ready. Fetching models from CLI...[/color]\n" % active_agent.get_name()
			else:
				var cur_model = _get_selected_model_name() if active_agent.supports_models() else ""
				var cur_effort = _get_selected_effort_label() if active_agent.supports_effort() else ""
				output_log.text = active_agent.get_ready_message(bin_path, cur_model, cur_effort)
		else:
			output_log.text = active_agent.get_not_found_bbcode(bin_path)

	if available:
		if not is_worker_active and not is_installing:
			if active_agent.supports_models() and available_models.is_empty():
				_set_status("Ready (fetching models...)", Color.YELLOW, false)
			else:
				_set_status("Ready (%s found)" % active_agent.get_short_name(), Color.GREEN, false)
		if active_agent.supports_models() and not has_fetched_initial_models and not is_fetching_models:
			has_fetched_initial_models = true
			_fetch_models_async()
		return true
	else:
		if not is_worker_active and not is_installing:
			_set_status("⚠️ '%s' not found on system PATH." % bin_path, Color.RED, false)
		if settings_box and not has_active_session:
			settings_box.visible = true
		return false

func _on_install_pressed() -> void:
	if is_worker_active:
		_set_status("Another operation is running. Please wait...", Color.ORANGE, true)
		return
	if not active_agent or not active_agent.can_install():
		return

	var cmd_info = active_agent.get_install_command()
	if cmd_info.is_empty():
		return

	var start_bb = active_agent.get_install_start_bbcode()
	if not start_bb.is_empty():
		_append_output(start_bb)
	_set_status("Installing %s... Please wait." % active_agent.get_short_name(), Color.CYAN, false)
	_start_process_worker(cmd_info.get("exec", ""), cmd_info.get("args", []), true)

func _on_new_chat_pressed() -> void:
	if is_worker_active:
		_stop_worker_process()
		_update_ui_state(false)
		_append_output("\n[color=yellow][Previous operation stopped][/color]\n")

	has_active_session = false
	active_conversation_id = ""
	viewing_history_id = ""
	active_chat_bbcode = ""
	if chk_continue:
		chk_continue.button_pressed = false
	if history_banner:
		history_banner.visible = false
	if history_list:
		history_list.deselect_all()
	if btn_resume_session:
		btn_resume_session.disabled = true
		btn_resume_session.text = "▶️ Resume Session"
	_append_output("\n[color=orange]─────────────────────────────────────────────────[/color]\n")
	_append_output("[color=yellow]🔄 New conversation started. Next prompt will begin a fresh session.[/color]\n")
	_set_status("Started new conversation session.", Color.YELLOW, true)

func _on_prompt_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and event.ctrl_pressed:
			_on_send_pressed()
			accept_event()

func _on_clear_output() -> void:
	if output_log:
		output_log.clear()

func _on_copy_output() -> void:
	if output_log:
		DisplayServer.clipboard_set(output_log.get_parsed_text())
		if not is_worker_active and not is_installing:
			_set_status("Conversation copied to clipboard.", Color.SKY_BLUE, true)

func _on_settings_toggle_pressed() -> void:
	if settings_box:
		settings_box.visible = not settings_box.visible

func _append_output(text: String) -> void:
	if output_log:
		output_log.append_text(text)

func _on_preset_explain() -> void:
	var scene_path = _get_active_scene_path()
	var abs_scene = ProjectSettings.globalize_path(scene_path) if not scene_path.is_empty() else ""
	if not abs_scene.is_empty():
		prompt_edit.text = "Explain the structure, hierarchy, and purpose of the current scene (%s) and any selected nodes." % abs_scene.get_file()
	else:
		prompt_edit.text = "Explain the structure, hierarchy, and purpose of this scene and any selected nodes."
	_on_send_pressed()

func _on_preset_review() -> void:
	var script_path = _get_active_script_path()
	var abs_script = ProjectSettings.globalize_path(script_path) if not script_path.is_empty() else ""
	if not abs_script.is_empty():
		prompt_edit.text = "Review the script '%s' against project architecture, conventions, and suggest improvements or refactorings." % abs_script
	else:
		prompt_edit.text = "Review this script against project architecture, conventions, and suggest improvements or refactorings."
	_on_send_pressed()

func _on_preset_bugs() -> void:
	var script_path = _get_active_script_path()
	var abs_script = ProjectSettings.globalize_path(script_path) if not script_path.is_empty() else ""
	var scene_path = _get_active_scene_path()
	var abs_scene = ProjectSettings.globalize_path(scene_path) if not scene_path.is_empty() else ""
	var targets: Array[String] = []
	if not abs_scene.is_empty():
		targets.append(abs_scene.get_file())
	if not abs_script.is_empty():
		targets.append(abs_script.get_file())
	var target_desc = " and ".join(targets) if not targets.is_empty() else "this scene and script"
	prompt_edit.text = "Analyze %s for potential bugs, broken node paths, missing null checks, or edge cases." % target_desc
	_on_send_pressed()

func _on_preset_test() -> void:
	var script_path = _get_active_script_path()
	var abs_script = ProjectSettings.globalize_path(script_path) if not script_path.is_empty() else ""
	if not abs_script.is_empty():
		prompt_edit.text = "Generate an automated test script under tests/ for '%s' following project conventions." % abs_script
	else:
		prompt_edit.text = "Generate an automated test script under tests/ for this component following project conventions."
	_on_send_pressed()

func _on_send_pressed() -> void:
	if is_worker_active:
		_stop_worker_process()
		_update_ui_state(false)
		_append_output("\n[color=yellow][Operation stopped by user][/color]\n\n")
		_set_status("Operation stopped.", Color.ORANGE, true)
		return

	var user_prompt = prompt_edit.text.strip_edges()
	if user_prompt.is_empty():
		_set_status("Please enter a prompt first.", Color.ORANGE, true)
		return

	if active_agent == null:
		_set_status("No active agent selected.", Color.RED, true)
		return

	if active_agent.supports_models() and available_models.is_empty():
		_set_status("Cannot send: No models available. Check %s installation or click 🔄 to refresh." % active_agent.get_short_name(), Color.RED, true)
		return

	var bin_path = _get_resolved_binary()
	var default_bin = active_agent.get_default_binary()
	if path_edit and path_edit.text != bin_path and bin_path != default_bin:
		path_edit.text = bin_path
		_save_config()

	# Verify binary exists
	if not _is_binary_available(bin_path):
		_set_status("Cannot send: '" + bin_path + "' not found on system PATH.", Color.RED, true)
		_append_output("\n[color=red]❌ Cannot execute: '" + bin_path + "' is not installed or not in PATH.[/color]\n")
		if active_agent.can_install():
			_append_output("[color=yellow]Click the [b]%s[/b] button above to install it automatically![/color]\n\n" % active_agent.get_install_button_text())
		return

	var scene_path = _get_active_scene_path()
	var script_path = _get_active_script_path()
	var node_info = _get_selected_nodes_summary()

	var abs_scene = ProjectSettings.globalize_path(scene_path) if (chk_scene and chk_scene.button_pressed and not scene_path.is_empty()) else ""
	var abs_script = ProjectSettings.globalize_path(script_path) if (chk_script and chk_script.button_pressed and not script_path.is_empty()) else ""

	if not viewing_history_id.is_empty():
		active_conversation_id = viewing_history_id
		viewing_history_id = ""
		if history_banner:
			history_banner.visible = false

	# Check whether we continue previous conversation turn
	var continue_session = (chk_continue and chk_continue.button_pressed) and (has_active_session or not active_conversation_id.is_empty())

	# Build context string
	var context_prefix = ""
	var context_items: Array[String] = []
	if not abs_scene.is_empty():
		context_items.append("Scene: " + abs_scene)
	if not abs_script.is_empty():
		context_items.append("Script: " + abs_script)
	if chk_nodes and chk_nodes.button_pressed and not node_info.is_empty():
		context_items.append("Selected Nodes: " + node_info)

	if not context_items.is_empty():
		if not continue_session:
			context_prefix = "[Context: " + "; ".join(context_items) + "]\n"
		else:
			context_prefix = "[Active Editor Focus: " + "; ".join(context_items) + "]\n"

	var full_prompt = context_prefix + user_prompt

	# Model and reasoning effort arguments
	var model_id = _get_selected_model_id() if active_agent.supports_models() else ""
	var effort_val = _get_selected_effort() if active_agent.supports_effort() else ""

	var cur_model_name = _get_selected_model_name() if active_agent.supports_models() else ""
	var cur_effort_label = _get_selected_effort_label() if active_agent.supports_effort() else ""
	var agent_tag = active_agent.get_agent_tag(cur_model_name, cur_effort_label)

	# Display user message in Output Log
	_append_output("\n[b][color=#60A5FA]You:[/color][/b] " + user_prompt + "\n")
	_append_output("[b][color=#F59E0B]%s:[/color][/b] " % agent_tag)

	response_received_bytes = 0
	has_active_session = true
	if chk_continue:
		chk_continue.button_pressed = true

	var status_tag = (" (%s)" % cur_model_name) if not cur_model_name.is_empty() and cur_model_name != "None" else ""
	_set_status("Thinking...%s" % status_tag, Color.CYAN, false)
	prompt_edit.clear()

	var cmd_info = active_agent.build_run_command(bin_path, full_prompt, model_id, effort_val, active_conversation_id, continue_session)
	var exec_cmd = cmd_info.get("exec", "")
	var exec_args = cmd_info.get("args", [])
	_start_process_worker(exec_cmd, exec_args, false)

func _get_active_scene_path() -> String:
	if not editor_plugin:
		return ""
	var root = editor_plugin.get_editor_interface().get_edited_scene_root()
	if root and not root.scene_file_path.is_empty():
		return root.scene_file_path
	return ""

func _get_active_script_path() -> String:
	if not editor_plugin:
		return ""
	var script_editor = editor_plugin.get_editor_interface().get_script_editor()
	if script_editor:
		var script = script_editor.get_current_script()
		if script and not script.resource_path.is_empty():
			return script.resource_path
	return ""

func _get_selected_nodes_summary() -> String:
	if not editor_plugin:
		return ""
	var selection = editor_plugin.get_editor_interface().get_selection().get_selected_nodes()
	if selection.is_empty():
		return ""
	var names: Array[String] = []
	for n in selection:
		names.append("%s (%s)" % [n.name, n.get_class()])
	return ", ".join(names)

func _load_config() -> void:
	var cfg = ConfigFile.new()
	var selected_agent_id = "antigravity"

	if cfg.load(CONFIG_FILE_PATH) == OK or cfg.load(LEGACY_CONFIG_FILE_PATH) == OK:
		selected_agent_id = cfg.get_value("settings", "active_agent", cfg.get_value("settings", "agent", "antigravity"))

	_populate_agent_options(selected_agent_id)

func _load_agent_specific_config(agent_id: String) -> void:
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_FILE_PATH) == OK or cfg.load(LEGACY_CONFIG_FILE_PATH) == OK:
		var saved_path = cfg.get_value("settings", "bin_path_" + agent_id, "")
		if saved_path.is_empty() and agent_id == "antigravity":
			saved_path = cfg.get_value("settings", "bin_path", "")
		if not saved_path.is_empty() and path_edit:
			path_edit.text = saved_path

		var saved_model = cfg.get_value("settings", "model_" + agent_id, "")
		if saved_model.is_empty() and agent_id == "antigravity":
			saved_model = cfg.get_value("settings", "model", "")
		if not saved_model.is_empty():
			_saved_model_preference = saved_model

		var saved_effort = cfg.get_value("settings", "effort_" + agent_id, "")
		if saved_effort.is_empty() and agent_id == "antigravity":
			saved_effort = cfg.get_value("settings", "effort", "")
		if not saved_effort.is_empty():
			_saved_effort_preference = saved_effort
	else:
		if path_edit and active_agent:
			path_edit.text = active_agent.get_default_binary()

	if path_edit and active_agent:
		var resolved = _get_resolved_binary()
		var def_bin = active_agent.get_default_binary()
		if resolved != def_bin and path_edit.text != resolved:
			path_edit.text = resolved

func _save_config() -> void:
	if not active_agent:
		return
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_FILE_PATH) != OK:
		cfg.load(LEGACY_CONFIG_FILE_PATH)

	var agent_id = active_agent.get_id()
	cfg.set_value("settings", "active_agent", agent_id)

	if path_edit:
		var current_path = path_edit.text.strip_edges()
		cfg.set_value("settings", "bin_path_" + agent_id, current_path)
		if agent_id == "antigravity":
			cfg.set_value("settings", "bin_path", current_path)

	if active_agent.supports_models():
		var model_id = _get_selected_model_id()
		if not model_id.is_empty():
			cfg.set_value("settings", "model_" + agent_id, model_id)
			if agent_id == "antigravity":
				cfg.set_value("settings", "model", model_id)

	if active_agent.supports_effort():
		var effort_val = _get_selected_effort()
		if not effort_val.is_empty():
			cfg.set_value("settings", "effort_" + agent_id, effort_val)
			if agent_id == "antigravity":
				cfg.set_value("settings", "effort", effort_val)

	cfg.save(CONFIG_FILE_PATH)

func _on_path_changed(_new_text: String) -> void:
	_binary_availability_cache.clear()
	has_fetched_initial_models = false
	_save_config()
	_validate_current_binary()

func _set_status(msg: String, color: Color, auto_clear: bool = false) -> void:
	if status_label:
		status_label.text = msg
		status_label.modulate = color
	if status_timer and status_timer.is_inside_tree():
		if auto_clear and not is_worker_active and not is_installing:
			status_timer.start(5.0)
		else:
			status_timer.stop()

func _on_status_timeout() -> void:
	if is_worker_active or is_installing:
		return
	if status_label:
		_validate_current_binary()

# --- Model & Reasoning Effort Management ---

func _init_models() -> void:
	available_models.clear()
	_populate_model_options()
	_update_effort_options(false)
	_update_quota_display()

func _populate_model_options(preferred_id: String = "") -> void:
	if not opt_model:
		return
	opt_model.clear()
	if not active_agent or not active_agent.supports_models() or available_models.is_empty():
		opt_model.disabled = true
		opt_model.tooltip_text = "No models available"
		return

	opt_model.disabled = is_worker_active
	var select_idx = 0
	for i in range(available_models.size()):
		var entry = available_models[i]
		opt_model.add_item(entry.get("name", entry.get("id", "")))
		opt_model.set_item_metadata(i, entry.get("id", ""))
		if not preferred_id.is_empty() and entry.get("id", "") == preferred_id:
			select_idx = i

	if opt_model.item_count > 0:
		opt_model.select(select_idx)
		opt_model.tooltip_text = "Current model: %s" % opt_model.get_item_text(select_idx)

func _update_effort_options(preserve_selection: bool = true) -> void:
	if not opt_effort:
		return

	opt_effort.clear()

	if not active_agent or not active_agent.supports_effort() or available_models.is_empty():
		opt_effort.disabled = true
		opt_effort.tooltip_text = "Effort not configurable"
		if lbl_effort:
			lbl_effort.modulate = Color(0.6, 0.6, 0.6, 0.7)
		return

	var current_model = _get_selected_model_entry()
	var supported: Array = current_model.get("efforts", [])
	var prev_effort = _get_selected_effort()

	if supported.is_empty():
		opt_effort.add_item("N/A (Thinking)")
		opt_effort.set_item_metadata(0, "")
		opt_effort.disabled = true
		opt_effort.tooltip_text = "Reasoning effort is fixed / not configurable for %s" % current_model.get("name", "this model")
		if lbl_effort:
			lbl_effort.modulate = Color(0.6, 0.6, 0.6, 0.7)
		return

	opt_effort.disabled = false
	if lbl_effort:
		lbl_effort.modulate = Color.WHITE

	var select_idx = 0
	var found_prev = false

	for i in range(supported.size()):
		var eff: String = supported[i]
		var label = eff.capitalize()
		if eff == "default":
			label = "Default"
		opt_effort.add_item(label)
		opt_effort.set_item_metadata(i, eff)
		if preserve_selection and eff == prev_effort:
			select_idx = i
			found_prev = true

	if not found_prev:
		var target_eff = _saved_effort_preference if not _saved_effort_preference.is_empty() else current_model.get("default_effort", "")
		for i in range(supported.size()):
			if supported[i] == target_eff:
				select_idx = i
				break

	if opt_effort.item_count > 0:
		opt_effort.select(select_idx)
		opt_effort.tooltip_text = "Reasoning effort: %s" % opt_effort.get_item_text(select_idx)

func _get_selected_model_entry() -> Dictionary:
	if not opt_model or opt_model.item_count == 0:
		return {}
	var idx = opt_model.selected
	if idx < 0 or idx >= opt_model.item_count:
		idx = 0
	var id = opt_model.get_item_metadata(idx)
	for m in available_models:
		if m.get("id", "") == id:
			return m
	return {}

func _get_selected_model_id() -> String:
	var entry = _get_selected_model_entry()
	return entry.get("id", "")

func _get_selected_model_name() -> String:
	var entry = _get_selected_model_entry()
	return entry.get("name", "None")

func _get_selected_effort() -> String:
	if not opt_effort or opt_effort.item_count == 0 or opt_effort.disabled:
		return ""
	var idx = opt_effort.selected
	if idx < 0 or idx >= opt_effort.item_count:
		return ""
	return str(opt_effort.get_item_metadata(idx))

func _get_selected_effort_label() -> String:
	if not opt_effort or opt_effort.item_count == 0:
		return ""
	var idx = opt_effort.selected
	if idx < 0 or idx >= opt_effort.item_count:
		return ""
	return opt_effort.get_item_text(idx)

func _select_model_by_id(id: String) -> void:
	if not opt_model:
		return
	for i in range(opt_model.item_count):
		if opt_model.get_item_metadata(i) == id:
			opt_model.select(i)
			opt_model.tooltip_text = "Current model: %s" % opt_model.get_item_text(i)
			_update_effort_options(true)
			return

func _select_effort_by_value(eff: String) -> void:
	if not opt_effort:
		return
	for i in range(opt_effort.item_count):
		if opt_effort.get_item_metadata(i) == eff:
			opt_effort.select(i)
			opt_effort.tooltip_text = "Reasoning effort: %s" % opt_effort.get_item_text(i)
			return

func _on_model_selected(index: int) -> void:
	var entry = _get_selected_model_entry()
	_saved_model_preference = entry.get("id", "")
	if opt_model:
		opt_model.tooltip_text = "Current model: %s" % opt_model.get_item_text(index)
	_update_effort_options(true)
	_update_quota_display()
	_save_config()
	var eff_lbl = _get_selected_effort_label()
	var eff_desc = " (%s effort)" % eff_lbl if not eff_lbl.is_empty() and eff_lbl != "N/A (Thinking)" and eff_lbl != "Default" else ""
	_set_status("Switched to model: %s%s" % [_get_selected_model_name(), eff_desc], Color.SKY_BLUE, true)

func _on_effort_selected(index: int) -> void:
	var eff = _get_selected_effort()
	_saved_effort_preference = eff
	if opt_effort:
		opt_effort.tooltip_text = "Reasoning effort: %s" % opt_effort.get_item_text(index)
	_save_config()
	_set_status("Set reasoning effort to: %s" % _get_selected_effort_label(), Color.SKY_BLUE, true)

func _on_refresh_models_pressed() -> void:
	if not active_agent or not active_agent.supports_models():
		return
	_set_status("Refreshing models & quota from CLI...", Color.CYAN, false)
	_fetch_models_async()
	if active_agent.supports_quota():
		_fetch_quota_async()

func _fetch_models_async() -> void:
	if is_fetching_models or not active_agent or not active_agent.supports_models():
		return
	var bin_path = _get_resolved_binary()
	if not _is_binary_available(bin_path):
		return

	is_fetching_models = true
	models_thread = Thread.new()
	var err = models_thread.start(_thread_fetch_models.bind(bin_path))
	if err != OK:
		is_fetching_models = false
		has_fetched_initial_models = false

func _thread_fetch_models(bin_path: String) -> void:
	if not active_agent:
		call_deferred("_on_fetch_models_completed", "")
		return

	var cmd_info = active_agent.build_fetch_models_command(bin_path)
	if cmd_info.is_empty():
		call_deferred("_on_fetch_models_completed", "")
		return

	var output: Array = []
	var exit_code = OS.execute(cmd_info.get("exec", ""), cmd_info.get("args", []), output)

	var raw_output = ""
	if exit_code == 0 and not output.is_empty():
		raw_output = str(output[0])

	call_deferred("_on_fetch_models_completed", raw_output)

func _on_fetch_models_completed(raw_text: String) -> void:
	if models_thread and models_thread.is_started():
		models_thread.wait_to_finish()
		models_thread = null
	is_fetching_models = false
	_apply_fetched_models(raw_text)
	if active_agent and active_agent.supports_quota():
		_fetch_quota_async()

func _apply_fetched_models(raw_text: String) -> void:
	if not active_agent:
		return
	var parsed = active_agent.parse_models_output(raw_text)
	if parsed.is_empty():
		if available_models.is_empty():
			_set_status("No models found from %s CLI. Click 🔄 to retry." % active_agent.get_short_name(), Color.ORANGE, false)
			_update_ui_state(false)
		return

	var target_id = _saved_model_preference if not _saved_model_preference.is_empty() else _get_selected_model_id()
	available_models = parsed
	_populate_model_options(target_id)
	_update_effort_options(true)
	_update_quota_display()
	_update_ui_state(false)

	# Update output_log preview if idle and fresh
	if not has_active_session and output_log:
		var cur_model = _get_selected_model_name()
		var cur_effort = _get_selected_effort_label()
		output_log.text = active_agent.get_ready_message(_get_resolved_binary(), cur_model, cur_effort)

	if not is_worker_active and not is_installing:
		_set_status("Models list refreshed (%d models available)." % (available_models.size() - 1), Color.GREEN, true)

# --- Quota Management ---

func _on_quota_pressed() -> void:
	if is_worker_active or is_fetching_quota or not active_agent or not active_agent.supports_quota():
		return
	_set_status("Refreshing quota...", Color.CYAN, false)
	_fetch_quota_async()

func _fetch_quota_async() -> void:
	if is_fetching_quota or not active_agent or not active_agent.supports_quota():
		return
	var bin_path = _get_resolved_binary()
	if not _is_binary_available(bin_path):
		return

	is_fetching_quota = true
	if btn_quota and cached_quota.is_empty():
		btn_quota.text = "⚡ ..."
		btn_quota.tooltip_text = "Fetching quota from CLI..."

	quota_thread = Thread.new()
	var err = quota_thread.start(_thread_fetch_quota.bind(bin_path))
	if err != OK:
		is_fetching_quota = false

func _thread_fetch_quota(bin_path: String) -> void:
	if not active_agent:
		call_deferred("_on_fetch_quota_completed", "")
		return

	var cmd_info = active_agent.build_fetch_quota_command(bin_path)
	if cmd_info.is_empty():
		call_deferred("_on_fetch_quota_completed", "")
		return

	var output: Array = []
	var exit_code = OS.execute(cmd_info.get("exec", ""), cmd_info.get("args", []), output)

	var raw_output = ""
	if exit_code == 0 and not output.is_empty():
		raw_output = str(output[0])

	call_deferred("_on_fetch_quota_completed", raw_output)

func _on_fetch_quota_completed(raw_text: String) -> void:
	if quota_thread and quota_thread.is_started():
		quota_thread.wait_to_finish()
		quota_thread = null
	is_fetching_quota = false
	if active_agent:
		cached_quota = active_agent.parse_quota_output(raw_text)
	_update_quota_display()

func _update_quota_display() -> void:
	if not btn_quota:
		return

	if not active_agent or not active_agent.supports_quota():
		btn_quota.visible = false
		return

	btn_quota.visible = true
	var display_info = active_agent.format_quota_display(cached_quota, _get_selected_model_id())
	btn_quota.text = display_info.get("text", "⚡ --%")
	btn_quota.tooltip_text = display_info.get("tooltip", "Remaining quota")
	btn_quota.modulate = display_info.get("color", Color(0.7, 0.7, 0.7))

# --- Conversation History Management ---

func _on_history_toggle_pressed() -> void:
	if history_drawer:
		history_drawer.visible = not history_drawer.visible
		if history_drawer.visible:
			_refresh_history_list(history_search.text if history_search else "")

func _on_close_history_pressed() -> void:
	if history_drawer:
		history_drawer.visible = false

func _on_open_history_folder_pressed() -> void:
	if not active_agent or not active_agent.supports_history():
		return
	var hist_path = active_agent.get_history_folder_path()
	if hist_path.is_empty():
		_set_status("Cannot determine history folder path.", Color.RED, true)
		return

	if not DirAccess.dir_exists_absolute(hist_path):
		var err = DirAccess.make_dir_recursive_absolute(hist_path)
		if err != OK:
			_set_status("History folder does not exist: %s" % hist_path, Color.RED, true)
			return

	var global_path = ProjectSettings.globalize_path(hist_path)
	var err = OS.shell_open(global_path)
	if err == OK:
		_set_status("Opened history folder in file manager.", Color.GREEN, true)
	else:
		_set_status("Failed to open history folder: %s" % global_path, Color.RED, true)

func _on_refresh_history_pressed() -> void:
	cached_conversations.clear()
	_refresh_history_list(history_search.text if history_search else "")
	_set_status("Refreshed conversation history.", Color.SKY_BLUE, true)

func _on_history_search_changed(filter_text: String) -> void:
	_refresh_history_list(filter_text)

func _refresh_history_list(filter_text: String = "") -> void:
	if not history_list:
		return
	history_list.clear()

	if not active_agent or not active_agent.supports_history():
		history_list.add_item("(History not supported by this agent)")
		history_list.set_item_disabled(0, true)
		if btn_resume_session:
			btn_resume_session.disabled = true
		return

	var hist_path = active_agent.get_history_folder_path()
	if hist_path.is_empty() or not DirAccess.dir_exists_absolute(hist_path):
		history_list.add_item("(No history directory found)")
		history_list.set_item_disabled(0, true)
		if btn_resume_session:
			btn_resume_session.disabled = true
		return

	if cached_conversations.is_empty():
		cached_conversations = active_agent.scan_conversations(hist_path)

	var filter_lower = filter_text.strip_edges().to_lower()
	var displayed_count = 0

	for conv in cached_conversations:
		var title: String = conv.get("title", "Untitled Session")
		var conv_id: String = conv.get("id", "")
		var time_str: String = conv.get("time_str", "")

		if not filter_lower.is_empty():
			if not (filter_lower in title.to_lower() or filter_lower in conv_id.to_lower()):
				continue

		var item_label = title
		if not time_str.is_empty():
			item_label = "[%s] %s" % [time_str, title]

		var idx = history_list.add_item(item_label)
		history_list.set_item_metadata(idx, conv)
		history_list.set_item_tooltip(idx, "ID: %s\nTime: %s\nPrompt: %s" % [conv_id, conv.get("full_time", ""), title])
		if conv_id == active_conversation_id or conv_id == viewing_history_id:
			history_list.select(idx)
		displayed_count += 1

	if displayed_count == 0:
		history_list.add_item("(No matching sessions)" if not filter_lower.is_empty() else "(No saved sessions)")
		history_list.set_item_disabled(0, true)
		if btn_resume_session:
			btn_resume_session.disabled = true

func _on_history_item_selected(index: int) -> void:
	if index < 0 or index >= history_list.item_count or not active_agent:
		return
	var conv = history_list.get_item_metadata(index)
	if not (conv is Dictionary) or conv.is_empty():
		return

	if viewing_history_id.is_empty() and has_active_session and output_log:
		active_chat_bbcode = output_log.text

	var conv_id = conv.get("id", "")
	viewing_history_id = conv_id

	if btn_resume_session:
		btn_resume_session.disabled = false
		if active_conversation_id == conv_id:
			btn_resume_session.text = "✓ Active Session"
		else:
			btn_resume_session.text = "▶️ Resume Session"

	_render_transcript_in_log(conv)

func _render_transcript_in_log(conv: Dictionary) -> void:
	if not output_log or not active_agent:
		return
	output_log.clear()

	var bbcode = active_agent.render_transcript(conv)
	output_log.text = bbcode

	if history_banner:
		history_banner.visible = true
	if lbl_history_banner:
		var conv_id = conv.get("id", "")
		lbl_history_banner.text = "Viewing: %s (%s)" % [conv.get("title", conv_id), conv_id.substr(0, 8)]

func _on_resume_session_pressed() -> void:
	if viewing_history_id.is_empty():
		return
	active_conversation_id = viewing_history_id
	has_active_session = true
	if chk_continue:
		chk_continue.button_pressed = true
	if btn_resume_session:
		btn_resume_session.text = "✓ Active Session"
	if history_banner:
		history_banner.visible = false
	viewing_history_id = ""
	_set_status("Resumed conversation: %s" % active_conversation_id.substr(0, 8), Color.GREEN, true)
	_append_output("\n[color=green]✓ Resumed session. Subsequent prompts will continue this conversation.[/color]\n")

func _on_back_to_active_chat_pressed() -> void:
	viewing_history_id = ""
	if history_banner:
		history_banner.visible = false
	if history_list:
		history_list.deselect_all()
	if btn_resume_session:
		btn_resume_session.disabled = true
		btn_resume_session.text = "▶️ Resume Session"

	if not active_chat_bbcode.is_empty() and output_log:
		output_log.text = active_chat_bbcode
	elif not has_active_session and output_log:
		_validate_current_binary()
