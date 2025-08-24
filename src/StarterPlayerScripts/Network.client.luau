--!strict
local CollectionService = game:GetService("CollectionService")

local CoreRemote: RemoteEvent = game.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StartCharacterAnimation") :: RemoteEvent
local Player: Player = game.Players.LocalPlayer

type AnimationData = {string}

CoreRemote.OnClientEvent:Connect(function(data: AnimationData)
    print("Received animation data:", data)
    local animFolders = CollectionService:GetTagged(tostring(Player.UserId) .. "_Animations")
    local animFolder: Folder? = if #animFolders > 0 then animFolders[1] :: Folder else nil
    local animName: string = data[1]

    if not animFolder then
        warn("No animation folder found for player", Player.Name)
        return
    end

    repeat task.wait() until #animFolder:GetChildren() > 0
    if #animFolder:GetChildren() == 0 then
        warn("Animation folder is empty for player", Player.Name)
        return
    end

    local myAnimClip: Animation? = animFolder:FindFirstChild(animName) :: Animation?
    if not myAnimClip then
        warn("Animation clip not found:", animName)
        return
    end

    local character = Player.Character
    if not character then
        warn("Character not found for player", Player.Name)
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("Humanoid not found in character for player", Player.Name)
        return
    end

    local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        task.spawn(function()
            for _, anim in animFolder:GetChildren() do
                if anim:IsA("Animation") then
                    animator:LoadAnimation(anim :: Animation)
                end
            end
        end)
        local clip: AnimationTrack = animator:LoadAnimation(myAnimClip)
        print("Loaded animation clip:", clip)
        clip.Looped = true
        clip:Play()
    end
end)