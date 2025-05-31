-- Basic CAS GUI for TI-Nspire (Lua)
local input = ""
local output = ""
local editing = true
local history = {}
local view = "main" -- can be "main", "history", "about", "help"

local unpack = table.unpack or unpack
local darkMode = false

-- Soft persistence for history and theme (if available)
local store = platform and platform.store
if store then
  local ok1, h = pcall(function() return store.get("cas_history") end)
  if ok1 and h then history = h end
  local ok2, d = pcall(function() return store.get("cas_darkMode") end)
  if ok2 and d ~= nil then darkMode = d end
end
local palette_light = {
  header = {34,40,49}, bg = {236,240,241}, faded = {230,230,230},
  inputBG = {240,244,255}, inputBorder = {60,120,200},
  outBG = {252,252,255}, outBorder = {80,180,120},
  text = {0,0,0}
}
local palette_dark = {
  header = {50,60,80}, bg = {18,18,24}, faded = {85,85,90},
  inputBG = {36,40,45}, inputBorder = {90,120,220},
  outBG = {38,43,47}, outBorder = {39,174,96},
  text = {220,220,220}
}

-- Forward declarations for parser functions
local parseExpr, parseTermChain, parseTerm, parseFactor

-- Tokenize a mathematical expression into components
function tokenize(expr)
  local tokens = {}
  local i = 1
  while i <= #expr do
    local c = expr:sub(i,i)
    if c:match("%s") then
      i = i + 1
    elseif c:match("[%d%.]") then
      local num = c
      i = i + 1
      while i <= #expr and expr:sub(i,i):match("[%d%.]") do
        num = num .. expr:sub(i,i)
        i = i + 1
      end
      table.insert(tokens, num)
    elseif c:match("[%a]") then
      local ident = c
      i = i + 1
      while i <= #expr and expr:sub(i,i):match("[%a%d]") do
        ident = ident .. expr:sub(i,i)
        i = i + 1
      end
      if expr:sub(i,i) == "(" then
        table.insert(tokens, ident)
        table.insert(tokens, "(")
        i = i + 1
      else
        table.insert(tokens, ident)
      end
    elseif c:match("[%+%-%*/%^%(%)]") then
      table.insert(tokens, c)
      i = i + 1
    else
      error("Unknown character: " .. c)
    end
  end

  -- Insert * for implicit multiplication
  local i = 2
  while i <= #tokens do
    if (tokens[i-1]:match("[%d%a%)%]]") and tokens[i]:match("[%a%(]")) then
      table.insert(tokens, i, "*")
      i = i + 1
    end
    i = i + 1
  end
  return tokens
end


-- Helper parsing functions for AST construction

local function parseTerm(tokens, index)
  local token = tokens[index]
  if token == nil then
    return nil, index
  end
  if tonumber(token) then
    return { type = "number", value = tonumber(token) }, index + 1
  elseif token:match("%a") then
    if tokens[index+1] == "(" then
      local args = {}
      local funcName = token
      local argNode, nextIndex = parseExpr(tokens, index + 2)
      table.insert(args, argNode)
      if tokens[nextIndex] ~= ")" then error("Expected ')' after function call") end
      return { type = "func", name = funcName, args = args }, nextIndex + 1
    else
      return { type = "variable", name = token }, index + 1
    end
  elseif token == "(" then
    local node, nextIndex = parseExpr(tokens, index + 1)
    if tokens[nextIndex] ~= ")" then
      error("Expected ')'")
    end
    return node, nextIndex + 1
  end
  error("Unexpected token: " .. token)
end

local function parseFactor(tokens, index)
  local node, nextIndex = parseTerm(tokens, index)
  if tokens[nextIndex] == "^" then
    local right, finalIndex = parseFactor(tokens, nextIndex + 1)
    return { type = "power", left = node, right = right }, finalIndex
  end
  return node, nextIndex
end

local function parseTermChain(tokens, index)
  local node, nextIndex = parseFactor(tokens, index)
  while tokens[nextIndex] == "*" or tokens[nextIndex] == "/" do
    local op = tokens[nextIndex]
    local right, newIndex = parseFactor(tokens, nextIndex + 1)
    node = { type = op == "*" and "mul" or "div", left = node, right = right }
    nextIndex = newIndex
  end
  return node, nextIndex
end

function parseExpr(tokens, index)
  local node, nextIndex = parseTermChain(tokens, index)
  while tokens[nextIndex] == "+" or tokens[nextIndex] == "-" do
    local op = tokens[nextIndex]
    local right, newIndex = parseTermChain(tokens, nextIndex + 1)
    node = { type = op == "+" and "add" or "sub", left = node, right = right }
    nextIndex = newIndex
  end
  return node, nextIndex
end

-- Very basic parser: Converts a flat list into a left-associative binary tree
function buildAST(tokens)
  local ast, nextIndex = parseExpr(tokens, 1)
  if nextIndex <= #tokens then
    return nil
  end
  return ast
