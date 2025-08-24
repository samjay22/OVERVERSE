--!strict
-- AbilityDisplay: Modern, clean ability UI with smooth animations
-- Features circular ability icons with radial cooldown sweeps

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for modules
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utility = Modules:WaitForChild("Utility")
local Configuration = Modules:WaitForChild("Configuration")

-- Import modules
local ClientAbilityStateManager = require(Utility:WaitForChild("ClientAbilityStateManager"))
local AbilityCategoryRegistry = require(Utility:WaitForChild("AbilityCategoryRegistry"))
local AbilityConfiguration = require(Configuration:WaitForChild("AbilityConfiguration"))
local ResourceTypes = require(Configuration:WaitForChild("ResourceTypes"))
local UIThemes = require(Configuration:WaitForChild("UIThemes"))

-- Get instances
local stateManager = ClientAbilityStateManager.GetInstance()
local registry = AbilityCategoryRegistry.GetInstance()

-- Configuration
local ICON_SIZE = 72  -- Larger icons
local ICON_SPACING = 16  -- More breathing room
local CORNER_RADIUS = 16  -- Rounder corners
local ANIMATION_SPEED = 0.2  -- Smoother animations
local GLOW_INTENSITY = 0.8
local BACKDROP_BLUR = 12

-- Create main UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AbilityDisplay"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10
screenGui.Parent = PlayerGui

-- Background panel with glass effect
local backgroundPanel = Instance.new("Frame")
backgroundPanel.Name = "BackgroundPanel"
backgroundPanel.Size = UDim2.new(0, 600, 0, 120)
backgroundPanel.Position = UDim2.new(0.5, 0, 1, -140)
backgroundPanel.AnchorPoint = Vector2.new(0.5, 1)
backgroundPanel.BackgroundColor3 = Color3.new(0.02, 0.02, 0.03)
backgroundPanel.BackgroundTransparency = 0.15
backgroundPanel.BorderSizePixel = 0
backgroundPanel.Parent = screenGui

local bgCorner = Instance.new("UICorner")
bgCorner.CornerRadius = UDim.new(0, 24)
bgCorner.Parent = backgroundPanel

local bgGradient = Instance.new("UIGradient")
bgGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
    ColorSequenceKeypoint.new(0.5, Color3.new(0.9, 0.9, 0.95)),
    ColorSequenceKeypoint.new(1, Color3.new(0.8, 0.8, 0.85))
})
bgGradient.Rotation = 90
bgGradient.Parent = backgroundPanel

-- Main container
local mainFrame = Instance.new("Frame")
mainFrame.Name = "AbilityContainer"
mainFrame.Size = UDim2.new(1, -40, 1, -20)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundTransparency = 1
mainFrame.Parent = backgroundPanel

