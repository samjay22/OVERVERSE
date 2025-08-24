--!strict
-- UIThemes: Customizable UI themes for the ability system
-- Provides themes and visual styles for ability displays

export type ColorScheme = {
    primary: Color3,
    secondary: Color3,
    accent: Color3,
    background: Color3,
    backgroundTransparent: Color3,
    text: Color3,
    textSecondary: Color3,
    success: Color3,
    warning: Color3,
    error: Color3,
    cooldown: Color3,
    ready: Color3,
    disabled: Color3,
}

export type AnimationStyle = {
    cooldownStyle: "fill" | "drain" | "pulse" | "sweep" | "radial",
    transitionSpeed: number,
    easingStyle: Enum.EasingStyle,
    easingDirection: Enum.EasingDirection,
    flashOnUse: boolean,
    flashDuration: number,
    flashColor: Color3?,
    shakeOnEmpty: boolean,
    shakeMagnitude: number,
    pulseOnReady: boolean,
    pulseSpeed: number,
    glowOnHover: boolean,
    glowIntensity: number,
}

export type BarStyle = {
    shape: "rectangle" | "rounded" | "hexagon" | "diamond",
    borderWidth: number,
    borderColor: Color3,
    fillDirection: "horizontal" | "vertical" | "radial",
    segmented: boolean,
    segmentCount: number?,
    gradientEnabled: boolean,
    gradientColors: {Color3}?,
    glassEffect: boolean,
    shadowEnabled: boolean,
    shadowOffset: Vector2,
    shadowColor: Color3,
}

export type TextStyle = {
    font: Enum.Font,
    textSize: number,
    textColor: Color3,
    textStrokeEnabled: boolean,
    textStrokeColor: Color3,
    textStrokeTransparency: number,
    textScaled: boolean,
    showKeybind: boolean,
    keybindPosition: "top" | "bottom" | "left" | "right" | "center",
    showCooldownText: boolean,
    cooldownFormat: "seconds" | "decimal" | "percentage",
    showResourceCount: boolean,
    resourcePosition: "overlay" | "below" | "above",
}

export type LayoutStyle = {
    arrangement: "horizontal" | "vertical" | "grid" | "radial",
    spacing: number,
    padding: UDim,
    alignment: "left" | "center" | "right" | "top" | "bottom",
    gridColumns: number?,
    gridRows: number?,
    radialStartAngle: number?,
    radialSpread: number?,
    scalingMode: "fixed" | "responsive" | "adaptive",
    baseSize: UDim2,
    minSize: Vector2?,
    maxSize: Vector2?,
}

export type IconStyle = {
    enabled: boolean,
    size: UDim2,
    position: UDim2,
    transparency: number,
    tintColor: Color3?,
    aspectRatio: number,
    scaleOnHover: boolean,
    hoverScale: number,
    rotateOnUse: boolean,
    rotationSpeed: number,
}

export type UITheme = {
    name: string,
    displayName: string,
    description: string?,
    author: string?,
    version: string,
    
    colors: ColorScheme,
    animations: AnimationStyle,
    bars: BarStyle,
    text: TextStyle,
    layout: LayoutStyle,
    icons: IconStyle,
    
    -- Category-specific overrides
    categoryOverrides: {[string]: {
        colors: ColorScheme?,
        animations: AnimationStyle?,
        bars: BarStyle?,
    }}?,
    
    -- Custom properties
    customProperties: {[string]: any}?,
}

-- Theme Registry
local UIThemes = {}
local registeredThemes: {[string]: UITheme} = {}
local activeTheme: string = "modern-dark"

