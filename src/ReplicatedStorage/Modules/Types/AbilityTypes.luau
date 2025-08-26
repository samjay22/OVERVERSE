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
    GetCharacterAnimations : (self: Client, player: Player) -> Folder,
    OnStateSync : (self: Client, syncData : {[string]: any}) -> boolean,
}

export type Server = {
    InternalState : {
        [string] : any
    },
    Validate : (self: Server, player: Player, onHitCallback : (target : Model?) -> nil, casterEntity : CharacterTypes.internalCharacter) -> boolean,
    OnUpdate : (self: Server, dt: number) -> boolean,
    _SyncToClient : (self: Server, player: Player, sm : any) -> boolean
}

export type AbilityModule = {
    Name : string,
    Enum : Enum.KeyCode | Enum.UserInputType,
    Client : Client,
    Server : Server,
}

return 0