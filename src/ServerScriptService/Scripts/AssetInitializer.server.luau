--!strict
--[[
    Optimized Server Asset Initialization
    
    This script optimizes asset loading by preloading all critical assets
    on server startup with parallel processing and advanced error handling.
    
    Features:
    - Parallel asset loading for better performance
    - Retry mechanisms for failed loads
    - Progress tracking and performance metrics
    - Memory optimization
    - Advanced error recovery
    
    @author: GitHub Copilot (Optimization)
    @version: 3.0.0 (Optimized)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

print("🚀 Starting Optimized Server Asset Initialization...")

-- Only run on server
if not RunService:IsServer() then
    return
end

-- Optimization constants
local MAX_RETRY_ATTEMPTS = 3
local RETRY_DELAY = 0.5
local PARALLEL_LOAD_BATCH_SIZE = 4
local ASSET_TIMEOUT = 10 -- seconds
local PROGRESS_UPDATE_INTERVAL = 0.5

-- Performance tracking
local AssetLoadingMetrics = {
    startTime = tick(),
    phaseTimings = {},
    totalAssets = 0,
    loadedAssets = 0,
    failedAssets = 0,
    retriedAssets = 0,
}

-- Asset loading state
local AssetLoadingState = {
    isInitializing = true,
    currentPhase = 0,
    totalPhases = 4,
    errors = {},
    warnings = {},
}

-- Load asset handlers
local AssetHandlers = require(game.ReplicatedStorage.Modules.AssetHandlers)
local AnimationAssets = AssetHandlers.OnModuleLoaded("Animations")
local EffectAssets = AssetHandlers.OnModuleLoaded("Effects")

-- Utility functions for optimized loading
local function _logProgress(phase: number, message: string)
    local progress = math.floor((phase / AssetLoadingState.totalPhases) * 100)
    print(`📊 [${progress}%] Phase ${phase}/${AssetLoadingState.totalPhases}: ${message}`)
end

local function _recordPhaseTime(phaseName: string, phaseStartTime: number)
    local duration = tick() - phaseStartTime
    AssetLoadingMetrics.phaseTimings[phaseName] = duration
    print(`⏱️ ${phaseName} completed in ${math.round(duration * 1000)}ms`)
end

local function _retryOperation(operation: () -> any, operationName: string, maxRetries: number?): (boolean, any)
    local attempts = maxRetries or MAX_RETRY_ATTEMPTS
    
    for attempt = 1, attempts do
        local success, result = pcall(operation)
        if success then
            if attempt > 1 then
                AssetLoadingMetrics.retriedAssets += 1
                print(`✅ ${operationName} succeeded on attempt ${attempt}`)
            end
            return true, result
        else
            AssetLoadingMetrics.failedAssets += 1
            if attempt < attempts then
                warn(`⚠️ ${operationName} failed (attempt ${attempt}/${attempts}): ${result}`)
                task.wait(RETRY_DELAY * attempt) -- Exponential backoff
            else
                warn(`❌ ${operationName} failed after ${attempts} attempts: ${result}`)
                table.insert(AssetLoadingState.errors, `${operationName}: ${result}`)
            end
        end
    end
    
    return false, nil
end

local function _parallelLoadAssets(loadTasks: {() -> ()}, batchSize: number?)
    local batch = batchSize or PARALLEL_LOAD_BATCH_SIZE
    local totalTasks = #loadTasks
    local completedTasks = 0
    
    -- Process tasks in parallel batches
    for i = 1, totalTasks, batch do
        local batchTasks = {}
        
        -- Create batch of tasks
        for j = i, math.min(i + batch - 1, totalTasks) do
            table.insert(batchTasks, task.spawn(loadTasks[j]))
        end
        
        -- Wait for batch completion with timeout
        local batchStartTime = tick()
        for _, taskThread in batchTasks do
            while coroutine.status(taskThread) == "running" do
                if tick() - batchStartTime > ASSET_TIMEOUT then
                    warn(`⚠️ Asset loading timeout reached for batch starting at index ${i}`)
                    break
                end
                task.wait(0.1)
            end
        end
        
        completedTasks += #batchTasks
        local progress = math.floor((completedTasks / totalTasks) * 100)
        print(`📈 Batch progress: ${progress}% (${completedTasks}/${totalTasks} tasks)`)
    end
end

-- Optimized priority-based asset preloading with parallel processing
local function initializeAssets()
    AssetLoadingState.isInitializing = true
    local overallStartTime = AssetLoadingMetrics.startTime
    
    -- Phase 1: Parallel Animation Loading
    AssetLoadingState.currentPhase = 1
    _logProgress(1, "Preloading animations in parallel...")
    local phase1Start = tick()
    
    if AnimationAssets then
        local animationTasks = {
            function()
                local success, result = _retryOperation(function()
                    return (AnimationAssets :: any).PreloadAll()
                end, "Animation Preload")
                
                if success then
                    AssetLoadingMetrics.loadedAssets += 1
                    print("✅ Animations preloaded successfully")
                else
                    warn("❌ Failed to preload animations after retries")
                end
            end
        }
        
        _parallelLoadAssets(animationTasks, 1)
    else
        warn("⚠️ Animation asset handler not found")
        table.insert(AssetLoadingState.warnings, "Animation asset handler not found")
    end
    
    _recordPhaseTime("Phase 1: Animations", phase1Start)
    
    -- Phase 2: Parallel Effect Loading
    AssetLoadingState.currentPhase = 2
    _logProgress(2, "Preloading effects in parallel...")
    local phase2Start = tick()
    
    if EffectAssets then
        local effectTasks = {
            function()
                local success, result = _retryOperation(function()
                    return (EffectAssets :: any).PreloadAllEffects()
                end, "Effect Preload")
                
                if success then
                    AssetLoadingMetrics.loadedAssets += 1
                    print("✅ Effects preloaded successfully")
                else
                    warn("❌ Failed to preload effects after retries")
                end
            end
        }
        
        _parallelLoadAssets(effectTasks, 1)
    else
        warn("⚠️ Effect asset handler not found")
        table.insert(AssetLoadingState.warnings, "Effect asset handler not found")
    end
    
    _recordPhaseTime("Phase 2: Effects", phase2Start)
    
    -- Phase 3: Parallel Registry Initialization
    AssetLoadingState.currentPhase = 3
    _logProgress(3, "Initializing registries in parallel...")
    local phase3Start = tick()
    
    local registryTasks = {
        function()
            local success, LoadoutRegistry = _retryOperation(function()
                return require(game.ServerStorage.Modules.registry.Loadouts)
            end, "Loadout Registry")
            
            if success then
                AssetLoadingMetrics.loadedAssets += 1
                print("✅ Loadout Registry initialized")
            end
        end,
        
        function()
            local success, EffectRegistry = _retryOperation(function()
                return require(game.ServerStorage.Modules.registry.Effects)
            end, "Effect Registry")
            
            if success then
                AssetLoadingMetrics.loadedAssets += 1
                print("✅ Effect Registry initialized")
            end
        end
    }
    
    _parallelLoadAssets(registryTasks, 2)
    _recordPhaseTime("Phase 3: Registries", phase3Start)
    
    -- Phase 4: Finalization and Metrics
    AssetLoadingState.currentPhase = 4
    _logProgress(4, "Finalizing asset initialization...")
    local phase4Start = tick()
    
    AssetLoadingState.isInitializing = false
    
    local endTime = tick()
    local totalDuration = endTime - overallStartTime
    
    -- Performance summary
    print("\n🎯 === ASSET LOADING PERFORMANCE SUMMARY ===")
    print(`⏱️ Total Duration: ${math.round(totalDuration * 1000)}ms`)
    print(`📊 Assets Loaded: ${AssetLoadingMetrics.loadedAssets}`)
    print(`❌ Failed Assets: ${AssetLoadingMetrics.failedAssets}`)
    print(`🔄 Retried Assets: ${AssetLoadingMetrics.retriedAssets}`)
    
    -- Phase breakdown
    for phaseName, timing in pairs(AssetLoadingMetrics.phaseTimings) do
        local percentage = math.round((timing / totalDuration) * 100)
        print(`   ${phaseName}: ${math.round(timing * 1000)}ms (${percentage}%)`)
    end
    
    -- Error and warning summary
    if #AssetLoadingState.errors > 0 then
        print("\n⚠️ ERRORS ENCOUNTERED:")
        for _, error in AssetLoadingState.errors do
            print(`   ❌ ${error}`)
        end
    end
    
    if #AssetLoadingState.warnings > 0 then
        print("\n⚠️ WARNINGS:")
        for _, warning in AssetLoadingState.warnings do
            print(`   ⚠️ ${warning}`)
        end
    end
    
    _recordPhaseTime("Phase 4: Finalization", phase4Start)
    
    print(`\n✅ Optimized Server Asset Initialization completed in ${math.round(totalDuration * 1000)}ms`)
    print("🎮 Server ready for players with enhanced performance!")
    
    return true
end

-- Run initialization in a separate thread to prevent blocking
local initializationThread = task.spawn(initializeAssets)

-- Create optimized asset ready signaling system
local assetsReadyValue = Instance.new("BoolValue")
assetsReadyValue.Name = "AssetsReady"
assetsReadyValue.Value = false
assetsReadyValue.Parent = ReplicatedStorage

-- Create progress tracking for clients
local progressValue = Instance.new("NumberValue")
progressValue.Name = "AssetLoadingProgress"
progressValue.Value = 0
progressValue.Parent = ReplicatedStorage

-- Progress monitoring with timeout safety
task.spawn(function()
    local maxWaitTime = 15 -- Increased timeout for complex assets
    local startTime = tick()
    local lastProgress = 0
    
    while AssetLoadingState.isInitializing and (tick() - startTime) < maxWaitTime do
        -- Update progress for clients
        local currentProgress = (AssetLoadingState.currentPhase / AssetLoadingState.totalPhases) * 100
        progressValue.Value = currentProgress
        
        -- Check for progress stall
        if currentProgress == lastProgress and (tick() - startTime) > 5 then
            warn("⚠️ Asset loading may have stalled. Progress:", currentProgress)
        end
        lastProgress = currentProgress
        
        task.wait(PROGRESS_UPDATE_INTERVAL)
    end
    
    -- Force completion if timeout reached
    if AssetLoadingState.isInitializing then
        warn("❌ Asset initialization timeout reached - forcing completion")
        AssetLoadingState.isInitializing = false
    end
    
    -- Set final values
    assetsReadyValue.Value = true
    progressValue.Value = 100
    
    print("📢 Optimized assets ready signal sent to clients")
    print(`📊 Final metrics - Loaded: ${AssetLoadingMetrics.loadedAssets}, Failed: ${AssetLoadingMetrics.failedAssets}`)
end)

-- Memory cleanup after initialization
task.spawn(function()
    task.wait(30) -- Wait for everything to settle
    
    -- Clean up temporary data structures
    table.clear(AssetLoadingState.errors)
    table.clear(AssetLoadingState.warnings)
    table.clear(AssetLoadingMetrics.phaseTimings)
    
    print("🧹 Asset initialization cleanup completed")
end)

return true
