--!nonstrict
local CollectionService = game:GetService("CollectionService")

local CoreRemote : RemoteEvent = game.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StartCharacterAnimation")

local Player : Player = game.Players.LocalPlayer

CoreRemote.OnClientEvent:Connect(function(data)
    local animFolder : Folder = CollectionService:GetTagged(tostring(Player.UserId) .. "_Animations")[1]
    local animName : string = data[1]

    if not animFolder or #animFolder:GetChildren() == 0 then
        warn("No animation folder found for player", Player.Name)
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
        clip.Looped = true
        clip:Play()
    end
end)