end


-- AST-to-string for display (minimized string allocations)
function astToString(ast)
  if not ast then return "?" end
  local t = ast.type
  if t == "number" then return tostring(ast.value) end
  if t == "variable" then return ast.name end
  if t == "func" then
    return ast.name .. "(" .. astToString(ast.args[1]) .. ")"
  end
  if t == "power" then
    -- Parenthesize if needed for clarity
    return "("..astToString(ast.left)..")^("..astToString(ast.right)..")"
  end
  if t == "mul" then
    -- Omit * for number*variable, e.g. 2x
    if ast.left.type == "number" and ast.right.type == "variable" then
      if ast.left.value == 1 then return astToString(ast.right) end
      if ast.left.value == 0 then return "0" end
      return tostring(ast.left.value)..astToString(ast.right)
    end
    if ast.right.type == "number" and ast.left.type == "variable" then
      if ast.right.value == 1 then return astToString(ast.left) end
      if ast.right.value == 0 then return "0" end
      return tostring(ast.right.value)..astToString(ast.left)
    end
    return astToString(ast.left).."*"..astToString(ast.right)
  end
  if t == "div" then
    return astToString(ast.left).."/"..astToString(ast.right)
  end
  if t == "add" then
    return astToString(ast.left).."+"..astToString(ast.right)
  end
  if t == "sub" then
    return astToString(ast.left).."-"..astToString(ast.right)
  end
  return "?"
end

-- Recursively simplify AST: combine constants, expand products/powers, collapse terms
function simplifyAST(ast)
  if not ast then return nil end
  local t = ast.type
  if t == "func" then
    return { type = "func", name = ast.name, args = {simplifyAST(ast.args[1])} }
  end
  if t == "number" or t == "variable" then
    return ast
  end
  -- Generic like-term combining for terms like ax^n + bx^n
  local function extractCoeffVarPow(node)
    if node.type == "variable" then
      return 1, node.name, 1
    elseif node.type == "mul" and node.left.type == "number" and node.right.type == "variable" then
      return node.left.value, node.right.name, 1
    elseif node.type == "power" and node.left.type == "variable" and node.right.type == "number" then
      return 1, node.left.name, node.right.value
    elseif node.type == "mul" and node.left.type == "number"
      and node.right.type == "power"
      and node.right.left.type == "variable"
      and node.right.right.type == "number" then
      return node.left.value, node.right.left.name, node.right.right.value
    -- Additional checks for combinations like x*x, x*x^2, x^2*x, x^2*x^3, x*x*x
    elseif node.type == "mul" and node.left.type == "variable" and node.right.type == "variable" and node.left.name == node.right.name then
      -- x*x => x^2
      return 1, node.left.name, 2
    elseif node.type == "mul" and node.left.type == "variable" and node.right.type == "power"
      and node.right.left.type == "variable" and node.right.right.type == "number"
      and node.left.name == node.right.left.name then
      -- x*x^n => x^(n+1)
      return 1, node.left.name, node.right.right.value + 1
    elseif node.type == "mul" and node.left.type == "power" and node.right.type == "variable"
      and node.left.left.type == "variable" and node.left.right.type == "number"
      and node.left.left.name == node.right.name then
      -- x^n*x => x^(n+1)
      return 1, node.right.name, node.left.right.value + 1
    elseif node.type == "mul" and node.left.type == "power" and node.right.type == "power"
      and node.left.left.type == "variable" and node.left.right.type == "number"
      and node.right.left.type == "variable" and node.right.right.type == "number"
      and node.left.left.name == node.right.left.name then
      -- x^n * x^m => x^(n+m)
      return 1, node.left.left.name, node.left.right.value + node.right.right.value
    end
    return nil
  end
  local function combineLikeTerms(left, right, op)
    local c1, v1, p1 = extractCoeffVarPow(left)
    local c2, v2, p2 = extractCoeffVarPow(right)
    if c1 and c2 and v1 == v2 and p1 == p2 then
      local coeff = op == "add" and (c1 + c2) or (c1 - c2)
      if coeff == 0 then
        return {type="number", value=0}
      elseif p1 == 1 then
        return {type="mul", left={type="number", value=coeff}, right={type="variable", name=v1}}
      else
        return {
          type="mul",
          left={type="number", value=coeff},
          right={type="power", left={type="variable", name=v1}, right={type="number", value=p1}}
        }
      end
    end
    return nil
  end
  if t == "add" or t == "sub" then
    local left = simplifyAST(ast.left)
    local right = simplifyAST(ast.right)
    -- Combine numeric
    if left.type == "number" and right.type == "number" then
      return {type="number", value=(t=="add" and left.value+right.value or left.value-right.value)}
    end
    -- Generic like-term combining
    local combined = combineLikeTerms(left, right, t)
    if combined then return combined end
    -- 0 + x = x, x + 0 = x
    if left.type == "number" and left.value == 0 then return right end
    if right.type == "number" and right.value == 0 then return left end
    return {type=t, left=left, right=right}
  end
  if t == "mul" then
    local left = simplifyAST(ast.left)
    local right = simplifyAST(ast.right)
    -- Constant folding
    if left.type == "number" and right.type == "number" then
      return {type="number", value=left.value * right.value}
    end
    -- 0*x or x*0 => 0
    if (left.type == "number" and left.value == 0) or (right.type == "number" and right.value == 0) then
      return {type="number", value=0}
    end
    -- 1*x or x*1 => x
    if left.type == "number" and left.value == 1 then return right end
    if right.type == "number" and right.value == 1 then return left end
    -- Expand (a+b)*c => a*c + b*c
    if left.type == "add" then
      return simplifyAST({type="add",
        left={type="mul", left=left.left, right=right},
        right={type="mul", left=left.right, right=right}})
    end
    if right.type == "add" then
      return simplifyAST({type="add",
        left={type="mul", left=left, right=right.left},
        right={type="mul", left=left, right=right.right}})
    end
    -- Expand (a-b)*c and a*(b-c)
    if left.type == "sub" then
      return simplifyAST({type="sub",
        left={type="mul", left=left.left, right=right},
        right={type="mul", left=left.right, right=right}})
    end
    if right.type == "sub" then
      return simplifyAST({type="sub",
        left={type="mul", left=left, right=right.left},
        right={type="mul", left=left, right=right.right}})
    end
    return {type="mul", left=left, right=right}
  end
  if t == "div" then
    local left = simplifyAST(ast.left)
    local right = simplifyAST(ast.right)
    if left.type == "number" and right.type == "number" then
      return {type="number", value=left.value / right.value}
    end
    -- x/1 = x
    if right.type == "number" and right.value == 1 then return left end
    return {type="div", left=left, right=right}
  end
  if t == "power" then
    local base = simplifyAST(ast.left)
    local exp = simplifyAST(ast.right)
    if base.type == "number" and exp.type == "number" then
      return {type="number", value=base.value ^ exp.value}
    end
    -- (x^1) => x, (x^0) => 1
    if exp.type == "number" and exp.value == 1 then return base end
    if exp.type == "number" and exp.value == 0 then return {type="number", value=1} end
    -- Expand (a+b)^2 => (a+b)*(a+b)
    if exp.type == "number" and exp.value == 2 then
      return simplifyAST({type="mul", left=base, right=base})
    end
    return {type="power", left=base, right=exp}
  end
  return ast
