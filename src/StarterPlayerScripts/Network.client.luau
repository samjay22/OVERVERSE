--!nonstrict
local CollectionService = game:GetService("CollectionService")

local CoreRemote : RemoteEvent = game.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StartCharacterAnimation")

local Player : Player = game.Players.LocalPlayer

CoreRemote.OnClientEvent:Connect(function(data)
    print("Received animation data:", data)
    local animFolders = CollectionService:GetTagged(tostring(Player.UserId) .. "_Animations")
    local animFolder : Folder? = animFolders and animFolders[1] :: Folder?
    local animName : string = data[1]

    if not animFolder then
        warn("No animation folder found for player", Player.Name)
        return
    end

    repeat task.wait() until #animFolder:GetChildren() > 0
    if #animFolder:GetChildren() == 0 then
        warn("Animation folder is empty for player", Player.Name)
        return
    end

    local myAnimClip : Animation? = animFolder:FindFirstChild(animName) :: Animation
    if not myAnimClip then
        warn("Animation clip not found:", animName)
        return
    end

    local humanoid = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")

    if not humanoid then
        warn("Humanoid not found in character for player", Player.Name)
        return
    end

    local animator : Animator? = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        local clip : AnimationTrack = animator:LoadAnimation(myAnimClip)
        print("Loaded animation clip:", clip)
        clip.Looped = true
        clip:Play()
    end
end)