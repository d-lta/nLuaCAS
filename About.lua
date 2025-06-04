-- About.lua
-- Handles the About screen for nLuaCAS.
-- Exists mostly to reassure the user that something was built on purpose.
-- And to legally acknowledge the ancestry of the UI code.
platform.apilevel = "2.4"

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
    "",
    "Derivative Work of SuperSpire by Xavier Andréani."
}

-- License and attribution block
-- Required because SuperSpire’s code was borrowed (nicely)
local license = {
    "Engine: MIT  |  UI: CC BY-SA 2.0",
    "SuperSpire by Xavier Andréani",
    "Full credits in docs."
}

-- Main render function for the About screen
-- Draws the title card and fills it with very polite text
-- Coordinates are semi-hardcoded because it's a calculator, not a game engine
function on.paint(gc)
    local w, h = platform.window:width(), platform.window:height()
    local boxW = math.min(300, w - 12)
    local boxH = 200
    local boxX = math.floor((w - boxW) / 2)
    local boxY = math.floor((h - boxH) / 2)

    -- Draw the background card with a soft blue border
    -- It’s meant to look serious and calming
    gc:setColorRGB(120, 145, 255)
    gc:fillRect(boxX, boxY, boxW, boxH)
    gc:setColorRGB(0, 60, 120)
    gc:drawRect(boxX, boxY, boxW, boxH)

    -- Draw the About title centered near the top
    -- Looks slightly bolder for dramatic effect
    gc:setFont("sansserif", "b", 13)
    gc:setColorRGB(255, 255, 255)
    local tW = gc:getStringWidth(aboutTitle)
    gc:drawString(aboutTitle, boxX + (boxW - tW) / 2, boxY + 11, "top")

    -- Show author and version info below the title
    -- Required to satisfy software convention law
    gc:setFont("sansserif", "r", 10)
    gc:setColorRGB(230, 230, 255)
    local aW = gc:getStringWidth(author)
    gc:drawString(author, boxX + (boxW - aW) / 2, boxY + 30, "top")
    local vW = gc:getStringWidth(version)
    gc:drawString(version, boxX + (boxW - vW) / 2, boxY + 44, "top")

    -- Render the main description lines
    -- Centered and evenly spaced for fake elegance
    gc:setFont("sansserif", "i", 9)
    gc:setColorRGB(235, 235, 245)
    local y = boxY + 60
    for i=1,#desc do
        local line = desc[i]
        local lW = gc:getStringWidth(line)
        gc:drawString(line, boxX + (boxW - lW) / 2, y, "top")
        y = y + 13
    end

    -- Render license and attribution lines
    -- Obligatory Creative Commons mention goes here
    gc:setFont("sansserif", "r", 8)
    gc:setColorRGB(200, 220, 255)
    y = y + 2
    for i=1,#license do
        local line = license[i]
        local lW = gc:getStringWidth(line)
        gc:drawString(line, boxX + (boxW - lW) / 2, y, "top")
        y = y + 11
    end
end