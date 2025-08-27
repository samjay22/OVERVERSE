--!strict

export type DamageType = "Physical" | "Magical" | "True" | "Fire" | "Ice" | "Lightning" | "Poison" | "Holy" | "Dark"

export type TargetingType = "Self" | "Targeted" | "Aimed" | "Area" | "Cone" | "Line" | "Chain" | "Random" | "All"

export type ResourceType = "Health" | "Mana" | "Stamina" | "Energy" | "Rage" | "Focus" | "Charges" | "Ammo" | "Custom"

export type EffectType = 
    "Damage" | "Heal" | "Shield" | "Buff" | "Debuff" | "Stun" | "Slow" | "Root" | 
    "Silence" | "Knockback" | "Pull" | "Teleport" | "Summon" | "Transform" | 
    "Projectile" | "Area" | "Dash" | "Channel" | "Toggle" | "Passive" | "Aura" | 
    "Reflect" | "Absorb" | "Cleanse" | "Dispel" | "Steal" | "Copy" | "Morph" |
    "Execute" | "Resurrect" | "Banish" | "Polymorph" | "Fear" | "Charm" | "Taunt" |
    "Invisible" | "Reveal" | "Mark" | "Link" | "Swap" | "Custom"

export type AbilityType = "Instant" | "Channeled" | "Toggle" | "Passive" | "Charged" | "Combo" | "Ultimate"

export type ActivationType = "Press" | "Hold" | "Release" | "DoublePress" | "Charge" | "Sequence"

export type ScalingType = {
    level: number?,
    attackPower: number?,
    spellPower: number?,
    maxHealth: number?,
    missingHealth: number?,
    targetMaxHealth: number?,
    targetMissingHealth: number?,
    distance: number?,
    chargeTime: number?,
    comboCount: number?,
    stackCount: number?,
    custom: { [string]: number }?
}

export type ValueRange = {
    min: number,
    max: number,
    scaling: ScalingType?
}

export type ScalableValue = {
    base: number,
    scaling: ScalingType?,
    modifiable: boolean?
}

export type ResourceRequirement = {
    type: ResourceType,
    amount: number | ScalableValue,
    consumeOnUse: boolean?,
    refundOnCancel: boolean?
}

export type TargetFilter = {
    team: ("Ally" | "Enemy" | "Neutral" | "All")?,
    type: ("Player" | "NPC" | "Object" | "All")?,
    status: ("Alive" | "Dead" | "All")?,
    hasEffect: string?,
    notHasEffect: string?,
    healthPercent: { min: number?, max: number? }?,
    custom: ((target: Instance) -> boolean)?
}

export type TargetingConfig = {
    type: TargetingType,
    range: number?,
    radius: number?,
    angle: number?, -- For cone targeting
    width: number?, -- For line targeting
    height: number?, -- For vertical range
    maxTargets: number?,
    filter: TargetFilter?,
    requireLineOfSight: boolean?,
    ignoreObstacles: boolean?,
    penetrating: boolean?,
    bounces: number?, -- For chain targeting
    falloff: number? -- Damage reduction per bounce/distance
}

export type EffectConfig = {
    type: EffectType,
    trigger: "OnCast" | "OnHit" | "OnChannel" | "OnEnd" | "OnKill" | "OnDamaged" | "Periodic" | "Conditional",
    
    -- Damage/Heal
    amount: (number | ScalableValue | ValueRange)?,
    damageType: DamageType?,
    canCrit: boolean?,
    critMultiplier: number?,
    
    -- Duration effects
    duration: number?,
    tickRate: number?,
    maxStacks: number?,
    refreshable: boolean?,
    
    -- Movement effects
    distance: number?,
    speed: number?,
    direction: "Forward" | "Backward" | "ToTarget" | "FromTarget" | "Random"?,
    
    -- Conditional
    condition: ((caster: Instance, target: Instance?) -> boolean)?,
    chance: number?,
    
    -- Child effects
    effects: { EffectConfig }?,
    
    -- Custom data
    customData: { [string]: any }?
}