-- Create ability slot
local function createAbilitySlot(abilityDef, index: number)
    local slotFrame = Instance.new("Frame")
    slotFrame.Name = abilityDef.id
    slotFrame.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
    slotFrame.BackgroundColor3 = Color3.new(0.08, 0.08, 0.1)
    slotFrame.BorderSizePixel = 0
    slotFrame.Parent = mainFrame
    
    -- Position calculation
    local totalWidth = #AbilityConfiguration.GetEnabledAbilities() * ICON_SIZE + (#AbilityConfiguration.GetEnabledAbilities() - 1) * ICON_SPACING
    local startX = (560 - totalWidth) / 2  -- Adjusted for new container width
    slotFrame.Position = UDim2.new(0, startX + (index - 1) * (ICON_SIZE + ICON_SPACING), 0.5, 0)
    slotFrame.AnchorPoint = Vector2.new(0, 0.5)
    
    -- Add shadow for depth
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 12, 1, 12)
    shadow.Position = UDim2.new(0.5, 0, 0.5, 4)
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
    shadow.ImageColor3 = Color3.new(0, 0, 0)
    shadow.ImageTransparency = 0.5
    shadow.ZIndex = 0
    shadow.Parent = slotFrame
    
    -- Round corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, CORNER_RADIUS)
    corner.Parent = slotFrame
    
    -- Gradient border effect
    local border = Instance.new("UIStroke")
    border.Color = abilityDef.ui.color
    border.Thickness = 2
    border.Transparency = 0.6
    border.Parent = slotFrame
    
    local borderGradient = Instance.new("UIGradient")
    borderGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(0.5, Color3.new(0.9, 0.9, 0.9)),
        ColorSequenceKeypoint.new(1, Color3.new(0.8, 0.8, 0.8))
    })
    borderGradient.Rotation = -45
    borderGradient.Parent = border
    
    -- Icon background with gradient
    local iconBg = Instance.new("Frame")
    iconBg.Name = "IconBackground"
    iconBg.Size = UDim2.new(1, -6, 1, -6)
    iconBg.Position = UDim2.new(0, 3, 0, 3)
    iconBg.BackgroundColor3 = abilityDef.ui.color
    iconBg.BackgroundTransparency = 0.7
    iconBg.BorderSizePixel = 0
    iconBg.Parent = slotFrame
    
    local iconBgCorner = Instance.new("UICorner")
    iconBgCorner.CornerRadius = UDim.new(0, CORNER_RADIUS - 3)
    iconBgCorner.Parent = iconBg
    
    local iconGradient = Instance.new("UIGradient")
    iconGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.7, 0.7, 0.7))
    })
    iconGradient.Rotation = 45
    iconGradient.Parent = iconBg
    
    -- Ability icon with better design
    local iconFrame = Instance.new("Frame")
    iconFrame.Name = "IconFrame"
    iconFrame.Size = UDim2.new(0.7, 0, 0.7, 0)
    iconFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    iconFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    iconFrame.BackgroundTransparency = 1
    iconFrame.Parent = slotFrame
    
    local icon = Instance.new("TextLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(1, 0, 1, 0)
    icon.Position = UDim2.new(0.5, 0, 0.5, 0)
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.BackgroundTransparency = 1
    icon.Text = string.upper(string.sub(abilityDef.id, 4, 5) or string.sub(abilityDef.id, 1, 1))
    icon.TextColor3 = Color3.new(0.95, 0.95, 1)
    icon.TextScaled = true
    icon.Font = Enum.Font.Montserrat
    icon.TextStrokeTransparency = 0.8
    icon.TextStrokeColor3 = Color3.new(0, 0, 0)
    icon.Parent = iconFrame
    
    -- Cooldown overlay (radial)
    local cooldownFrame = Instance.new("Frame")
    cooldownFrame.Name = "CooldownOverlay"
    cooldownFrame.Size = UDim2.new(1, 0, 1, 0)
    cooldownFrame.BackgroundColor3 = Color3.new(0, 0, 0)
    cooldownFrame.BackgroundTransparency = 0.6
    cooldownFrame.BorderSizePixel = 0
    cooldownFrame.Visible = false
    cooldownFrame.Parent = slotFrame
    
    local cooldownCorner = Instance.new("UICorner")
    cooldownCorner.CornerRadius = UDim.new(0, CORNER_RADIUS)
    cooldownCorner.Parent = cooldownFrame
    
    -- Cooldown text
    local cooldownText = Instance.new("TextLabel")
    cooldownText.Name = "CooldownText"
    cooldownText.Size = UDim2.new(1, 0, 1, 0)
    cooldownText.BackgroundTransparency = 1
    cooldownText.Text = ""
    cooldownText.TextColor3 = Color3.new(1, 1, 1)
    cooldownText.TextScaled = false
    cooldownText.TextSize = 18
    cooldownText.Font = Enum.Font.GothamBold
    cooldownText.Parent = cooldownFrame
    
    -- Resource display (ammo/charges/energy)
    local resourceLabel = Instance.new("TextLabel")
    resourceLabel.Name = "ResourceLabel"
    resourceLabel.Size = UDim2.new(0.8, 0, 0, 16)
    resourceLabel.Position = UDim2.new(0.5, 0, 1, -18)
    resourceLabel.AnchorPoint = Vector2.new(0.5, 1)
    resourceLabel.BackgroundTransparency = 1
    resourceLabel.Text = ""
    resourceLabel.TextColor3 = Color3.new(1, 1, 1)
    resourceLabel.TextScaled = false
    resourceLabel.TextSize = 12
    resourceLabel.Font = Enum.Font.Gotham
    resourceLabel.Parent = slotFrame
    
    -- Keybind display
    local keybindFrame = Instance.new("Frame")
    keybindFrame.Name = "Keybind"
    keybindFrame.Size = UDim2.new(0, 24, 0, 24)
    keybindFrame.Position = UDim2.new(1, -2, 0, 2)
    keybindFrame.AnchorPoint = Vector2.new(1, 0)
    keybindFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.12)
    keybindFrame.BorderSizePixel = 0
    keybindFrame.Parent = slotFrame
    
    local keybindCorner = Instance.new("UICorner")
    keybindCorner.CornerRadius = UDim.new(0, 6)
    keybindCorner.Parent = keybindFrame
    
    local keybindStroke = Instance.new("UIStroke")
    keybindStroke.Color = Color3.new(0.2, 0.2, 0.25)
    keybindStroke.Thickness = 1
    keybindStroke.Parent = keybindFrame
    
    local keybindText = Instance.new("TextLabel")
    keybindText.Name = "KeyText"
    keybindText.Size = UDim2.new(1, 0, 1, 0)
    keybindText.BackgroundTransparency = 1
    keybindText.Text = abilityDef.ui.keyDisplay
    keybindText.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    keybindText.TextScaled = false
    keybindText.TextSize = 11
    keybindText.Font = Enum.Font.GothamSemibold
    keybindText.Parent = keybindFrame
    
    -- Ready pulse effect
    local pulseFrame = Instance.new("Frame")
    pulseFrame.Name = "PulseEffect"
    pulseFrame.Size = UDim2.new(1.2, 0, 1.2, 0)
    pulseFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    pulseFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    pulseFrame.BackgroundColor3 = abilityDef.ui.color
    pulseFrame.BackgroundTransparency = 1
    pulseFrame.BorderSizePixel = 0
    pulseFrame.ZIndex = 0
    pulseFrame.Parent = slotFrame
    
    local pulseCorner = Instance.new("UICorner")
    pulseCorner.CornerRadius = UDim.new(0, CORNER_RADIUS + 4)
    pulseCorner.Parent = pulseFrame
    
    -- Hover effect
    local hoverConnection
    hoverConnection = slotFrame.MouseEnter:Connect(function()
        TweenService:Create(
            border,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            {Color = abilityDef.ui.color, Transparency = 0}
        ):Play()
        
        TweenService:Create(
            slotFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            {Size = UDim2.new(0, ICON_SIZE + 4, 0, ICON_SIZE + 4)}
        ):Play()
    end)
    
    local leaveConnection
    leaveConnection = slotFrame.MouseLeave:Connect(function()
        TweenService:Create(
            border,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            {Color = Color3.new(0.15, 0.15, 0.18), Transparency = 0.5}
        ):Play()
        
        TweenService:Create(
            slotFrame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad),
            {Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)}
        ):Play()
    end)
    
    return {
        frame = slotFrame,
        iconBg = iconBg,
        icon = icon,
        cooldownFrame = cooldownFrame,
        cooldownText = cooldownText,
        resourceLabel = resourceLabel,
        keybindFrame = keybindFrame,
        pulseFrame = pulseFrame,
        border = border,
        abilityDef = abilityDef,
        pulseTween = nil :: Tween?,
    }