end

function simplify(expr)
  expr = expr:gsub("%s+", "")
  local tokens = tokenize(expr)
  local ast = buildAST(tokens)
  if not ast then return "Can't simplify: invalid expression" end
  local simp = simplifyAST(ast)
  return simp and astToString(simp) or "Simplify failed"
end

-- Basic equation solver: solve(x^2 - 4 = 0)
function solve(eqn)
  eqn = eqn:gsub("%s+", "") -- Remove all whitespace
  local lhs, rhs = eqn:match("(.+)%=(.+)")
  if not lhs or not rhs then
    -- Try auto-convert to "=0" if not present
    if not eqn:find("=") then
      lhs = eqn
      rhs = "0"
    else
      return "Invalid equation"
    end
  end
  local expr = "(" .. lhs .. ")-(" .. rhs .. ")"
  local tokens = tokenize(expr)
  local ast = buildAST(tokens)
  if not ast then return "Could not parse equation" end

  local function collectPoly(node, coeffs)
    coeffs = coeffs or { [0]=0, [1]=0, [2]=0, [3]=0 }
    if node.type == "add" or node.type == "sub" then
      local left = collectPoly(node.left, {})
      local right = collectPoly(node.right, {})
      for k,v in pairs(left) do coeffs[k] = (coeffs[k] or 0) + v end
      for k,v in pairs(right) do
        coeffs[k] = (coeffs[k] or 0) + (node.type == "add" and v or -v)
      end
    elseif node.type == "mul" then
      if node.left.type == "number" and node.right.type == "variable" and node.right.name == "x" then
        coeffs[1] = (coeffs[1] or 0) + node.left.value
      elseif node.right.type == "number" and node.left.type == "variable" and node.left.name == "x" then
        coeffs[1] = (coeffs[1] or 0) + node.right.value
      elseif node.left.type == "number" and node.right.type == "power" and node.right.left.name == "x" then
        coeffs[node.right.right.value] = (coeffs[node.right.right.value] or 0) + node.left.value
      end
    elseif node.type == "power" and node.left.name == "x" then
      coeffs[node.right.value] = (coeffs[node.right.value] or 0) + 1
    elseif node.type == "variable" and node.name == "x" then
      coeffs[1] = (coeffs[1] or 0) + 1
    elseif node.type == "number" then
      coeffs[0] = (coeffs[0] or 0) + node.value
    end
    return coeffs
  end

  local coeffs = collectPoly(ast)
  local a, b, c, d = coeffs[3] or 0, coeffs[2] or 0, coeffs[1] or 0, coeffs[0] or 0

  if a == 0 and b == 0 and c ~= 0 then
    return "x = " .. (-d/c)
  elseif a == 0 and b ~= 0 then
    local D = c^2 - 4*b*d
    if D < 0 then return "No real roots" end
    local r1 = (-c + math.sqrt(D)) / (2*b)
    local r2 = (-c - math.sqrt(D)) / (2*b)
    return string.format("x₁ = %.4g, x₂ = %.4g", r1, r2)
  elseif a ~= 0 then
    local p = (3*a*c - b^2) / (3*a^2)
    local q = (2*b^3 - 9*a*b*c + 27*a^2*d) / (27*a^3)
    local delta = (q^2)/4 + (p^3)/27
    local roots = {}
    if delta > 0 then
      local sqrt_delta = math.sqrt(delta)
      local u = ((-q)/2 + sqrt_delta)^(1/3)
      local v = ((-q)/2 - sqrt_delta)^(1/3)
      local root = u + v - b / (3*a)
      table.insert(roots, root)
      return string.format("x = %.4g (1 real root)", root)
    elseif delta == 0 then
      local u = (-q / 2)^(1/3)
      local r1 = 2*u - b / (3*a)
      local r2 = -u - b / (3*a)
      return string.format("x₁ = %.4g, x₂ = %.4g", r1, r2)
    else
      local r = math.sqrt(-p^3 / 27)
      local phi = math.acos(-q / (2 * r))
      local t = 2 * math.sqrt(-p / 3)
      for k = 0, 2 do
        local angle = (phi + 2*math.pi*k)/3
        local root = t * math.cos(angle) - b / (3*a)
        table.insert(roots, root)
      end
      return string.format("x₁ = %.4g, x₂ = %.4g, x₃ = %.4g", roots[1], roots[2], roots[3])
    end
  end
  return "Unsupported or no x found"