export type ComboConfig = {
    window: number, -- Time window to perform combo
    requirements: {
        previousAbility: string?,
        hitCount: number?,
        targetMarked: string?,
        resourceThreshold: { type: ResourceType, amount: number }?
    },
    effects: { EffectConfig }, -- Additional effects when combo triggers
    resetOnMiss: boolean?,
    sharedCooldown: boolean?
}

export type VisualConfig = {
    -- Models/Parts
    projectileModel: string?,
    areaIndicator: string?,
    
    -- Particles
    castParticles: { string }?,
    travelParticles: { string }?,
    impactParticles: { string }?,
    persistentParticles: { string }?,
    
    -- Animations
    castAnimation: string?,
    channelAnimation: string?,
    impactAnimation: string?,
    
    -- Colors/Materials
    primaryColor: Color3?,
    secondaryColor: Color3?,
    material: Enum.Material?,
    transparency: number?,
    
    -- Lighting
    lightEmission: number?,
    lightInfluence: number?,
    
    -- Screen effects
    screenShake: {
        magnitude: number,
        duration: number,
        fadeIn: number,
        fadeOut: number
    }?,
    
    -- UI
    castBar: boolean?,
    rangeIndicator: boolean?,
    targetHighlight: boolean?
}

export type AudioConfig = {
    castSound: string?,
    channelSound: string?,
    travelSound: string?,
    impactSound: string?,
    successSound: string?,
    failSound: string?,
    
    volume: number?,
    pitch: number?,
    distanceFalloff: number?,
    
    customSounds: { [string]: string }?
}

export type AIConfig = {
    priority: number, -- AI priority for ability selection
    preferredRange: { min: number, max: number },
    targetPreference: "Closest" | "Furthest" | "LowestHealth" | "HighestHealth" | "MostDamaged" | "Random",
    conditions: {
        minTargets: number?,
        maxTargets: number?,
        selfHealthPercent: { min: number?, max: number? }?,
        targetHealthPercent: { min: number?, max: number? }?,
        allyCount: { min: number?, max: number? }?,
        enemyCount: { min: number?, max: number? }?
    }
}

export type AbilityDefinition = {
    -- Identification
    id: string,
    name: string,
    description: string?,
    icon: string?,
    category: string?,
    tags: { string }?,
    
    -- Core Properties
    type: AbilityType,
    activation: ActivationType,
    slot: ("M1" | "M2" | "Q" | "E" | "R" | "F" | "Passive" | "Item" | number)?,
    
    -- Timing
    castTime: (number | ScalableValue)?,
    channelTime: (number | ScalableValue)?,
    cooldown: ScalableValue,
    globalCooldown: number?,
    charges: {
        max: number,
        rechargeTime: number,
        consumeOnCast: boolean?,
        sharedCharges: string? -- Share charges with another ability
    }?,
    
    -- Resources
    resources: { ResourceRequirement }?,
    generates: { ResourceRequirement }?, -- Resources generated on use
    
    -- Targeting
    targeting: TargetingConfig,
    
    -- Effects
    effects: { EffectConfig },
    
    -- Combos
    combos: { ComboConfig }?,
    combosWith: { string }?, -- Other abilities this combos with
    
    -- Requirements
    requirements: {
        level: number?,
        hasAbility: string?,
        hasEffect: string?,
        inCombat: boolean?,
        outOfCombat: boolean?,
        custom: ((caster: Instance) -> boolean)?
    }?,
    
    -- Modifiers (can be modified at runtime)
    modifiers: {
        cooldownReduction: number?,
        castTimeReduction: number?,
        rangeIncrease: number?,
        radiusIncrease: number?,
        damageIncrease: number?,
        costReduction: number?,
        custom: { [string]: number }?
    }?,
    
    -- Visuals
    visuals: VisualConfig?,
    
    -- Audio
    audio: AudioConfig?,
    
    -- AI
    ai: AIConfig?,
    
    -- Networking
    network: {
        predictable: boolean?, -- Can be predicted client-side
        authoritative: "Client" | "Server", -- Who has authority
        syncRate: number?, -- How often to sync state
        interpolate: boolean? -- Smooth visual interpolation
    }?,
    
    -- Callbacks
    callbacks: {
        onLearn: ((character: Instance) -> ())?,
        onForget: ((character: Instance) -> ())?,
        onCast: ((caster: Instance, target: Instance?) -> boolean)?,
        onHit: ((caster: Instance, target: Instance, damage: number?) -> ())?,
        onChannel: ((caster: Instance, progress: number) -> ())?,
        onInterrupt: ((caster: Instance, source: Instance?) -> ())?,
        onComplete: ((caster: Instance) -> ())?,
        onCooldownEnd: ((caster: Instance) -> ())?
    }?,
    
    -- Custom data
    customData: { [string]: any }?
}