end

-- Update ability display
local function updateAbilityDisplay(slot, state)
    if not state then return end
    
    local displayInfo = ResourceTypes.GetDisplayInfo(state)
    if not displayInfo then return end
    
    -- Update resource display
    if state.type == "ammo" then
        slot.resourceLabel.Text = `{state.current}/{state.max}`
        slot.resourceLabel.TextColor3 = state.current > 0 and Color3.new(1, 1, 1) or Color3.new(1, 0.3, 0.3)
    elseif state.type == "charges" then
        local dots = string.rep("●", state.current) .. string.rep("○", state.max - state.current)
        slot.resourceLabel.Text = dots
        slot.resourceLabel.TextColor3 = state.current > 0 and Color3.new(1, 1, 1) or Color3.new(0.5, 0.5, 0.5)
    elseif state.type == "energy" then
        slot.resourceLabel.Text = `{math.floor(state.current)}%`
        slot.resourceLabel.TextColor3 = Color3.new(1, 0.8, 0.2):Lerp(Color3.new(1, 1, 1), state.current / state.max)
    elseif state.type == "heat" then
        local heatPercent = (state.current / state.max) * 100
        slot.resourceLabel.Text = string.format("%.0f°", heatPercent)
        slot.resourceLabel.TextColor3 = Color3.new(1, 1, 1):Lerp(Color3.new(1, 0.2, 0.2), state.current / state.max)
    else
        slot.resourceLabel.Text = ""
    end
    
    -- Update cooldown display
    local canUse = ResourceTypes.CanUseResource(state)
    
    -- Check fire rate too
    if canUse and state.fireRate and state.lastUseTime then
        local now = workspace:GetServerTimeNow()
        local timeSinceUse = now - state.lastUseTime
        if timeSinceUse < state.fireRate then
            canUse = false
        end
    end
    
    if not canUse then
        slot.cooldownFrame.Visible = true
        
        -- Show appropriate text
        if state.type == "cooldown" then
            local remaining = stateManager:GetRemainingCooldown(state.abilityId)
            if remaining > 0 then
                slot.cooldownText.Text = string.format("%.1f", remaining)
            else
                slot.cooldownText.Text = ""
            end
        elseif state.type == "ammo" and state.isReloading then
            local progress = stateManager:GetReloadProgress(state.abilityId)
            slot.cooldownText.Text = "RELOAD"
            slot.cooldownFrame.BackgroundTransparency = 0.3 + (0.3 * progress)
        elseif state.type == "heat" and state.metadata and state.metadata.overheated then
            slot.cooldownText.Text = "OVERHEAT"
            slot.cooldownFrame.BackgroundColor3 = Color3.new(1, 0.2, 0.2)
        else
            slot.cooldownText.Text = ""
        end
        
        -- Stop pulse
        if slot.pulseTween then
            slot.pulseTween:Cancel()
            slot.pulseTween = nil
            slot.pulseFrame.BackgroundTransparency = 1
        end
    else
        -- Ability is ready
        slot.cooldownFrame.Visible = false
        slot.cooldownText.Text = ""
        
        -- Add ready pulse if configured
        if slot.abilityDef.ui.pulseOnReady and not slot.pulseTween then
            slot.pulseTween = TweenService:Create(
                slot.pulseFrame,
                TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                {BackgroundTransparency = 0.7}
            )
            slot.pulseTween:Play()
        end
    end
    
    -- Flash on use
    if state.lastUseTime and workspace:GetServerTimeNow() - state.lastUseTime < 0.15 then
        local flash = TweenService:Create(
            slot.iconBg,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0.3}
        )
        flash:Play()
        flash.Completed:Connect(function()
            TweenService:Create(
                slot.iconBg,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                {BackgroundTransparency = 0.85}
            ):Play()
        end)
    end