-- Modern Dark Theme
local ModernDarkTheme: UITheme = {
    name = "modern-dark",
    displayName = "Modern Dark",
    description = "Clean, modern dark theme with vibrant accents",
    author = "System",
    version = "1.0.0",
    
    colors = {
        primary = Color3.fromRGB(45, 45, 50),
        secondary = Color3.fromRGB(60, 60, 65),
        accent = Color3.fromRGB(88, 166, 255),
        background = Color3.fromRGB(25, 25, 28),
        backgroundTransparent = Color3.fromRGB(25, 25, 28),
        text = Color3.fromRGB(255, 255, 255),
        textSecondary = Color3.fromRGB(180, 180, 180),
        success = Color3.fromRGB(98, 209, 98),
        warning = Color3.fromRGB(255, 195, 87),
        error = Color3.fromRGB(255, 87, 87),
        cooldown = Color3.fromRGB(150, 150, 150),
        ready = Color3.fromRGB(88, 255, 166),
        disabled = Color3.fromRGB(80, 80, 80),
    },
    
    animations = {
        cooldownStyle = "fill",
        transitionSpeed = 0.1,
        easingStyle = Enum.EasingStyle.Quad,
        easingDirection = Enum.EasingDirection.Out,
        flashOnUse = true,
        flashDuration = 0.15,
        flashColor = Color3.fromRGB(255, 255, 255),
        shakeOnEmpty = true,
        shakeMagnitude = 5,
        pulseOnReady = true,
        pulseSpeed = 1,
        glowOnHover = true,
        glowIntensity = 0.3,
    },
    
    bars = {
        shape = "rounded",
        borderWidth = 2,
        borderColor = Color3.fromRGB(70, 70, 75),
        fillDirection = "horizontal",
        segmented = false,
        gradientEnabled = true,
        gradientColors = {
            Color3.fromRGB(88, 166, 255),
            Color3.fromRGB(88, 255, 166),
        },
        glassEffect = true,
        shadowEnabled = true,
        shadowOffset = Vector2.new(2, 2),
        shadowColor = Color3.fromRGB(0, 0, 0),
    },
    
    text = {
        font = Enum.Font.Gotham,
        textSize = 14,
        textColor = Color3.fromRGB(255, 255, 255),
        textStrokeEnabled = true,
        textStrokeColor = Color3.fromRGB(0, 0, 0),
        textStrokeTransparency = 0.5,
        textScaled = false,
        showKeybind = true,
        keybindPosition = "bottom",
        showCooldownText = true,
        cooldownFormat = "decimal",
        showResourceCount = true,
        resourcePosition = "overlay",
    },
    
    layout = {
        arrangement = "horizontal",
        spacing = 8,
        padding = UDim.new(0, 12),
        alignment = "center",
        scalingMode = "responsive",
        baseSize = UDim2.new(0, 80, 0, 80),
    },
    
    icons = {
        enabled = true,
        size = UDim2.new(0.6, 0, 0.6, 0),
        position = UDim2.new(0.5, 0, 0.5, 0),
        transparency = 0.1,
        aspectRatio = 1,
        scaleOnHover = true,
        hoverScale = 1.1,
        rotateOnUse = false,
        rotationSpeed = 360,
    },
    
    categoryOverrides = {
        Primary = {
            colors = {
                primary = Color3.fromRGB(50, 40, 40),
                accent = Color3.fromRGB(255, 100, 100),
                ready = Color3.fromRGB(255, 150, 150),
            },
        },
        Ultimate = {
            colors = {
                primary = Color3.fromRGB(50, 45, 35),
                accent = Color3.fromRGB(255, 200, 50),
                ready = Color3.fromRGB(255, 220, 100),
            },
            animations = {
                pulseOnReady = true,
                pulseSpeed = 2,
                glowIntensity = 0.5,
            },
        },
    },
}

