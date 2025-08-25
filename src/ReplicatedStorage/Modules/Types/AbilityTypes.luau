export type Client = {
    AbilityEffects : Folder,
    AbilitySounds : Folder,
    InternalState : {
        Animations : {AnimationTrack},
        Effects : {Instance},
        Sounds : {Sound},
    },

    OnUse : (self: Client, player: Player) -> boolean,
    OnReplicate : (self: Client, player: Player) -> boolean,
    OnCancel : (self: Client, player: Player) -> boolean,
    GetCharacterAnimations : (self: Client, player: Player) -> Folder
}

export type Server = {
    Validate : (self: Server, player: Player) -> boolean
}

export type AbilityModule = {
    Enum : Enum.KeyCode | Enum.UserInputType,
    Client : Client,
    Server : Server,
}

return 0