--!strict
-- WeaponService: unified weapon handling with OnAttack/OnHit and configs

local _ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(game.ReplicatedStorage.Modules.Types.Enums)
local CharacterTypes = require(game.ServerStorage.Modules.Types.CharacterTypes)
local WeaponTypes = require(game.ServerStorage.Modules.Types.WeaponTypes)

export type WeaponAction = Enums.WeaponAction
export type WeaponId = Enums.WeaponId
export type WeaponHandler = WeaponTypes.WeaponHandler

local WeaponService = {}
WeaponService.__index = WeaponService

function WeaponService.New()
    local self = setmetatable({}, WeaponService)
    self._handlers = {} :: {[WeaponId]: WeaponHandler}
    self._equipped = {} :: {[number]: WeaponId}
    return self
end

function WeaponService:RegisterWeapon(id: WeaponId, handler: WeaponHandler)
    -- Upgrade legacy handlers that define OnAction but not OnAttack/OnHit
    if handler and not handler.OnAttack and (handler :: any).OnAction then
        local legacy = handler :: any
        handler.OnAttack = function(ctx)
            return legacy.OnAction({ character = ctx.character, action = ctx.action })
        end
        handler.OnHit = function()
            return true
        end
    end
    self._handlers[id] = handler
end

function WeaponService:Equip(playerId: number, weaponId: WeaponId)
    self._equipped[playerId] = weaponId
end

function WeaponService:GetEquipped(playerId: number): WeaponId
    return self._equipped[playerId] or Enums.WeaponId.Default
end

function WeaponService:Primary(player: Player, action: WeaponAction): boolean
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local character = Character:GetCharacterData(player)
    if not character then return false end
    local weaponId = self:GetEquipped(player.UserId)
    local handler = self._handlers[weaponId]
    if not handler then return false end
    -- Build attack context
    local ctx = {
        character = character,
        action = action,
        config = handler.config,
    }
    local ok = true
    if handler.OnAttack then
        ok = (handler.OnAttack :: any)(ctx)
    elseif (handler :: any).OnAction then
        ok = (handler :: any).OnAction({ character = character, action = action })
    end
    return ok and true or false
end

-- Report a hit from weapon systems (e.g., hitbox/raycast). Accepts Player or Instance as target.
function WeaponService:Hit(player: Player, target: Instance | Player, extra: {[string]: any}?): boolean
    local Character = require(game.ServerStorage.Modules.Entities.Character)
    local attacker = Character:GetCharacterData(player)
    if not attacker then return false end
    local weaponId = self:GetEquipped(player.UserId)
    local handler = self._handlers[weaponId]
    if not handler then return false end

    local targetCharacter: CharacterTypes.Character? = nil
    local targetModel: Model? = nil
    local hitPart: BasePart? = nil

    if typeof(target) == "Instance" then
        hitPart = target :: any
        targetModel = hitPart:FindFirstAncestorOfClass("Model")
        if targetModel then
            local plr = game.Players:GetPlayerFromCharacter(targetModel)
            if plr then
                targetCharacter = Character:GetCharacterData(plr)
            end
        end
    else
        targetCharacter = Character:GetCharacterData(target :: any)
        targetModel = targetCharacter and targetCharacter.Character or nil
    end

    local ctx = {
        attacker = attacker,
        target = targetCharacter,
        targetModel = targetModel,
        hitPart = hitPart,
        damageOverride = extra and extra.damage or nil,
        canBlock = extra and extra.canBlock,
        config = handler.config,
    }
    if handler.OnHit then
        local ok = (handler.OnHit :: any)(ctx)
        return ok and true or false
    end
    return true
end

return WeaponService
