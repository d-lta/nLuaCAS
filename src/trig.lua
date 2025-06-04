-- trig.lua
-- Trig evaluation and symbolic helpers for nLuaCAS
-- Mostly here to pretend we remember SOHCAHTOA and the chain rule


-- Handles numeric evaluation of trig functions
-- Assumes degrees because radians scare most calculator users
-- Falls back to symbolic if it smells like algebra
-- Numeric trig evaluation (angle in degrees if constant input)
local function eval_trig_func(fname, arg)
  if type(arg) == "table" and arg.type == "number" then
    local val = arg.value
    -- Assume degrees for simple numbers (can adapt for radians)
    local rad = math.rad(val)
    if fname == "sin" then return ast.number(math.sin(rad)) end
    if fname == "cos" then return ast.number(math.cos(rad)) end
    if fname == "tan" then return ast.number(math.tan(rad)) end
    if fname == "cot" then return ast.number(1 / math.tan(rad)) end
    if fname == "sec" then return ast.number(1 / math.cos(rad)) end
    if fname == "csc" then return ast.number(1 / math.sin(rad)) end
  end
  -- Not a numeric constant: return nil, fall back to symbolic
  return nil
end

-- Symbolic derivatives of trig functions
-- Applies the chain rule without asking for permission
-- Sins become cosines, cosines become negative sins, and so on
-- Symbolic differentiation of all trig functions (chain rule applied)
local function diff_trig_func(fname, arg, darg)
  if fname == "sin" then
    return ast.mul(ast.func("cos", {arg}), darg)
  elseif fname == "cos" then
    return ast.mul(ast.neg(ast.func("sin", {arg})), darg)
  elseif fname == "tan" then
    return ast.mul(ast.add(ast.number(1), ast.pow(ast.func("tan", {arg}), ast.number(2))), darg)
  elseif fname == "cot" then
    return ast.mul(ast.neg(ast.add(ast.number(1), ast.pow(ast.func("cot", {arg}), ast.number(2)))), darg)
  elseif fname == "sec" then
    return ast.mul(ast.mul(ast.func("sec", {arg}), ast.func("tan", {arg})), darg)
  elseif fname == "csc" then
    return ast.mul(ast.neg(ast.mul(ast.func("csc", {arg}), ast.func("cot", {arg}))), darg)
  end
  return nil
end

-- Bundle it up for the global namespace
-- Hopefully avoids circular dependency chaos
_G.trig = {
  eval_trig_func = eval_trig_func,
  diff_trig_func = diff_trig_func,
}