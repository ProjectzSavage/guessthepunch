--!nonstrict
-- Main.client.luau - Queue + Match Setup Test Client
-- Purpose: Listens to queue and match state updates for testing
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient (LocalScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
print("[GuessThePuncherClient] Starting for " .. player.Name)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotesFolder then
	warn("[GuessThePuncherClient] Missing Remotes folder")
	return
end

-- Queue events
local stateUpdate = remotesFolder:WaitForChild("RE_QueueStateUpdate", 10)
if stateUpdate then
	stateUpdate.OnClientEvent:Connect(function(slotId, occupancyList, maxPlayers, state, countdownTimeLeft, locked, occupancyCount)
		print(string.format("[Queue] %s: %d/%d state=%s countdown=%.1f locked=%s", slotId, occupancyCount or #occupancyList, maxPlayers, state, countdownTimeLeft or 0, tostring(locked)))
	end)
	print("[QueueClient] Listening to RE_QueueStateUpdate")
end

local queueStarted = remotesFolder:FindFirstChild("RE_QueueStarted")
if queueStarted then
	queueStarted.OnClientEvent:Connect(function(slotId, players)
		print(string.format("[Queue] Started %s with %d players - handing off to MatchService", slotId, #players))
	end)
end

-- Match events
local matchStart = remotesFolder:FindFirstChild("RE_MatchStart")
if matchStart then
	matchStart.OnClientEvent:Connect(function(matchId, arenaName, players)
		print(string.format("[Match] Start matchId=%s arena=%s players=%d (%s)", matchId, arenaName, #players, table.concat(players, ",")))
	end)
end

local matchStateUpdate = remotesFolder:FindFirstChild("RE_MatchStateUpdate")
if matchStateUpdate then
	matchStateUpdate.OnClientEvent:Connect(function(payload)
		if payload then
			print(string.format("[Match] StateUpdate matchId=%s state=%s target=%s players=%d", tostring(payload.matchId), tostring(payload.state), tostring(payload.targetUserId), payload.players and #payload.players or 0))
			if payload.roles then
				for uid, role in pairs(payload.roles) do
					if uid == player.UserId then
						print(string.format("[Match] Your role: %s", role))
					end
				end
			end
		end
	end)
end

local matchEnd = remotesFolder:FindFirstChild("RE_MatchEnd")
if matchEnd then
	matchEnd.OnClientEvent:Connect(function(matchId, reason)
		print(string.format("[Match] End matchId=%s reason=%s - returning to lobby", matchId, reason))
	end)
end

local roleAssigned = remotesFolder:FindFirstChild("RE_RoleAssigned")
if roleAssigned then
	roleAssigned.OnClientEvent:Connect(function(matchId, role)
		print(string.format("[Match] RoleAssigned matchId=%s role=%s", matchId, role))
	end)
end

print("[GuessThePuncherClient] Ready - Queue + Match Setup Test Client")
print("  To join queue: game.ReplicatedStorage.Remotes.RE_QueueJoinRequest:FireServer('Slot2')")
print("  To leave queue: game.ReplicatedStorage.Remotes.RE_QueueLeaveRequest:FireServer()")
print("  Or walk onto EntryArea part")