-- Neon Theme
local NeonTheme: UITheme = {
    name = "neon",
    displayName = "Neon",
    description = "Vibrant neon colors with glowing effects",
    author = "System",
    version = "1.0.0",
    
    colors = {
        primary = Color3.fromRGB(10, 10, 20),
        secondary = Color3.fromRGB(20, 20, 30),
        accent = Color3.fromRGB(255, 0, 255),
        background = Color3.fromRGB(0, 0, 0),
        backgroundTransparent = Color3.fromRGB(0, 0, 0),
        text = Color3.fromRGB(255, 255, 255),
        textSecondary = Color3.fromRGB(200, 200, 255),
        success = Color3.fromRGB(0, 255, 128),
        warning = Color3.fromRGB(255, 255, 0),
        error = Color3.fromRGB(255, 0, 128),
        cooldown = Color3.fromRGB(128, 0, 255),
        ready = Color3.fromRGB(0, 255, 255),
        disabled = Color3.fromRGB(40, 40, 40),
    },
    
    animations = {
        cooldownStyle = "pulse",
        transitionSpeed = 0.05,
        easingStyle = Enum.EasingStyle.Linear,
        easingDirection = Enum.EasingDirection.InOut,
        flashOnUse = true,
        flashDuration = 0.2,
        flashColor = Color3.fromRGB(255, 255, 255),
        shakeOnEmpty = false,
        shakeMagnitude = 0,
        pulseOnReady = true,
        pulseSpeed = 3,
        glowOnHover = true,
        glowIntensity = 0.8,
    },
    
    bars = {
        shape = "rectangle",
        borderWidth = 3,
        borderColor = Color3.fromRGB(255, 0, 255),
        fillDirection = "horizontal",
        segmented = true,
        segmentCount = 10,
        gradientEnabled = true,
        gradientColors = {
            Color3.fromRGB(255, 0, 255),
            Color3.fromRGB(0, 255, 255),
        },
        glassEffect = false,
        shadowEnabled = true,
        shadowOffset = Vector2.new(0, 0),
        shadowColor = Color3.fromRGB(255, 0, 255),
    },
    
    text = {
        font = Enum.Font.SciFi,
        textSize = 16,
        textColor = Color3.fromRGB(255, 255, 255),
        textStrokeEnabled = true,
        textStrokeColor = Color3.fromRGB(255, 0, 255),
        textStrokeTransparency = 0,
        textScaled = false,
        showKeybind = true,
        keybindPosition = "center",
        showCooldownText = true,
        cooldownFormat = "percentage",
        showResourceCount = true,
        resourcePosition = "overlay",
    },
    
    layout = {
        arrangement = "horizontal",
        spacing = 12,
        padding = UDim.new(0, 16),
        alignment = "center",
        scalingMode = "fixed",
        baseSize = UDim2.new(0, 90, 0, 90),
    },
    
    icons = {
        enabled = true,
        size = UDim2.new(0.7, 0, 0.7, 0),
        position = UDim2.new(0.5, 0, 0.5, 0),
        transparency = 0.2,
        tintColor = Color3.fromRGB(255, 0, 255),
        aspectRatio = 1,
        scaleOnHover = true,
        hoverScale = 1.2,
        rotateOnUse = true,
        rotationSpeed = 720,
    },
}

-- Minimal Theme
local MinimalTheme: UITheme = {
    name = "minimal",
    displayName = "Minimal",
    description = "Clean and minimal design",
    author = "System",
    version = "1.0.0",
    
    colors = {
        primary = Color3.fromRGB(240, 240, 240),
        secondary = Color3.fromRGB(220, 220, 220),
        accent = Color3.fromRGB(100, 100, 100),
        background = Color3.fromRGB(255, 255, 255),
        backgroundTransparent = Color3.fromRGB(255, 255, 255),
        text = Color3.fromRGB(50, 50, 50),
        textSecondary = Color3.fromRGB(120, 120, 120),
        success = Color3.fromRGB(76, 175, 80),
        warning = Color3.fromRGB(255, 152, 0),
        error = Color3.fromRGB(244, 67, 54),
        cooldown = Color3.fromRGB(200, 200, 200),
        ready = Color3.fromRGB(76, 175, 80),
        disabled = Color3.fromRGB(230, 230, 230),
    },
    
    animations = {
        cooldownStyle = "drain",
        transitionSpeed = 0.2,
        easingStyle = Enum.EasingStyle.Sine,
        easingDirection = Enum.EasingDirection.InOut,
        flashOnUse = false,
        flashDuration = 0,
        shakeOnEmpty = false,
        shakeMagnitude = 0,
        pulseOnReady = false,
        pulseSpeed = 0,
        glowOnHover = false,
        glowIntensity = 0,
    },
    
    bars = {
        shape = "rectangle",
        borderWidth = 1,
        borderColor = Color3.fromRGB(200, 200, 200),
        fillDirection = "horizontal",
        segmented = false,
        gradientEnabled = false,
        glassEffect = false,
        shadowEnabled = false,
        shadowOffset = Vector2.new(0, 0),
        shadowColor = Color3.fromRGB(0, 0, 0),
    },
    
    text = {
        font = Enum.Font.SourceSans,
        textSize = 12,
        textColor = Color3.fromRGB(50, 50, 50),
        textStrokeEnabled = false,
        textStrokeColor = Color3.fromRGB(255, 255, 255),
        textStrokeTransparency = 1,
        textScaled = false,
        showKeybind = true,
        keybindPosition = "top",
        showCooldownText = false,
        cooldownFormat = "seconds",
        showResourceCount = true,
        resourcePosition = "below",
    },
    
    layout = {
        arrangement = "horizontal",
        spacing = 4,
        padding = UDim.new(0, 8),
        alignment = "center",
        scalingMode = "responsive",
        baseSize = UDim2.new(0, 60, 0, 60),
    },
    
    icons = {
        enabled = false,
        size = UDim2.new(0.5, 0, 0.5, 0),
        position = UDim2.new(0.5, 0, 0.5, 0),
        transparency = 0.5,
        aspectRatio = 1,
        scaleOnHover = false,
        hoverScale = 1,
        rotateOnUse = false,
        rotationSpeed = 0,
    },
}

