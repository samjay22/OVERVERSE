--!strict
-- Setup script for Remotes folder and events

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create Remotes folder if it doesn't exist
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
    remotes = Instance.new("Folder")
    remotes.Name = "Remotes"
    remotes.Parent = ReplicatedStorage
end

-- Create required RemoteEvents
local requiredRemotes = {
    "AbilityValidation",
    "AbilityPrediction", -- legacy client predictor
}

for _, remoteName in ipairs(requiredRemotes) do
    local remote = remotes:FindFirstChild(remoteName)
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = remoteName
        remote.Parent = remotes
        print(`Created RemoteEvent: {remoteName}`)
    end
end

print("Remotes setup complete!")
print("Available RemoteEvents:")
for _, child in ipairs(remotes:GetChildren()) do
    if child:IsA("RemoteEvent") then
        print(`- {child.Name}`)
    end
end