end

-- Evaluate simple user-defined functions
local memory = {}
function define(expr)
  local name, body = expr:match("let%s+(%w+)%s*=%s*(.+)")
  if name and body then
    memory[name] = body
    return "Stored: " .. name .. " = " .. body
  end
  local fname, fbody = expr:match("let%s+(%w+%b())%s*=%s*(.+)")
  if fname and fbody then
    memory[fname] = fbody
    return "Stored function: " .. fname
  end
  return "Invalid definition"
end

function evalFunction(expr)
  -- Try variable lookup
  if memory[expr] then
    return simplify(memory[expr])
  end

  -- Try function call
  for k,v in pairs(memory) do
    local name, arg = k:match("(%w+)%((%w+)%)")
    local callarg = expr:match(name .. "%(([%d%.%-]+)%)")
    if name and arg and callarg then
      local body = v:gsub(arg, callarg)
      return simplify(body)
    end
  end
  return "Unknown variable or function"
end

-- Support definite integrals: int(expr, a, b)
function definiteInt(expr)
  local e,a,b = expr:match("([^,]+),%s*([^,]+),%s*([^%)]+)")
  if e and a and b then
    local f = integrate(e)
    local fa = evalFunction(f:gsub(" +C", ""):gsub("x", a))
    local fb = evalFunction(f:gsub(" +C", ""):gsub("x", b))
    return "(" .. fb .. ") - (" .. fa .. ")"
  end
  return "Invalid definite integral"
end

