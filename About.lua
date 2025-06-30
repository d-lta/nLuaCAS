-- About.lua
-- Handles the About screen for nLuaCAS.
-- Exists mostly to reassure the user that something was built on purpose.
-- And to legally acknowledge the ancestry of the UI code.
platform.apilevel = "2.4"

local charProgress = 0 -- Total number of characters shown so far
local typingSpeed = 1.5 -- Characters revealed per frame

local timer = timer.start(0.05)

local logo = image.new(_R.IMG.logo)

-- UI heading string — shown at the top of the About card
local aboutTitle = "About nLuaCAS"
local author = "Created by DeltaDev"
local version = "v1.0 (2024)"

-- Multi-line description shown to the user
-- Mostly fluff, but technically accurate
local desc = {
    "nLuaCAS adds symbolic CAS features",
    "to non-CAS TI-Nspire calculators.",
    "Polynomial factoring, trig, GCD, LCM,",
    "and more.",
    "Derivative Work of SuperSpire by Xavier Andréani.",
    ""
}

-- License and attribution block
-- Required because SuperSpire’s code was borrowed (nicely)
local license = {
    "Engine: MIT  |  UI: CC BY-SA 2.0",
    "SuperSpire by Xavier Andréani",
    "Full credits in docs.",
    "Some constants derived from EEPro by adriweb and contributors"
}

-- Main render function for the About screen
-- Draws the title card and fills it with very polite text
-- Coordinates are semi-hardcoded because it's a calculator, not a game engine
function on.paint(gc)
    local w, h = platform.window:width(), platform.window:height()
    local boxW = math.min(300, w - 12)
    local boxH = 190 -- reduced from 200
    local boxX = math.floor((w - boxW) / 2)
    local boxY = math.floor((h - boxH) / 2) - 5 -- shift everything up slightly

    local totalTextLength = 0
    for _, line in ipairs(desc) do totalTextLength = totalTextLength + #line end
    for _, line in ipairs(license) do totalTextLength = totalTextLength + #line end

    -- Draw background card with updated calm blue tone and dark border
    gc:setColorRGB(100, 130, 255)
    gc:fillRect(boxX, boxY, boxW, boxH)
    gc:setColorRGB(40, 50, 90)
    gc:drawRect(boxX, boxY, boxW, boxH)

    -- Draw logo at the top of the card in the place where title text was previously
    local logoScale = 0.5 -- Adjust logo scaling as needed
    local logoW = image.width(logo) * logoScale
    local logoH = image.height(logo) * logoScale
    gc:drawImage(logo, boxX + (boxW - logoW) / 2 - 40, boxY + 5, logoW, logoH)

    -- Author and version info in lighter gray, shifted down by logoH + 4
    gc:setFont("sansserif", "r", 10)
    gc:setColorRGB(210, 220, 240)
    local aW = gc:getStringWidth(author)
    gc:drawString(author, boxX + (boxW - aW) / 2, boxY + 24 + logoH, "top")
    local vW = gc:getStringWidth(version)
    gc:drawString(version, boxX + (boxW - vW) / 2, boxY + 38 + logoH, "top")

    -- Main description text in consistent soft gray-blue, shifted down by logoH + 4
    gc:setFont("sansserif", "i", 9)
    gc:setColorRGB(220, 230, 250)
    local y = boxY + 55 + logoH
    local totalChars = 0
    for i=1,#desc do
        local line = desc[i]
        if totalChars + #line <= charProgress then
            -- Full line visible
            local lW = gc:getStringWidth(line)
            gc:drawString(line, boxX + (boxW - lW) / 2, y, "top")
        elseif totalChars < charProgress then
            -- Partial line visible
            local visible = math.max(0, charProgress - totalChars)
            local partial = string.sub(line, 1, visible)
            local lW = gc:getStringWidth(partial)
            gc:drawString(partial, boxX + (boxW - lW) / 2, y, "top")
        end
        totalChars = totalChars + #line
        y = y + 13
    end

    -- License and attribution in even lighter tone
    gc:setFont("sansserif", "r", 8)
    gc:setColorRGB(180, 200, 235)
    y = y - 3
    for i=1,#license do
        local line = license[i]
        if totalChars + #line <= charProgress then
            local lW = gc:getStringWidth(line)
            gc:drawString(line, boxX + (boxW - lW) / 2, y, "top")
        elseif totalChars < charProgress then
            local visible = math.max(0, charProgress - totalChars)
            local partial = string.sub(line, 1, visible)
            local lW = gc:getStringWidth(partial)
            gc:drawString(partial, boxX + (boxW - lW) / 2, y, "top")
        end
        totalChars = totalChars + #line
        y = y + 11
    end
end
function on.timer()
    local totalTextLength = 0
    for _, line in ipairs(desc) do totalTextLength = totalTextLength + #line end
    for _, line in ipairs(license) do totalTextLength = totalTextLength + #line end
    if charProgress < totalTextLength then
        charProgress = math.min(charProgress + typingSpeed, totalTextLength)
        platform.window:invalidate()
    end
    return 0.05
end