end

-- Create ability slots
local abilitySlots = {}
local enabledAbilities = AbilityConfiguration.GetEnabledAbilities()

for i, abilityDef in ipairs(enabledAbilities) do
    local slot = createAbilitySlot(abilityDef, i)
    abilitySlots[abilityDef.id] = slot
end

-- Update loop
RunService.Heartbeat:Connect(function()
    for abilityId, slot in pairs(abilitySlots) do
        local state = stateManager:GetAbilityState(abilityId)
        if state then
            updateAbilityDisplay(slot, state)
        end
    end
end)

-- Add tooltip on hover
local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.Size = UDim2.new(0, 200, 0, 60)
tooltip.BackgroundColor3 = Color3.new(0.05, 0.05, 0.06)
tooltip.BorderSizePixel = 0
tooltip.Visible = false
tooltip.Parent = screenGui

local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, 8)
tooltipCorner.Parent = tooltip

local tooltipStroke = Instance.new("UIStroke")
tooltipStroke.Color = Color3.new(0.2, 0.2, 0.25)
tooltipStroke.Thickness = 1
tooltipStroke.Parent = tooltip

local tooltipTitle = Instance.new("TextLabel")
tooltipTitle.Name = "Title"
tooltipTitle.Size = UDim2.new(1, -10, 0, 20)
tooltipTitle.Position = UDim2.new(0, 5, 0, 5)
tooltipTitle.BackgroundTransparency = 1
tooltipTitle.Text = ""
tooltipTitle.TextColor3 = Color3.new(1, 1, 1)
tooltipTitle.TextScaled = false
tooltipTitle.TextSize = 14
tooltipTitle.Font = Enum.Font.GothamBold
tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
tooltipTitle.Parent = tooltip

local tooltipDesc = Instance.new("TextLabel")
tooltipDesc.Name = "Description"
tooltipDesc.Size = UDim2.new(1, -10, 0, 30)
tooltipDesc.Position = UDim2.new(0, 5, 0, 25)
tooltipDesc.BackgroundTransparency = 1
tooltipDesc.Text = ""
tooltipDesc.TextColor3 = Color3.new(0.7, 0.7, 0.7)
tooltipDesc.TextScaled = false
tooltipDesc.TextSize = 11
tooltipDesc.Font = Enum.Font.Gotham
tooltipDesc.TextXAlignment = Enum.TextXAlignment.Left
tooltipDesc.TextWrapped = true
tooltipDesc.Parent = tooltip

-- Tooltip functionality
for abilityId, slot in pairs(abilitySlots) do
    slot.frame.MouseEnter:Connect(function()
        tooltipTitle.Text = slot.abilityDef.displayName
        tooltipDesc.Text = slot.abilityDef.description or ""
        
        local mousePos = UserInputService:GetMouseLocation()
        tooltip.Position = UDim2.new(0, mousePos.X, 0, mousePos.Y - 70)
        tooltip.Visible = true
    end)
    
    slot.frame.MouseLeave:Connect(function()
        tooltip.Visible = false
    end)
end

print("[AbilityDisplay] Modern UI initialized")