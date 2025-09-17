-- platform.lua
-- Manages platform-specific settings, state persistence, and error handling.
-- This file must be loaded first to ensure error handling is in place.

platform.apilevel = "2.4"

local var = rawget(_G, "var") or nil
_G.darkMode = (var and var.recall and var.recall("dark_mode") == 1) or false

--[[
  A monkey-patch of the global 'error' function.
  This suppresses file and line number information, providing a cleaner, user-friendly error message.
  This is essential for the TI-Nspire's limited display.
  @param msg (string): The error message.
  @param level (number): The stack level to report. This is ignored.
]]
local original_error = error
function error(msg, level)
    original_error(tostring(msg), 0)
end

-- Default fallback; true recall happens after storage is ready
_G.current_constant_category = nil

--[[
  Synchronizes the current constant category with persistent storage.
  It attempts to recall the last-used category from the 'var' storage.
  If no category is found, it defaults to "fundamental" and stores this default value.
]]
function syncCategoryFromStorage()
    if var and type(var.recall) == "function" then
        local cat = var.recall("current_constant_category")
        if cat and type(cat) == "string" then
            print("[STATE] Loaded stored constant category:", cat)
            _G.current_constant_category = cat
            return
        end
    end

    if not _G.current_constant_category then
        _G.current_constant_category = "fundamental"
        print("[STATE] No stored category, using default:", _G.current_constant_category)
        
        if var and type(var.store) == "function" then
            var.store("current_constant_category", _G.current_constant_category)
            print("[STATE] Stored default category to storage:", _G.current_constant_category)
        end
    end
end

--[[
  Platform-specific event handler called when the program is constructed.
  It's the ideal place to load persistent state from storage.
]]
function on.construction()
    syncCategoryFromStorage()
end

--[[
  Platform-specific event handler that returns a list of global variables to be saved.
  This ensures that the state of 'current_constant_category' is preserved across program sessions.
  @return (table): A list of global symbol names.
]]
function on.getSymbolList()
    return { "current_constant_category" }
end