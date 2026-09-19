--!nonstrict
-- RemoteService.luau
-- Purpose: Auto-creates RemoteEvents if missing, as requested
-- Roblox Studio Destination: ServerScriptService > Services > RemoteService (ModuleScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteService = {}

function RemoteService.EnsureFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
		print("[RemoteService] Created ReplicatedStorage.Remotes folder")
	end
	return folder
end

function RemoteService.EnsureRemote(name: string): RemoteEvent
	local folder = RemoteService.EnsureFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		warn("[RemoteService] Object " .. name .. " exists but not RemoteEvent, recreating")
		existing:Destroy()
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = folder
	print("[RemoteService] Auto-created RemoteEvent: " .. name)
	return re
end

function RemoteService.EnsureAllRemotes(names: {string})
	for _, name in ipairs(names) do
		RemoteService.EnsureRemote(name)
	end
end

function RemoteService.GetRemote(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then return nil end
	local obj = folder:FindFirstChild(name)
	if obj and obj:IsA("RemoteEvent") then
		return obj
	end
	return nil
end

return RemoteService
