--!nonstrict
-- Main.client.luau - Queue System Test Client
-- Purpose: Listens to queue state updates, prints for testing, allows join/leave via command bar
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient (LocalScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
print("[QueueClient] Starting for " .. player.Name)

local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 10)
if not sharedFolder then
	warn("[QueueClient] Missing Shared folder")
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotesFolder then
	warn("[QueueClient] Missing Remotes folder, waiting...")
	remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then return end
end

-- Listen to queue state updates
local stateUpdate = remotesFolder:WaitForChild("RE_QueueStateUpdate", 10)
if stateUpdate then
	stateUpdate.OnClientEvent:Connect(function(slotId, occupancyList, maxPlayers, state, countdownTimeLeft, locked, occupancyCount)
		print(string.format("[QueueClient] StateUpdate %s: %d/%d state=%s countdown=%.1f locked=%s players=%s", slotId, occupancyCount or #occupancyList, maxPlayers, state, countdownTimeLeft or 0, tostring(locked), table.concat(occupancyList, ",")))
	end)
	print("[QueueClient] Listening to RE_QueueStateUpdate")
end

local countdownUpdate = remotesFolder:FindFirstChild("RE_QueueCountdownUpdate")
if countdownUpdate then
	countdownUpdate.OnClientEvent:Connect(function(slotId, timeLeft)
		print(string.format("[QueueClient] Countdown %s: %.1f", slotId, timeLeft))
	end)
end

local lockedEvent = remotesFolder:FindFirstChild("RE_QueueLocked")
if lockedEvent then
	lockedEvent.OnClientEvent:Connect(function(slotId, locked)
		print(string.format("[QueueClient] Locked %s: %s", slotId, tostring(locked)))
	end)
end

local startedEvent = remotesFolder:FindFirstChild("RE_QueueStarted")
if startedEvent then
	startedEvent.OnClientEvent:Connect(function(slotId, players)
		print(string.format("[QueueClient] Started %s with %d players: %s - Handoff to MatchManager", slotId, #players, table.concat(players, ",")))
	end)
end

local playerLeftEvent = remotesFolder:FindFirstChild("RE_QueuePlayerLeft")
if playerLeftEvent then
	playerLeftEvent.OnClientEvent:Connect(function(slotId, userId)
		print(string.format("[QueueClient] PlayerLeft %s userId=%d", slotId, userId))
	end)
end

print("[QueueClient] Ready. To test join/leave from Command Bar (client):")
print("  game.ReplicatedStorage.Remotes.RE_QueueJoinRequest:FireServer('Slot2')")
print("  game.ReplicatedStorage.Remotes.RE_QueueLeaveRequest:FireServer()")
print("Or walk onto EntryArea part in Workspace.Lobby.MatchSlots.Slot2.EntryArea")