export type AbilityModifier = {
    id: string,
    source: Instance?, -- What applied this modifier
    priority: number, -- Order of application
    duration: number?, -- nil for permanent
    stacks: number?,
    
    -- Stat modifications
    statModifiers: {
        cooldown: { flat: number?, percent: number? }?,
        castTime: { flat: number?, percent: number? }?,
        range: { flat: number?, percent: number? }?,
        radius: { flat: number?, percent: number? }?,
        damage: { flat: number?, percent: number? }?,
        healing: { flat: number?, percent: number? }?,
        cost: { flat: number?, percent: number? }?,
        duration: { flat: number?, percent: number? }?,
        custom: { [string]: { flat: number?, percent: number? } }?
    }?,
    
    -- Effect modifications
    effectModifiers: {
        add: { EffectConfig }?, -- Add new effects
        remove: { string }?, -- Remove effects by type
        modify: { [string]: any }? -- Modify existing effects
    }?,
    
    -- Behavioral modifications
    behaviorModifiers: {
        canCastWhileMoving: boolean?,
        canCastWhileStunned: boolean?,
        ignoreGlobalCooldown: boolean?,
        resetCooldownOnKill: boolean?,
        refundResourceOnKill: boolean?,
        piercing: boolean?,
        bouncing: number?,
        splitting: number?, -- Number of projectiles
        chaining: number?,
        custom: { [string]: any }?
    }?,
    
    -- Visual modifications
    visualModifiers: {
        colorOverride: Color3?,
        sizeMultiplier: number?,
        particleOverride: string?,
        animationOverride: string?,
        custom: { [string]: any }?
    }?
}

export type AbilityInstance = {
    definition: AbilityDefinition,
    owner: Instance,
    level: number,
    
    -- Runtime state
    cooldownRemaining: number,
    charges: number,
    lastCastTime: number,
    castCount: number,
    
    -- Active modifiers
    modifiers: { AbilityModifier },
    
    -- Computed values (with modifiers applied)
    computedStats: {
        cooldown: number,
        castTime: number,
        range: number,
        radius: number,
        damage: number,
        cost: { [ResourceType]: number },
        [string]: any
    },
    
    -- Methods
    canCast: (self: AbilityInstance, target: Instance?) -> (boolean, string?),
    execute: (self: AbilityInstance, target: Instance?) -> boolean,
    interrupt: (self: AbilityInstance, source: Instance?) -> (),
    addModifier: (self: AbilityInstance, modifier: AbilityModifier) -> (),
    removeModifier: (self: AbilityInstance, modifierId: string) -> (),
    getModifiedValue: (self: AbilityInstance, stat: string) -> any
}

export type AbilityEvent = {
    type: "Cast" | "Hit" | "Complete" | "Interrupt" | "Cooldown" | "Modify" | "Learn" | "Forget",
    ability: string,
    caster: Instance,
    target: Instance?,
    timestamp: number,
    data: { [string]: any }?
}

export type AbilityAnalytics = {
    abilityId: string,
    totalCasts: number,
    successfulCasts: number,
    interrupts: number,
    totalDamage: number,
    totalHealing: number,
    averageCooldown: number,
    averageCastTime: number,
    hitRate: number,
    critRate: number,
    resourceEfficiency: number,
    combosTriggered: number,
    modifierUptime: number,
    customMetrics: { [string]: number }
}

return {}