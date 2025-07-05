local errors_table = {
  ["parse(series)"] = "Error: Failed to parse the series expression. Did you use correct syntax?",
  ["parse(integral)"] = "Error: Integral parsing failed. Make sure your integral syntax is correct.",
  ["d/dx(nothing)"] = "Error: Derivative operator used without an expression. What do you want to differentiate?",
  ["simplify(series)"] = "Error: Could not simplify the series expression. This is math, not magic.",
  ["simplify(integral)"] = "Error: Integral simplification failed. Did you expect miracles?",
  ["int(series)"] = "Error: Integration of series failed. Try something simpler, genius.",
  ["int(by_parts)"] = "Error: Integration by parts failed. Maybe try harder or give up.",
}

-- Separate invalid function to avoid overwriting and recursion hell
local function invalid_error(typ)
  return "Error: Invalid " .. (typ or "expression") .. ". Can't make sense of that garbage."
end

-- Assign errors_table directly to _G.errors but keep invalid separate
_G.errors = errors_table
_G.errors.invalid = invalid_error

function _G.errors.get(key)
  if _G.errors and type(_G.errors) == "table" then
    return _G.errors[key]
  end
  return nil
end

function handleParseError(context)
  if context == "series" then
    error(_G.errors.get("parse(series)") or _G.errors.invalid("parse"))
  elseif context == "integral" then
    error(_G.errors.get("parse(integral)") or _G.errors.invalid("parse"))
  elseif context == "derivative" then
    error(_G.errors.get("d/dx(nothing)") or _G.errors.invalid("diff"))
  else
    error(_G.errors.invalid("parse"))
  end
end

function handleSimplifyError(context)
  if context == "series" then
    error(_G.errors.get("simplify(series)") or _G.errors.invalid("simplify"))
  elseif context == "integral" then
    error(_G.errors.get("simplify(integral)") or _G.errors.invalid("simplify"))
  else
    error(_G.errors.invalid("simplify"))
  end
end

function handleIntegralError(context)
  if context == "series" then
    error(_G.errors.get("int(series)") or _G.errors.invalid("int"))
  elseif context == "by_parts" then
    error(_G.errors.get("int(by_parts)") or _G.errors.invalid("int"))
  else
    error(_G.errors.invalid("int"))
  end
end

_G.handleParseError = handleParseError
_G.handleSimplifyError = handleSimplifyError
_G.handleIntegralError = handleIntegralError