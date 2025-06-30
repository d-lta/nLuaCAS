platform.apilevel = "2.4"

local var = rawget(_G, "var") or nil
_G.darkMode = (var and var.recall and var.recall("dark_mode") == 1) or false

-- Default fallback; true recall happens after storage is ready
_G.current_constant_category = nil

-- Delay storage sync to avoid race with var initialization
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


function on.construction()
    syncCategoryFromStorage()
end

function on.getSymbolList()
    return { "current_constant_category" }
end
