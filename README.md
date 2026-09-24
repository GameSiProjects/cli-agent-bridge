# CLI Agent Bridge — Extensible Local CLI AI Agent Dock for Godot 4

**CLI Agent Bridge** is an extensible Godot 4 editor plugin that embeds conversational local AI coding agents directly into the editor's bottom panel. It enables seamless, multi-turn AI assistance without window switching, context loss, or separate desktop apps.

Out of the box, CLI Agent Bridge provides rich, first-class support for Google's **Antigravity CLI (`agy`)**, alongside an adapter-based architecture that lets you connect **any local CLI agent** (such as Claude CLI, Aider, Ollama, Cursor CLI, or custom scripts).

---

## Directory Structure

All Antigravity-specific code is neatly isolated in its own dedicated subfolder, leaving the core bridge completely agent-agnostic:

```text
addons/cli_agent_bridge/
├── base_agent.gd              # Abstract base class defining the CLI agent API
├── generic_agent.gd           # Generic CLI fallback agent (runs any terminal tool)
├── dock.gd                    # UI logic, thread worker, streaming output & signals
├── dock.tscn                  # Bottom dock UI layout and widget tree
├── plugin.gd                  # EditorPlugin entry point (registers dock in bottom panel)
├── plugin.cfg                 # Godot plugin descriptor
├── icon.svg                   # Plugin tab icon
├── README.md                  # Plugin documentation
└── antigravity/               # Dedicated Antigravity encapsulation
    └── antigravity_agent.gd   # All agy-specific logic (models, quota, history, installer)
```

---

## Architecture: Pluggable CLI Agent System

CLI Agent Bridge uses the **Adapter Pattern** to decouple the Godot editor UI from specific AI CLI implementations:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Godot Editor Bottom Panel                   │
│         [dock.tscn] & [dock.gd] (Context, UI, Streaming Worker) │
└────────────────────────────────┬────────────────────────────────┘
                                 │ delegates to active agent
                    ┌────────────┴────────────┐
                    ▼                         ▼
         ┌─────────────────────┐   ┌─────────────────────┐
         │  AntigravityAgent   │   │   GenericCliAgent   │  ... (Custom Agents)
         │  (agy CLI Adapter)  │   │   (Direct CLI Run)  │
         └──────────┬──────────┘   └──────────┬──────────┘
                    │                         │
                    ▼                         ▼
            powershell / sh            powershell / sh
              & 'agy.exe'                & 'aider' / 'ollama' / ...
```

### Core Components

1. **[`base_agent.gd`](base_agent.gd) (`BaseAgent`)**:
   Defines the contract for CLI agents:
   - **Identity**: `get_id()`, `get_name()`, `get_short_name()`, `get_description()`
   - **Binary Resolution**: `get_default_binary()`, `is_binary_available()`, `get_path_placeholder()`
   - **Installation**: `can_install()`, `get_install_button_text()`, `get_install_command()`
   - **Model & Effort**: `supports_models()`, `build_fetch_models_command()`, `parse_models_output()`, `supports_effort()`
   - **Quota**: `supports_quota()`, `build_fetch_quota_command()`, `parse_quota_output()`, `format_quota_display()`
   - **Execution**: `build_run_command()`, `get_prompt_placeholder()`, `get_agent_tag()`
   - **History**: `supports_history()`, `get_history_folder_path()`, `scan_conversations()`, `render_transcript()`

2. **[`antigravity/antigravity_agent.gd`](antigravity/antigravity_agent.gd) (`AntigravityAgent`)**:
   Encapsulates all Antigravity CLI logic:
   - Automatic detection of `%LOCALAPPDATA%\agy\bin\agy.exe` and PATH resolution.
   - 1-click installer using `irm https://antigravity.google/cli/install.ps1 | iex`.
   - Command construction with `--dangerously-skip-permissions`, `-p`, `-c`, and `--conversation <id>`.
   - Dynamic model discovery via `agy models` (supports Gemini, Claude, GPT-OSS with High/Medium/Low effort levels).
   - Quota tracking via `/quota` (5-hour and weekly limits with color-coded status and reset countdowns).
   - Past conversation indexing and JSONL transcript parsing from `~/.gemini/antigravity-cli/brain/`.

3. **[`generic_agent.gd`](generic_agent.gd) (`GenericCliAgent`)**:
   A lightweight, universal CLI runner that passes your prompt directly to any specified executable or script without requiring custom parsing.

---

## Adding a Custom CLI Agent

To add support for your favorite CLI agent (e.g. Aider, Claude Code, Ollama):

### 1. Create an Agent Script
Inherit from `BaseAgent` and override the necessary methods:

```gdscript
@tool
class_name AiderAgent
extends BaseAgent

func get_id() -> String:
	return "aider"

func get_name() -> String:
	return "Aider CLI"

func get_short_name() -> String:
	return "Aider"

func get_default_binary() -> String:
	return "aider"

func build_run_command(bin_path: String, full_prompt: String, _model_id: String, _effort: String, _session_id: String, _continue_session: bool) -> Dictionary:
	var escaped_bin = bin_path.replace("'", "''")
	var escaped_prompt = full_prompt.replace("'", "''")
	
	if OS.get_name() == "Windows":
		var ps_cmd = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & '%s' --message '%s' --no-auto-commits *>&1" % [escaped_bin, escaped_prompt]
		return { "exec": "powershell.exe", "args": ["-NoProfile", "-Command", ps_cmd] }
	else:
		var sh_cmd = "'%s' --message '%s' --no-auto-commits 2>&1" % [bin_path, full_prompt.replace("'", "'\\''")]
		return { "exec": "sh", "args": ["-c", sh_cmd] }
```

