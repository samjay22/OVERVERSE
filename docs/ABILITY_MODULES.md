Per-Ability Ability Modules (Client & Server)

Contract
- AbilityResult: { success: boolean, reason?: string, cooldowns?: { [abilityId: string]: number } }
- Client module interface:
  - onRequest(ctx) -> AbilityResult
  - onCast(ctx, serverData?) -> ()
  - OnCancel(ctx, reason?) -> ()
- Server module interface:
  - Execute(ctx) -> AbilityResult

Notes
- Keep results minimal: only return success and any cooldown updates.
- Cooldowns map values are absolute timestamps (server time) when the ability becomes available again.
- Validator applies only cooldowns and sends success/failure to the client.
- SharedAbilityLogic has been removed; logic lives in each module.

Locations
- Client: ReplicatedStorage/Modules/ClientAbilities/<Ability>.luau
- Server: ServerStorage/Modules/Abilities/Actives/<Ability>.luau