function derivative(expr)
  expr = expr:gsub("%s+", "") -- remove whitespace

  -- Multivariable partial derivatives
  if expr:match("^∂/∂[yz]%(") then
    local var = expr:sub(4, 4)
    local subexpr = expr:match("∂/∂"..var.."%((.+)%)")
    if subexpr then
      return "Partial w.r.t " .. var .. ": " .. derivative(subexpr)
    else
      return "Invalid partial"
    end
  end

  -- Constant
  if expr:match("^%d+$") then return "0" end
  if expr == "x" then return "1" end

  -- Trigonometric functions
  if expr == "sin(x)" then return "cos(x)" end
  if expr == "cos(x)" then return "-sin(x)" end
  if expr == "tan(x)" then return "sec(x)^2" end
  if expr == "sec(x)" then return "sec(x)tan(x)" end
  if expr == "csc(x)" then return "-csc(x)cot(x)" end
  if expr == "cot(x)" then return "-csc(x)^2" end

  -- Exponential
  if expr == "e^x" then return "e^x" end
  local a = expr:match("^(%d+)%^x$")
  if a then return expr .. "*ln(" .. a .. ")" end

  -- Logarithmic
  if expr == "ln(x)" then return "1/x" end

  -- Chain rule: (ax+b)^n
  local inner, offset, exponent = expr:match("^%((%-?%d*%.?%d*)x([%+%-]%d+)%)%^([%d%.]+)$")
  if inner and exponent then
    local a = tonumber(inner) ~= 0 and tonumber(inner) or 1
    local n = tonumber(exponent)
    local new_exp = n - 1
    local outer = tostring(n) .. "(" .. inner .. "x" .. offset .. ")^" .. new_exp
    return outer .. "*" .. tostring(a)
  end

  -- Power rule
  local base, exponent = expr:match("^(x)%^([%d%.]+)$")
  if base and exponent then
    local new_exp = tonumber(exponent) - 1
    return exponent .. "x^" .. new_exp
  end

  -- Constant * x^n
  local coeff, power = expr:match("^(%-?%d*%.?%d*)x%^([%d%.]+)$")
  if coeff and power then
    if coeff == "" then coeff = "1" end
    local new_coeff = tonumber(coeff) * tonumber(power)
    local new_exp = tonumber(power) - 1
    return tostring(new_coeff) .. "x^" .. tostring(new_exp)
  end

  -- Constant * x
  coeff = expr:match("^(%-?%d*%.?%d*)x$")
  if coeff then
    if coeff == "" then coeff = "1" end
    return tostring(tonumber(coeff))
  end

  -- Product rule: f(x)*g(x)
  local f, g = expr:match("^(.-)%*(.+)$")
  if f and g then
    return "(" .. derivative(f) .. ")*" .. g .. " + " .. f .. "*(" .. derivative(g) .. ")"
  end

  -- Quotient rule: f(x)/g(x)
  local num, denom = expr:match("^(.-)/(.-)$")
  if num and denom then
    return "((" .. derivative(num) .. ")*" .. denom .. " - " .. num .. "*(" .. derivative(denom) .. "))/" .. denom .. "^2"
  end

  -- Sum of terms
  if expr:find("%+") then
    local terms = {}
    for term in expr:gmatch("[^+]+") do
      table.insert(terms, derivative(term))
    end
    return table.concat(terms, " + ")
  end

  -- Higher-order derivatives: d²/dx²(expr)
  local order, var, subexpr = expr:match("^d(%d+)/d([a-zA-Z])%^(%d+)%((.+)%)$")
  if order and var and subexpr then
    order = tonumber(order)
    local result = subexpr
    for i = 1, order do
      result = derivative(result)
    end
    return result
  end

  -- Handle exact form like d²/dx²(...)
  if expr:match("^d²/dx²%(.+%)$") then
    local subexpr = expr:match("^d²/dx²%((.+)%)$")
    if subexpr then
      return derivative(derivative(subexpr))
    end
  end

  return "d/dx not supported for: " .. expr
end

function integrate(expr)
  expr = expr:gsub("%s+", "") -- remove whitespace

  -- Integrate constants
  if expr:match("^%d+$") then
    return expr .. "x + C"
  end

  -- Integrate x
  if expr == "x" then
    return "0.5x^2 + C"
  end

  -- Trigonometric functions
  if expr == "sin(x)" then return "-cos(x) + C" end
  if expr == "cos(x)" then return "sin(x) + C" end
  if expr == "tan(x)" then return "-ln|cos(x)| + C" end
  if expr == "sec(x)^2" then return "tan(x) + C" end
  if expr == "csc(x)^2" then return "-cot(x) + C" end
  if expr == "sec(x)tan(x)" then return "sec(x) + C" end
  if expr == "csc(x)cot(x)" then return "-csc(x) + C" end

  -- Exponential and log
  if expr == "e^x" then return "e^x + C" end
  if expr == "ln(x)" then return "x*ln(x) - x + C" end

  -- Power rule: x^n -> x^(n+1)/(n+1)
  local base, exponent = expr:match("^(x)%^([%d%.]+)$")
  if base and exponent then
    local new_exp = tonumber(exponent) + 1
    return "x^" .. new_exp .. "/" .. new_exp .. " + C"
  end

  -- Constant * x^n
  local coeff, power = expr:match("^(%-?%d*%.?%d*)x%^([%d%.]+)$")
  if coeff and power then
    if coeff == "" then coeff = "1" end
    local new_exp = tonumber(power) + 1
    local result = tonumber(coeff) / new_exp
    return tostring(result) .. "x^" .. tostring(new_exp) .. " + C"
  end

  -- Constant * x
  coeff = expr:match("^(%-?%d*%.?%d*)x$")
  if coeff then
    if coeff == "" then coeff = "1" end
    return coeff .. "*0.5x^2 + C"
  end

  return "∫ not supported for: " .. expr
end

function on.charIn(char)
  if editing then
    input = input .. char
    platform.window:invalidate()
  end
end

function on.backspaceKey()
  input = input:sub(1, -2)
  platform.window:invalidate()
end