### 2. Register the Agent
Register it in `dock.gd` or from an external script/plugin:

```gdscript
dock.register_agent(AiderAgent.new())
```

The dock UI will automatically adapt, adding the agent to the dropdown and displaying only the features supported by your adapter.

---

## Features

- **Agent Selector**:
  - Switch between **Antigravity (agy)**, **Generic CLI**, or any registered agent adapter directly from the top toolbar dropdown.
  - UI dynamically adapts to each agent's capabilities (showing or hiding model selection, effort levels, quota indicators, and session history).
- **Asynchronous Non-Blocking Execution**:
  - Process execution runs in a dedicated background worker `Thread` with real-time UTF-8 streaming.
  - The Godot editor stays 100% smooth, interactive, and responsive while the AI thinks and generates code.
- **Model & Reasoning Effort Selection** (Antigravity):
  - Choose between Gemini 3.8/3.7/3.6 Flash, Gemini 3.1 Pro, Claude Sonnet 4.6, Claude Opus 4.6, GPT-OSS 120B, and System Default.
  - Dynamic reasoning effort levels (`High`, `Medium`, `Low`, `Default`) intelligently match model capabilities.
  - Background async discovery queries `agy models` to fetch newly available models without editor freeze.
- **Real-Time Quota Display** (Antigravity):
  - Displays remaining 5-hour and weekly quota percentages with color-coded warning states (green/yellow/red) and reset timers.
- **Interruptible / Cancellation Support**:
  - Stop any running query immediately with the **Stop** button or reset session context with **New Chat**.
- **Conversation History Browser** (Antigravity):
  - Click **History** to browse, search, and preview historical sessions from `~/.gemini/antigravity-cli/brain/`.
  - Click **Resume Session** to seamlessly pick up right where a previous conversation left off.
  - Click the folder icon button to open the session folder directly in your operating system's file manager.
- **Multi-Turn Memory**:
  - Preserves conversation context across turns using session continuation flags (`-c` / `--conversation`).
- **Live Godot Context Bundling**:
  - **Scene**: Attaches active `.tscn` scene filename and path.
  - **Script**: Attaches active `.gd` or `.cs` script path open in Godot's Script Editor.
  - **Selected Nodes**: Attaches selected nodes and their engine types from the Scene Tree dock.
- **One-Click Presets**:
  - **Explain**: Analyzes scene hierarchy, purpose, and selected nodes.
  - **Review**: Reviews active script against project architecture, conventions, and memory/performance guidelines.
  - **Bugs**: Inspects for missing null checks, broken NodePaths, and edge cases.
  - **Test**: Generates automated test scripts under `tests/` following project conventions.
- **Automatic Path Resolution & 1-Click Installer**:
  - Detects `%LOCALAPPDATA%\agy\bin\agy.exe` automatically without requiring manual configuration or restart.
  - If `agy` is not installed, an **Install agy** button appears in the toolbar to run the official installer in the background.

---

## Important Notice for Antigravity (`agy`): Auto-Approval

> [!WARNING]
> When using the Antigravity agent, commands run with the `--dangerously-skip-permissions` flag:
> ```bash
> agy --dangerously-skip-permissions -c -p "<prompt>"
> ```

### Why is this flag required?
When running in non-interactive/print mode (`-p`), `agy` cannot prompt the user interactively in a terminal for tool permissions. By default, any operation that touches the filesystem (such as `read_file` to inspect the active script or scene) is auto-denied by `agy`. Passing `--dangerously-skip-permissions` allows `agy` to read workspace files, analyze scripts, and produce reviews and suggestions directly inside the Godot dock.

### Security Implications
- **Auto-approved Operations**: Tools requested by `agy` (file reading, workspace inspections, edits, commands) are executed without prompting for manual confirmation.
- **Scope**: Tool execution is confined to your workspace directory and project files.
- **Reviewing Changes**: If you instruct `agy` to edit or refactor scripts, always verify diffs using your version control system (`git status` / `git diff`).

---

## Getting Started

### 1. Enable the Plugin
1. Open your Godot project.
2. Navigate to **Project → Project Settings → Plugins**.
3. Enable **CLI Agent Bridge**.
4. The **CLI Agent** dock will appear in the bottom panel.

### 2. Configure Your Agent
1. Open the **CLI Agent** bottom panel tab.
2. Select your agent provider from the **Agent:** dropdown:
   - **Antigravity (agy)** (default)
   - **Generic CLI**
   - Or any custom registered agent.
3. If using Antigravity and it is not installed:
   - Click the **Install agy** button in the top bar.
   - Or install manually via PowerShell:
     ```powershell
     irm https://antigravity.google/cli/install.ps1 | iex
     ```
4. If you need a custom binary path, click the settings gear button in the top right to open the Settings drawer and enter the path.

### 3. Usage & Shortcuts
- **Send Prompt**: Press `Ctrl+Enter` (or click **Send**).
- **Cancel Prompt**: Click **Stop** while a response is streaming.
- **New Session**: Click **New Chat**.
- **Inspect Past Sessions**: Click **History**.
- **Copy Log**: Click **Copy** to copy formatted chat to clipboard.
- **Clear Log**: Click **Clear**.

---

## Configuration & Persistence

The plugin persists your preferences in `user://cli_agent_bridge.cfg` (with automatic fallback to legacy `user://agent_bridge.cfg` if present):
- Active agent selection (`settings/active_agent`)
- Executable binary paths per agent (`settings/bin_path_<agent_id>`)
- Preferred models and reasoning efforts per agent (`settings/model_<agent_id>`, `settings/effort_<agent_id>`)

Settings are preserved across Godot editor restarts and maintain full backward compatibility with earlier versions.