-- Register default themes
function UIThemes.RegisterDefaults()
    registeredThemes["modern-dark"] = ModernDarkTheme
    registeredThemes["neon"] = NeonTheme
    registeredThemes["minimal"] = MinimalTheme
end

-- Register custom theme
function UIThemes.RegisterTheme(theme: UITheme)
    if registeredThemes[theme.name] then
        warn(`[UIThemes] Theme {theme.name} already registered`)
        return false
    end
    
    registeredThemes[theme.name] = theme
    return true
end

-- Get theme
function UIThemes.GetTheme(themeName: string?): UITheme?
    local name = themeName or activeTheme
    return registeredThemes[name]
end

-- Set active theme
function UIThemes.SetActiveTheme(themeName: string): boolean
    if not registeredThemes[themeName] then
        warn(`[UIThemes] Theme {themeName} not found`)
        return false
    end
    
    activeTheme = themeName
    return true
end

-- Get active theme
function UIThemes.GetActiveTheme(): UITheme?
    return registeredThemes[activeTheme]
end

-- Get all themes
function UIThemes.GetAllThemes(): {[string]: UITheme}
    return table.clone(registeredThemes)
end

-- Apply theme to UI element
function UIThemes.ApplyToElement(element: GuiObject, theme: UITheme?, elementType: string?)
    theme = theme or UIThemes.GetActiveTheme()
    if not theme then return end
    
    -- Apply background color
    if element:IsA("Frame") or element:IsA("ImageLabel") or element:IsA("ImageButton") then
        element.BackgroundColor3 = theme.colors.primary
        element.BorderColor3 = theme.bars.borderColor
        element.BorderSizePixel = theme.bars.borderWidth
    end
    
    -- Apply text properties
    if element:IsA("TextLabel") or element:IsA("TextButton") or element:IsA("TextBox") then
        element.Font = theme.text.font
        element.TextColor3 = theme.text.textColor
        element.TextScaled = theme.text.textScaled
        if not theme.text.textScaled then
            element.TextSize = theme.text.textSize
        end
        element.TextStrokeColor3 = theme.text.textStrokeColor
        element.TextStrokeTransparency = theme.text.textStrokeTransparency
    end
end

-- Get interpolated color for progress
function UIThemes.GetProgressColor(theme: UITheme?, progress: number, elementType: string?): Color3
    theme = theme or UIThemes.GetActiveTheme()
    if not theme then
        return Color3.new(1, 1, 1)
    end
    
    if progress >= 1 then
        return theme.colors.ready
    elseif progress <= 0 then
        return theme.colors.disabled
    else
        -- Interpolate between cooldown and ready colors
        return theme.colors.cooldown:Lerp(theme.colors.ready, progress)
    end
end

-- Initialize with defaults
UIThemes.RegisterDefaults()

return UIThemes