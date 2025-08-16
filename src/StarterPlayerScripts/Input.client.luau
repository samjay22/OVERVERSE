--!strict
-- Sends input begin/end to server for authoritative action handling

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS: UserInputService = game:GetService("UserInputService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local userInputRE: RemoteEvent = remotes:WaitForChild("UserInput")

-- Encode inputs compactly as numbers to reduce bandwidth and server work.
-- Convention: Keyboard = KeyCode.Value, Mouse buttons = OFFSET + UserInputType.Value
local OFFSET = 100000

local function encodeInput(input: InputObject): number?
    local it = input.UserInputType
    if it == Enum.UserInputType.Keyboard then
        local kc = input.KeyCode
        if kc ~= Enum.KeyCode.Unknown then
            return kc.Value
        end
        return nil
    end
    if it == Enum.UserInputType.MouseButton1 or it == Enum.UserInputType.MouseButton2 or it == Enum.UserInputType.MouseButton3 then
        return OFFSET + it.Value
    end
    return nil
end

UIS.InputBegan:Connect(function(input: InputObject, gp: boolean)
    if gp then return end
    local n = encodeInput(input)
    if not n then return end
    -- Send numeric-only payload for efficiency
    userInputRE:FireServer({ t = "B", n = n })
end)

UIS.InputEnded:Connect(function(input: InputObject, gp: boolean)
    if gp then return end
    local n = encodeInput(input)
    if not n then return end
    userInputRE:FireServer({ t = "E", n = n })
end)
