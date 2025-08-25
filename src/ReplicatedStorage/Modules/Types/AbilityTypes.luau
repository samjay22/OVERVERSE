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
    InternalState : {
        [string] : any
    },
    Validate : (self: Server, player: Player, ctxExtra : {[string]: any}?) -> boolean,
    OnUpdate : (self: Server, dt: number) -> boolean
}

export type AbilityModule = {
    Name : string,
    Enum : Enum.KeyCode | Enum.UserInputType,
    Client : Client,
    Server : Server,
}

return 0