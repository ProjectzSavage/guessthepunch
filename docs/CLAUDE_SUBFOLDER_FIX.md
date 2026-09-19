# Why Claude Can't Access Subfolders + Fix

## The Problem

You enabled MCP connection for Claude, but Claude can't access subfolders like `src/Shared/`, `src/Server/Services/`, etc.

**Reasons:**

1. **MCP FileSystem Server Config:** Many Claude MCP filesystem servers are configured with `allowedDirectories` that only allow root repo path, but not recursive subfolder reads, or they have `root` set to repo root but Claude's tool calls use relative paths incorrectly.

2. **GitHub Repo Structure vs Studio Structure:** Claude might be trying to read `ReplicatedStorage/Shared/Config` (Studio path) instead of `src/Shared/Config.luau` (GitHub path). If MCP is connected to Studio, not GitHub, it can't see `src/` subfolders because they don't exist in Studio - they exist only in GitHub.

3. **Case Sensitivity / Extension Handling:** You requested no `.luau` extensions in Studio names, but GitHub files have `.luau`. If Claude's MCP does exact name matching, `Config` vs `Config.luau` mismatch causes "not found".

4. **MCP Tool Limitations:** Some MCP tools (like `read_file`) require exact absolute path `/home/user/guessthepunch/src/Shared/Config.luau` and don't auto-list subfolders. If Claude only calls `list_files` on root, it won't see nested files unless recursive flag enabled.

---

## Fix - 3 Options

### Option 1: Use Flat Folder (Recommended for Claude)

I created `flat/` folder at repo root with NO subfolders, just flat files:

```
flat/
├── Shared_Config.luau
├── Shared_QueueStates.luau
├── Shared_MatchStates.luau
├── Shared_Roles.luau
├── Shared_RemoteNames.luau
├── Shared_Constants.luau
├── Shared_Types.luau
├── Server_RemoteService.luau
├── Server_QueueService.luau
├── Server_MatchService.luau
├── Server_Main.server.luau
└── Client_Main.client.luau
```

**For Claude:** Tell Claude to read from `flat/` folder, not `src/` subfolders. All files are at top level of `flat/`, no subfolders to traverse.

**Command for Claude:**
```
Read file flat/Shared_Config.luau
Read file flat/Server_QueueService.luau
etc.
```

This fixes subfolder access because flat has no subfolders.

### Option 2: Update MCP Config to Allow Recursive Subfolder Access

If you control MCP config (e.g., `claude_desktop_config.json`), ensure:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/guessthepunch"],
      "env": {}
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "your_token"
      }
    }
  }
}
```

And ensure Claude uses `list_files` with recursive=true or uses absolute paths like `/home/user/guessthepunch/src/Shared/Config.luau`.

Also check if MCP has `allowedDirectories` - add `/home/user/guessthepunch/src` and `/home/user/guessthepunch/src/Shared` and `/home/user/guessthepunch/src/Server/Services`.

### Option 3: Use Master Script That Creates Everything (No File Reading Needed)

Use `docs/CLAUDE_MASTER_SCRIPT.lua` or `docs/CLAUDE_MASTER_SCRIPT_MATCH_SETUP.lua` - these are single scripts that **contain all code inside** as strings, so Claude doesn't need to read subfolders at all. Claude just needs to:

1. Read ONE file: `docs/CLAUDE_MASTER_SCRIPT_MATCH_SETUP.lua`
2. Paste its content into Studio Command Bar
3. It auto-creates all folders and scripts with code

This bypasses subfolder access entirely because all code is embedded in one file.

**For Claude MCP to Studio:**
- If Claude has MCP connection to Studio (e.g., via `roblox-studio-mcp`), it can directly call `create_instance` tools to create ModuleScripts and set Source, without reading GitHub files at all. Use the master script logic.

---

## What I Did in GitHub Now

- **Updated GitHub:** Merged remote Claude MCP docs (05679ae) with local match setup (4f2e229) into 7ef283d and pushed to `arena/01a0ba26-guessthepunch` branch. GitHub now has:
  - `src/Shared/` with Config, QueueStates, MatchStates, Roles, etc.
  - `src/Server/Services/` with QueueService, MatchService, RemoteService
  - `flat/` with flat files (no subfolders) for Claude
  - `docs/CLAUDE_MCP_SETUP.md` + `docs/CLAUDE_MASTER_SCRIPT.lua` + `docs/CLAUDE_MASTER_SCRIPT_MATCH_SETUP.lua`

- **Fixed Constants error:** Constants.luau now standalone, no requires, so no yellow underline.

- **Created flat folder:** `flat/` contains all files flattened, no subfolders, so Claude can access without traversing subfolders.

---

## Instructions for Claude (Copy-Paste)

**Tell Claude:**

```
You have MCP access to GitHub repo at /home/user/guessthepunch and/or Roblox Studio.

Your task: Setup Guess the Puncher queue + match setup system.

If you CANNOT access subfolders like src/Shared/, use flat/ folder instead:

- Read flat/Shared_Config.luau
- Read flat/Shared_QueueStates.luau
- Read flat/Shared_MatchStates.luau
- Read flat/Shared_Roles.luau
- Read flat/Server_QueueService.luau
- Read flat/Server_MatchService.luau
- etc.

All files in flat/ are at top level, no subfolders.

Alternatively, read ONE file: docs/CLAUDE_MASTER_SCRIPT_MATCH_SETUP.lua - it contains a master script that creates ALL folders and scripts in Studio with code embedded. Paste that master script into Studio Command Bar.

Required manual objects (you cannot create via GitHub, user must create manually, but you can create via MCP Studio tools if available):
- Workspace.Lobby.MatchSlots.Slot2, Slot4, Slot6 with EntryArea, LeaveButton, DisplayBoard, PlayerSpawns
- Workspace.MatchArenas.Arena2, Arena4, Arena6 with TargetStand+Chair Seat, PuncherStand 6 studs behind, PlayerSpawns
- See docs/QUEUE_MANUAL_OBJECTS.md and docs/MATCH_ARENA_OBJECTS.md for exact names, hierarchy, properties

Do NOT implement punching, power, damage, guessing, knockout, GUI, monetization, DataStores - only queue + basic match setup (Preparing, SelectingTarget, WaitingForPuncher).

After setup, verify with:
- Shared/Config exists and returns table
- No yellow underline errors (Constants standalone)
- Remotes folder has 12 remotes
- Workspace.Lobby.MatchSlots.Slot2.EntryArea exists
- Workspace.MatchArenas.Arena2.TargetStand.Chair is Seat
```

---

## Quick Test for Claude

Claude can run this in Studio Command Bar to test access:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
print("Shared exists?", ReplicatedStorage:FindFirstChild("Shared") ~= nil)
print("Config exists?", ReplicatedStorage.Shared:FindFirstChild("Config") ~= nil)
print("QueueService exists?", game.ServerScriptService.Services:FindFirstChild("QueueService") ~= nil)
print("MatchService exists?", game.ServerScriptService.Services:FindFirstChild("MatchService") ~= nil)
print("Arena2 Chair is Seat?", workspace.MatchArenas.Arena2.TargetStand:FindFirstChild("Chair") and workspace.MatchArenas.Arena2.TargetStand.Chair:IsA("Seat"))
```

If any false, Claude needs to create missing objects using master script.

