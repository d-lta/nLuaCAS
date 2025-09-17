-- trig.lua
-- Symbolic and numeric helpers for trigonometric functions.
-- All numeric evaluation assumes angles are in radians.

local errors = _G.errors
local ast = _G.ast or error("AST module required")

-- Handles numeric evaluation of trig functions.
-- Returns an AST number node if successful, otherwise nil.
local function eval_trig_func(fname, arg)
  if type(arg) == "table" and arg.type == "number" then
    local val = arg.value
    if fname == "sin" then return ast.number(math.sin(val)) end
    if fname == "cos" then return ast.number(math.cos(val)) end
    if fname == "tan" then return ast.number(math.tan(val)) end
    if fname == "cot" then return ast.number(1 / math.tan(val)) end
    if fname == "sec" then return ast.number(1 / math.cos(val)) end
    if fname == "csc" then return ast.number(1 / math.sin(val)) end
  end
  return nil -- Not a number, fallback to symbolic.
end

-- Symbolic differentiation of a trig function using the chain rule.
-- Requires the inner function (arg) and its derivative (darg).
local function diff_trig_func(fname, arg, darg)
  if fname == "sin" then
    return ast.mul(ast.func("cos", {arg}), darg)
  elseif fname == "cos" then
    return ast.mul(ast.neg(ast.func("sin", {arg})), darg)
  elseif fname == "tan" then
    -- Using the secant identity is cleaner than (1 + tan^2).
    return ast.mul(ast.pow(ast.func("sec", {arg}), ast.number(2)), darg)
  elseif fname == "cot" then
    -- Equivalent to -csc^2(x).
    return ast.mul(ast.neg(ast.pow(ast.func("csc", {arg}), ast.number(2))), darg)
  elseif fname == "sec" then
    return ast.mul(ast.mul(ast.func("sec", {arg}), ast.func("tan", {arg})), darg)
  elseif fname == "csc" then
    return ast.mul(ast.neg(ast.mul(ast.func("csc", {arg}), ast.func("cot", {arg}))), darg)
  end
  return error(errors.invalid("diff", "unknown trig function: " .. tostring(fname)))
end

-- Symbolic integration of a trig function.
local function integrate_trig_func(fname, arg)
  if fname == "sin" then
    return ast.neg(ast.func("cos", {arg}))
  elseif fname == "cos" then
    return ast.func("sin", {arg})
  elseif fname == "tan" then
    return ast.neg(ast.func("ln", {ast.func("cos", {arg})}))
  elseif fname == "cot" then
    return ast.func("ln", {ast.func("sin", {arg})})
  elseif fname == "sec" then
    return ast.func("ln", {ast.add(ast.func("sec", {arg}), ast.func("tan", {arg}))})
  elseif fname == "csc" then
    return ast.neg(ast.func("ln", {ast.add(ast.func("csc", {arg}), ast.func("cot", {arg}))}))
  end
  return nil -- Unknown trig function, fallback to unhandled.
end

_G.trig = {
  eval_trig_func = eval_trig_func,
  diff_trig_func = diff_trig_func,
  integrate_trig_func = integrate_trig_func,
}