function on.enterKey()
  if view == "main" then
    if editing then
      editing = false
      local result = ""
      if input:sub(1,4) == "d/dx" or input:sub(1,4) == "d/dy" then
        local expr = input:match("d/d[xy]%((.+)%)")
        result = expr and derivative(expr) or "Invalid format"
      elseif input:sub(1,5) == "∂/∂x(" and input:sub(-1) == ")" then
        local expr = input:match("∂/∂x%((.+)%)")
        result = expr and derivative(expr) or "Invalid format"
      elseif input:match("^∂/∂[yz]%(.+%)$") then
        result = derivative(input)
      elseif input:sub(1,3) == "∫(" and input:sub(-2) == ")x" then
        result = integrate(input:sub(4, -3))
      elseif input:sub(1,4) == "int(" and input:sub(-1) == ")" then
        local expr = input:match("int%((.+)%)")
        result = expr and integrate(expr) or "Invalid format"
      elseif input:sub(1,4) == "ast(" and input:sub(-1) == ")" then
        local expr = input:match("ast%((.+)%)")
        if expr then
          local tokens = tokenize(expr)
          local ast = buildAST(tokens)
          result = ast and stringifyAST(ast) or "Error: incomplete expression"
        else
          result = "Invalid AST format"
        end
      -- Debug log for solve (optional for development)
      elseif input:sub(1,6) == "solve(" and input:sub(-1) == ")" then
        print("Solving:", input)
        local eqn = input:match("solve%((.+)%)")
        result = eqn and solve(eqn) or "Invalid solve format"
      elseif input:sub(1,4) == "let " then
        result = define(input)
      elseif input:match("%w+%(.+%)") then
        result = evalFunction(input)
      elseif input:sub(1,4) == "int(" and input:match(",") then
        local defint = input:match("int%((.+)%)")
        result = defint and definiteInt(defint) or "Invalid definite integral"
      elseif input:sub(1,9) == "simplify(" and input:sub(-1) == ")" then
        local inner = input:match("simplify%((.+)%)")
        result = inner and simplify(inner) or "Invalid simplify format"
      else
        result = simplify(input)
      end
      output = result
      table.insert(history, input .. " → " .. result)
      if store then pcall(function() store.set("cas_history", history) end) end
      if store then pcall(function() store.set("cas_darkMode", darkMode) end) end
      platform.window:invalidate()
    else
      -- User pressed Enter again after result: clear and reset for new input
      editing = true
      input = ""
      output = ""
      platform.window:invalidate()
    end
  end
end

function on.tabKey()
  if view == "main" then
    view = "history"
  elseif view == "history" then
    view = "about"
  elseif view == "about" then
    view = "help"
  elseif view == "help" then
    view = "main"
  end
  platform.window:invalidate()
end


-- Utility function to format superscripts for powers like x^2 -> x²

function formatSuperscripts(str)
  local map = {
    ["0"] = "⁰", ["1"] = "¹", ["2"] = "²", ["3"] = "³",
    ["4"] = "⁴", ["5"] = "⁵", ["6"] = "⁶", ["7"] = "⁷",
    ["8"] = "⁸", ["9"] = "⁹", ["-"] = "⁻"
  }
  return str:gsub("x%^([%-%d]+)", function(exp)
    local formatted = ""
    for c in exp:gmatch(".") do
      formatted = formatted .. (map[c] or "")
    end
    return "x" .. formatted
  end)
end

function prettyPrint(expr, gc, x, y)
  expr = expr or ""
  -- Simple recursive pretty-printer for basic "a/b", powers, roots
  -- Only handles simple single-letter numerator/denominator
  -- Does not parse full AST; parses strings for now
  if expr == nil or expr == "" then
    -- Print nothing (or a placeholder if desired), but always return a valid height
    return 18
  end
  local frac = expr:match("^(.-)/(%b())$")
  if frac then -- e.g. "x/(x+1)"
    local num, denom = expr:match("^(.-)/%((.+)%)$")
    if num and denom then
      gc:drawString(num, x + 15, y, "top")
      local numWidth = gc:getStringWidth(num)
      local denWidth = gc:getStringWidth(denom)
      local fracWidth = math.max(numWidth, denWidth)
      gc:drawLine(x + 12, y + 14, x + 12 + fracWidth + 6, y + 14)
      gc:drawString(denom, x + 15, y + 18, "top")
      return 28
    end
  end
  local num, denom = expr:match("^(.-)/(.+)$")
  if num and denom and not num:find("%+") and not denom:find("%+") then
    -- Only simple "a/b" with no "+"
    gc:drawString(num, x + 10, y, "top")
    local numWidth = gc:getStringWidth(num)
    local denWidth = gc:getStringWidth(denom)
    local fracWidth = math.max(numWidth, denWidth)
    gc:drawLine(x + 7, y + 14, x + 7 + fracWidth + 6, y + 14)
    gc:drawString(denom, x + 10, y + 18, "top")
    return 28
  end

  -- Exponents (superscript handled by formatSuperscripts)
  if expr:find("x%^") then
    gc:drawString(formatSuperscripts(expr), x, y, "top")
    return 18
  end

  -- Square roots as "√(stuff)"
  local sq = expr:match("^sqrt%((.+)%)$")
  if sq then
    gc:drawString("√(" .. sq .. ")", x, y, "top")
    return 18
  end

  -- Otherwise just print as-is, formatted
  gc:drawString(formatSuperscripts(expr), x, y, "top")
  return 18
