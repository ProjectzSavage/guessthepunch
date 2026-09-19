# Copy Instructions - GitHub to Roblox Studio

## How to copy files from GitHub into Roblox Studio

### Method 1: Manual Copy-Paste (Recommended for Phase 1)

1. Open GitHub repo in browser or local clone.
2. Open Roblox Studio place.
3. In Explorer, create the required Folder/Model/Script as per docs/STUDIO_MAPPING.md
4. For each file:

   **Example: src/Shared/Constants.luau**
   - In GitHub, open file, select all (Ctrl+A), copy (Ctrl+C)
   - In Studio, right-click ReplicatedStorage > Shared > Insert Object > ModuleScript
   - Rename ModuleScript to `Constants`
   - Double-click to open script editor
   - Delete default `print("Hello world!")`
   - Paste GitHub content (Ctrl+V)
   - File > Save

   **Example: src/Server/Main.server.luau**
   - In Studio, right-click ServerScriptService > Insert Object > Script
   - Rename to `GuessThePuncherServer`
   - Open, paste content from GitHub
   - Important: Must be Script, not ModuleScript, for .server.luau

   **Example: src/Client/Main.client.luau**
   - Right-click StarterPlayer > StarterPlayerScripts > Insert Object > LocalScript
   - Rename to `GuessThePuncherClient`
   - Paste content

5. Repeat for all files in src/.

### Method 2: Rojo (Advanced, optional)

If you use Rojo:

- Install Rojo plugin in Studio
- Create `default.project.json` in repo root:
```json
{
  "name": "GuessThePuncher",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "Shared": {
        "$path": "src/Shared"
      },
      "Remotes": {
        "$className": "Folder"
      }
    },
    "ServerScriptService": {
      "GuessThePuncherServer": {
        "$path": "src/Server/Main.server.luau"
      },
      "Services": {
        "$path": "src/Server/Services"
      }
    },
    "StarterPlayer": {
      "StarterPlayerScripts": {
        "GuessThePuncherClient": {
          "$path": "src/Client/Main.client.luau"
        },
        "Controllers": {
          "$path": "src/Client/Controllers"
        }
      }
    }
  }
}
```
- Run `rojo serve` and connect in Studio

But for this project, manual copy is fine per your instruction.

---

## Order to copy for Phase 1

1. ReplicatedStorage:
   - Create Folder `Shared`
   - Create Folder `Shared/Util`
   - Copy: Constants, Config, Types, Animations, RemoteDefinitions
   - Copy Util: TableUtil, StateMachine, Signal

2. ServerScriptService:
   - Create Folder `Services`
   - Copy all Services ModuleScripts
   - Create Script `GuessThePuncherServer` and paste Main.server.luau
   - The script will auto-create Remotes folder and 20 RemoteEvents if missing (as requested)

3. StarterPlayerScripts:
   - Create Folder `Controllers`
   - Create LocalScript `GuessThePuncherClient` and paste Main.client.luau
   - Copy all Controllers ModuleScripts into Controllers folder

4. Workspace:
   - Manually create Lobby, MatchSlots, MatchArenas as per MANUAL_OBJECTS.md (not from GitHub)

5. StarterGui:
   - Create ScreenGui `MainHUD` with ResetOnSpawn=false (placeholder for now)

---

## Validation after copy

After copying:

- Play in Studio (F5) with 1 player
- Check Output window:
  - Server should print: "[GuessThePuncherServer] All remotes validated: 20 found" or "Auto-created X RemoteEvents"
  - Server should print: "[GuessThePuncherServer] Workspace structure validated" or list missing objects
  - Client should print: "[GuessThePuncherClient] All remotes validated: 20 found"
  - Both should print "Phase 1 scaffold ready"

If you see warnings about missing Workspace objects, create them per MANUAL_OBJECTS.md.

If you see warnings about missing modules, check you copied all Shared files.

---

## Common Errors

- **"Missing ReplicatedStorage.Shared folder"**: You forgot to create Shared folder before copying ModuleScripts
- **"Failed to require Constants"**: ModuleScript named incorrectly (must be exactly Constants, case-sensitive)
- **"Missing RemoteEvents"**: Server auto-creates, but if client starts before server, it may warn briefly - wait a second and check again
- **"Services folder not found"**: Create ServerScriptService/Services folder

---

## File Types Matter

- `.server.luau` -> Script in Studio
- `.client.luau` -> LocalScript in Studio
- `.luau` (others) -> ModuleScript in Studio

Do NOT put .server.luau files as ModuleScript, they won't run.