end

-- Helper: split operator and argument for prettyPrint sizing
function splitOperatorInput(expr)
  -- e.g. "d/dx(x^2)" => "d/dx", "x^2"
  local op, arg = expr:match("^([^%(]+)%((.+)%)$")
  if op and arg then return op, arg end
  return nil, nil
end

-- Helper: compute prettyPrint height for an expression
function getPrettyPrintHeight(expr, gc)
  expr = expr or ""
  local op, arg = splitOperatorInput(expr)
  if op and arg and not expr:find("^.+%s%(") then
    if arg:match("^.+/.+$") then return 47 end
    return 37
  elseif expr:match("^.+/.+$") then
    return 28
  else
    return 18
  end
end

function on.paint(gc)
  local w, h = platform.window:width(), platform.window:height()
  local palette = darkMode and palette_dark or palette_light

  -- Fill background with bg color before faded symbols, header, boxes
  gc:setColorRGB(unpack(palette.bg))
  gc:fillRect(0, 0, w, h)

  -- Faded background, as before
  gc:setFont("serif", "b", 48)
  -- faded symbols: set color depending on darkMode
  for _, sym in ipairs({ "∫", "dx", "d/dx", "Σ", "π", "∞", "∂" }) do
    local x = math.random(0, w - 40)
    local y = math.random(35, h - 60)
    if darkMode then
      gc:setColorRGB(120,120,120)
    else
      gc:setColorRGB(unpack(palette.faded))
    end
    gc:drawString(sym, x, y, "top")
  end

  -- Gradient header (subtle)
  for i = 0, 34 do
    local t = i/34
    local r = math.floor(palette.header[1]*(1-t) + palette.header[1]*t)
    local g = math.floor(palette.header[2]*(1-t) + palette.header[2]*t)
    local b = math.floor(palette.header[3]*(1-t) + palette.header[3]*t)
    gc:setColorRGB(r, g, b)
    gc:drawLine(0, i, w, i)
  end
  -- header/title section: set color for header text
  gc:setColorRGB(255,255,255)
  gc:setFont("serif", "b", 18)
  gc:drawString("∂", 10, 3, "top")
  gc:setFont("sansserif", "b", 16)
  gc:drawString("Symbolic Calculus Engine", 32, 10, "top")
  gc:setColorRGB(unpack(palette.text))
  gc:setFont("sansserif", "i", 10)
  gc:drawString(" ", w - 110, 10, "top")

  if view == "main" then
    gc:setColorRGB(unpack(palette.text))
    gc:setFont("sansserif", "r", 12)
    gc:drawString("Input:", 10, 40, "top")
    local inputStr = (input and input ~= "" and input) or "Type here..."
    local outputStr = output or ""
    -- Dynamic input/output box heights
    local in_box_h = math.max(25, getPrettyPrintHeight(inputStr, gc) + 8)
    local out_box_h = math.max(25, getPrettyPrintHeight(outputStr, gc) + 8)

    -- Input box (modern fillRect/drawRect, improved padding/colors)
    gc:setColorRGB(unpack(palette.inputBG)) -- input background
    gc:fillRect(10, 60, w - 20, in_box_h)
    gc:setColorRGB(unpack(palette.inputBorder)) -- input border
    gc:drawRect(10, 60, w - 20, in_box_h)
    gc:setColorRGB(unpack(palette.text))
    prettyPrint(inputStr, gc, 18, 60 + math.floor((in_box_h - getPrettyPrintHeight(inputStr, gc))/2), w - 24)

    -- Autoprompt suggestions
    gc:setFont("sansserif", "i", 9)
    local suggestion_y = 60 + in_box_h + 5
    if input:find("^d/dx") then
      gc:setColorRGB(unpack(palette.text))
      gc:drawString("Derivative of an expression, e.g. d/dx(x^2)", 18, suggestion_y, "top")
      suggestion_y = suggestion_y + 16
    end
    if input:find("^∫%(") or input:find("^int%(") then
      gc:setColorRGB(unpack(palette.text))
      gc:drawString("Integral: ∫(x^2)dx or int(x^2)", 18, suggestion_y, "top")
      suggestion_y = suggestion_y + 16
    end
    if input:find("^solve%(") then
      gc:setColorRGB(unpack(palette.text))
      gc:drawString("Equation solver: solve(x^2 = 4)", 18, suggestion_y, "top")
      suggestion_y = suggestion_y + 16
    end
    if input:find("^let ") then
      gc:setColorRGB(unpack(palette.text))
      gc:drawString("Function: let f(x) = x^2", 18, suggestion_y, "top")
      suggestion_y = suggestion_y + 16
    end

    -- Output box (modern fillRect/drawRect, fixed position/colors)
    local outputTop = 132
    gc:setColorRGB(unpack(palette.outBG)) -- output background
    gc:fillRect(10, outputTop, w - 20, out_box_h)
    gc:setColorRGB(unpack(palette.outBorder)) -- output border
    gc:drawRect(10, outputTop, w - 20, out_box_h)
    gc:setColorRGB(unpack(palette.text))
    prettyPrint(outputStr, gc, 18, outputTop + math.floor((out_box_h - getPrettyPrintHeight(outputStr, gc))/2), w - 24)

    -- Footer instructions
    gc:setFont("sansserif", "i", 10)
    gc:setColorRGB(unpack(palette.text))
    gc:drawString("↵ ENTER = compute   |   TAB = switch view", 18, h - 40, "top")
    gc:drawString("TAB = switch view (History, About, Help)", 18, h - 55, "top")
    gc:drawString("Supports: d/dx(expr), ∫(expr)dx, int(expr), ast(expr)", 18, h - 25, "top")
  elseif view == "history" then
    gc:setColorRGB(unpack(palette.text))
    gc:setFont("sansserif", "b", 12)
    gc:drawString("Previous Computations:", 10, 40, "top")
    local y = 60
    local historyPad = 8
    gc:setFont("sansserif", "r", 10)
    gc:setColorRGB(unpack(palette.text))
    for i = #history, math.max(1, #history - 10), -1 do
      gc:drawString(history[i], 10, y, "top")
      y = y + 15 + historyPad
    end
  elseif view == "about" then
    gc:setColorRGB(unpack(palette.text))
    gc:setFont("sansserif", "b", 12)
    gc:drawString("About This Tool", 10, 40, "top")
    gc:setFont("sansserif", "r", 10)
    gc:drawString("A lightweight symbolic calculator engine", 10, 60, "top")
    gc:drawString("Built in Lua for TI-Nspire CX II", 10, 75, "top")
    gc:drawString("Supports derivatives, integrals, simplification", 10, 90, "top")
    gc:drawString("Developed by @DeltaDev", 10, 105, "top")
    local toggleText = darkMode and "Switch to Light Mode" or "Switch to Dark Mode"
    gc:setColorRGB(unpack(palette.text))
    gc:drawString(toggleText, 10, 130, "top")
    -- Draw switch box (rectangle) for mode
    local boxX, boxY = 170, 130
    gc:setColorRGB(200, 200, 200)
    gc:drawRect(boxX, boxY, 32, 16)
    if darkMode then
      gc:setColorRGB(90, 170, 220)
      gc:fillRect(boxX+16, boxY, 16, 16)
      gc:setColorRGB(60, 60, 60)
      gc:drawString("L", boxX+18, boxY-2, "top")
    else
      gc:setColorRGB(255, 230, 50)
      gc:fillRect(boxX, boxY, 16, 16)
      gc:setColorRGB(90, 90, 90)
      gc:drawString("D", boxX+2, boxY-2, "top")
    end
  elseif view == "help" then
    gc:setColorRGB(unpack(palette.text))
    gc:setFont("sansserif", "b", 12)
    gc:drawString("Help & Examples", 10, 40, "top")
    gc:setFont("sansserif", "r", 10)
    local y = 60
    local examples = {
      "d/dx(x^2 + 3x)            → 2x + 3",
      "∫(x^2 + 1)dx              → 1/3x^3 + x + C",
      "simplify(2x + 3x)         → 5x",
      "solve(x^2 - 4 = 0)        → x₁ = 2, x₂ = -2",
      "int(x^2, 0, 2)            → (4/3) - (0)",
      "let f(x) = x^2 + 1        → Store a function",
      "f(2)                      → 5",
      "ast(x^2 + 2x + 1)         → Abstract Syntax Tree",
    }
    for _, ex in ipairs(examples) do
      gc:drawString(ex, 10, y, "top")
      y = y + 15
    end
  end
end

function on.mouseDown(x, y)
  -- Switch box: (x in [170,202], y in [130,146])
  if view == "about" and y >= 130 and y <= 146 and x >= 170 and x <= 202 then
    darkMode = not darkMode
    if store then pcall(function() store.set("cas_darkMode", darkMode) end) end
    platform.window:invalidate()
  -- Also allow toggling by clicking on the text (legacy region)
  elseif view == "about" and y >= 130 and y <= 150 then
    darkMode = not darkMode
    if store then pcall(function() store.set("cas_darkMode", darkMode) end) end
    platform.window:invalidate()
  end
end
