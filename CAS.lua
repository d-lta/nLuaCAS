



-- Additional CAS commands:
-- expand(expr)
-- subs(expr, var, val)
-- factor(expr)
-- gcd(a, b)
-- lcm(a, b)
-- trigid(expr)

platform.apilevel = "2.4"

-- Global error flag for LuaCAS engine status
_G.luaCASerror = false

-- CAS core routines

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
  local j = 2
  while j <= #tokens do
    if tokens[j-1]:match("[%d%a%)%]]") and tokens[j]:match("[%a%(]") then
      table.insert(tokens, j, "*")
      j = j + 1
    end
    j = j + 1
  end
  return tokens
end

-- Parsing helpers
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

function buildAST(tokens)
  local ast, nextIndex = parseExpr(tokens, 1)
  if nextIndex <= #tokens then
    return nil
  end
  return ast
end

function astToString(ast)
  if not ast then return "?" end
  local t = ast.type
  if t == "number" then return tostring(ast.value) end
  if t == "variable" then return ast.name end
  if t == "func" then
    return ast.name .. "(" .. astToString(ast.args[1]) .. ")"
  end
  if t == "power" then
    return "("..astToString(ast.left)..")^("..astToString(ast.right)..")"
  end
  if t == "mul" then
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

function simplifyAST(ast)
  if not ast then return nil end
  local t = ast.type
  if t == "func" then
    return { type = "func", name = ast.name, args = {simplifyAST(ast.args[1])} }
  end
  if t == "number" or t == "variable" then
    return ast
  end
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
    elseif node.type == "mul" and node.left.type == "variable" and node.right.type == "variable" and node.left.name == node.right.name then
      return 1, node.left.name, 2
    elseif node.type == "mul" and node.left.type == "variable" and node.right.type == "power"
      and node.right.left.type == "variable" and node.right.right.type == "number"
      and node.left.name == node.right.left.name then
      return 1, node.left.name, node.right.right.value + 1
    elseif node.type == "mul" and node.left.type == "power" and node.right.type == "variable"
      and node.left.left.type == "variable" and node.left.right.type == "number"
      and node.left.left.name == node.right.name then
      return 1, node.right.name, node.left.right.value + 1
    elseif node.type == "mul" and node.left.type == "power" and node.right.type == "power"
      and node.left.left.type == "variable" and node.left.right.type == "number"
      and node.right.left.type == "variable" and node.right.right.type == "number"
      and node.left.left.name == node.right.left.name then
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
    if left.type == "number" and right.type == "number" then
      return {type="number", value=(t=="add" and left.value+right.value or left.value-right.value)}
    end
    local combined = combineLikeTerms(left, right, t)
    if combined then return combined end
    if left.type == "number" and left.value == 0 then return right end
    if right.type == "number" and right.value == 0 then return left end
    return {type=t, left=left, right=right}
  end
  if t == "mul" then
    local left = simplifyAST(ast.left)
    local right = simplifyAST(ast.right)
    if left.type == "number" and right.type == "number" then
      return {type="number", value=left.value * right.value}
    end
    if (left.type == "number" and left.value == 0) or (right.type == "number" and right.value == 0) then
      return {type="number", value=0}
    end
    if left.type == "number" and left.value == 1 then return right end
    if right.type == "number" and right.value == 1 then return left end
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
    if right.type == "number" and right.value == 1 then return left end
    return {type="div", left=left, right=right}
  end
  if t == "power" then
    local base = simplifyAST(ast.left)
    local exp = simplifyAST(ast.right)
    if base.type == "number" and exp.type == "number" then
      return {type="number", value=base.value ^ exp.value}
    end
    if exp.type == "number" and exp.value == 1 then return base end
    if exp.type == "number" and exp.value == 0 then return {type="number", value=1} end
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

function solve(eqn)
  eqn = eqn:gsub("%s+", "")
  local lhs, rhs = eqn:match("(.+)%=(.+)")
  if not lhs or not rhs then
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
  if memory[expr] then
    return simplify(memory[expr])
  end
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
  expr = expr:gsub("%s+", "")
  if expr:match("^∂/∂[yz]%(") then
    local var = expr:sub(4, 4)
    local subexpr = expr:match("∂/∂"..var.."%((.+)%)")
    if subexpr then
      return "Partial w.r.t " .. var .. ": " .. derivative(subexpr)
    else
      return "Invalid partial"
    end
  end
  if expr:match("^%d+$") then return "0" end
  if expr == "x" then return "1" end
  if expr == "sin(x)" then return "cos(x)" end
  if expr == "cos(x)" then return "-sin(x)" end
  if expr == "tan(x)" then return "sec(x)^2" end
  if expr == "sec(x)" then return "sec(x)tan(x)" end
  if expr == "csc(x)" then return "-csc(x)cot(x)" end
  if expr == "cot(x)" then return "-csc(x)^2" end
  if expr == "e^x" then return "e^x" end
  local a = expr:match("^(%d+)%^x$")
  if a then return expr .. "*ln(" .. a .. ")" end
  if expr == "ln(x)" then return "1/x" end
  -- Additional function derivatives
  if expr == "exp(x)" then return "exp(x)" end
  if expr == "log(x)" then return "1/x" end
  if expr == "sqrt(x)" then return "1/(2*sqrt(x))" end
  if expr == "abs(x)" then return "x/abs(x)" end
  if expr == "asin(x)" then return "1/sqrt(1-x^2)" end
  if expr == "acos(x)" then return "-1/sqrt(1-x^2)" end
  if expr == "atan(x)" then return "1/(1+x^2)" end
  local inner, offset, exponent = expr:match("^%((%-?%d*%.?%d*)x([%+%-]%d+)%)%^([%d%.]+)$")
  if inner and exponent then
    local acoef = tonumber(inner) ~= 0 and tonumber(inner) or 1
    local n = tonumber(exponent)
    local new_exp = n - 1
    local outer = tostring(n) .. "(" .. inner .. "x" .. offset .. ")^" .. new_exp
    return outer .. "*" .. tostring(acoef)
  end
  -- x^n
  local base, exponent2 = expr:match("^(x)%^([%d%.]+)$")
  if base and exponent2 then
    local new_exp2 = tonumber(exponent2) - 1
    if new_exp2 == 1 then
      return exponent2 .. "x"
    elseif new_exp2 == 0 then
      return exponent2
    else
      return exponent2 .. "x^" .. new_exp2
    end
  end
  -- x^(n)
  local baseP, exponentP = expr:match("^(x)%^%(([%d%.%-]+)%)$")
  if baseP and exponentP then
    local new_expP = tonumber(exponentP) - 1
    if new_expP == 1 then
      return exponentP .. "x"
    elseif new_expP == 0 then
      return exponentP
    else
      return exponentP .. "x^" .. new_expP
    end
  end
  -- a*x^n
  local coeff, power = expr:match("^(%-?%d*%.?%d*)x%^([%d%.]+)$")
  if coeff and power then
    if coeff == "" then coeff = "1" end
    local new_coeff = tonumber(coeff) * tonumber(power)
    local new_exp2 = tonumber(power) - 1
    if new_exp2 == 1 then
      return tostring(new_coeff) .. "x"
    elseif new_exp2 == 0 then
      return tostring(new_coeff)
    else
      return tostring(new_coeff) .. "x^" .. tostring(new_exp2)
    end
  end
  -- a*x^(n)
  local coeffP, powerP = expr:match("^(%-?%d*%.?%d*)x%^%(([%d%.%-]+)%)$")
  if coeffP and powerP then
    if coeffP == "" then coeffP = "1" end
    local new_coeffP = tonumber(coeffP) * tonumber(powerP)
    local new_expP = tonumber(powerP) - 1
    if new_expP == 1 then
      return tostring(new_coeffP) .. "x"
    elseif new_expP == 0 then
      return tostring(new_coeffP)
    else
      return tostring(new_coeffP) .. "x^" .. tostring(new_expP)
    end
  end
  -- a*x
  local coeff2 = expr:match("^(%-?%d*%.?%d*)x$")
  if coeff2 then
    if coeff2 == "" then coeff2 = "1" end
    return tostring(coeff2)
  end
  -- sums: split at '+' outside parentheses
  local function split_terms(expr, op)
    local terms = {}
    local level, last = 0, 1
    for i = 1, #expr do
      local c = expr:sub(i,i)
      if c == "(" then level = level + 1 end
      if c == ")" then level = level - 1 end
      if c == op and level == 0 then
        table.insert(terms, expr:sub(last, i-1))
        last = i+1
      end
    end
    if last <= #expr then
      table.insert(terms, expr:sub(last))
    end
    return terms
  end
  -- sums
  if expr:find("%+") then
    local terms = split_terms(expr, "+")
    local out = {}
    for i, term in ipairs(terms) do
      table.insert(out, derivative(term))
    end
    return table.concat(out, " + ")
  end
  -- differences
  if expr:find("%-") then
    local terms = split_terms(expr, "-")
    local out = {}
    for i, term in ipairs(terms) do
      if i == 1 then
        table.insert(out, derivative(term))
      else
        table.insert(out, "-("..derivative(term)..")")
      end
    end
    return table.concat(out, " ")
  end
  -- product rule
  local f, g = expr:match("^(.-)%*(.+)$")
  if f and g then
    return "("..derivative(f)..")*("..g..")+"..f.."*("..derivative(g)..")"
  end
  -- quotient rule
  local num, denom = expr:match("^(.-)/(.-)$")
  if num and denom then
    return "(("..derivative(num)..")*("..denom..")-("..num..")*("..derivative(denom).."))/("..denom..")^2"
  end
  -- Chain rule for f(ax+b)
  local fname, inner = expr:match("^(%a+)%(([%d%.%-]*x[%+%-]?[%d%.]*)%)$")
  if fname and inner then
      local inner_deriv = derivative(inner)
      if fname == "sin" then
          return "cos(" .. inner .. ")*(" .. inner_deriv .. ")"
      elseif fname == "cos" then
          return "-sin(" .. inner .. ")*(" .. inner_deriv .. ")"
      elseif fname == "tan" then
          return "sec(" .. inner .. ")^2*(" .. inner_deriv .. ")"
      elseif fname == "exp" then
          return "exp(" .. inner .. ")*(" .. inner_deriv .. ")"
      elseif fname == "log" then
          return "1/(" .. inner .. ")*(" .. inner_deriv .. ")"
      elseif fname == "sqrt" then
          return "1/(2*sqrt("..inner.."))*("..inner_deriv..")"
      end
  end
  -- nth order
  local order, var2, subexpr2 = expr:match("^d(%d+)/d([a-zA-Z])%^(%d+)%((.+)%)$")
  if order and var2 and subexpr2 then
    order = tonumber(order)
    local result = subexpr2
    for i = 1, order do
      result = derivative(result)
    end
    return result
  end
  if expr:match("^d²/dx²%(.+%)$") then
    local se = expr:match("^d²/dx²%((.+)%)$")
    if se then return derivative(derivative(se)) end
  end
  return "d/dx not supported for: "..expr
end

function integrate(expr)
  expr = expr:gsub("%s+", "")
  if expr:match("^%d+$") then return expr .. "x + C" end
  if expr == "x" then return "0.5x^2 + C" end
  if expr == "sin(x)" then return "-cos(x) + C" end
  if expr == "cos(x)" then return "sin(x) + C" end
  if expr == "tan(x)" then return "-ln|cos(x)| + C" end
  if expr == "sec(x)^2" then return "tan(x) + C" end
  if expr == "csc(x)^2" then return "-cot(x) + C" end
  if expr == "sec(x)tan(x)" then return "sec(x) + C" end
  if expr == "csc(x)cot(x)" then return "-csc(x) + C" end
  if expr == "e^x" then return "e^x + C" end
  if expr == "ln(x)" then return "x*ln(x) - x + C" end
  -- Additional function integrals
  if expr == "exp(x)" then return "exp(x) + C" end
  if expr == "log(x)" then return "x*log(x) - x + C" end
  if expr == "sqrt(x)" then return "2/3*x^(3/2) + C" end
  if expr == "1/x" then return "log(x) + C" end
  if expr == "1/(1+x^2)" then return "atan(x) + C" end
  if expr == "1/sqrt(1-x^2)" then return "asin(x) + C" end
  if expr == "1/(1-x^2)" then return "atanh(x) + C" end
  -- x^n
  local base2, exponent3 = expr:match("^(x)%^([%d%.]+)$")
  if base2 and exponent3 then
    local new_exp3 = tonumber(exponent3) + 1
    return "x^" .. new_exp3 .. "/" .. new_exp3 .. " + C"
  end
  -- x^(n)
  local base2P, exponent3P = expr:match("^(x)%^%(([%d%.%-]+)%)$")
  if base2P and exponent3P then
    local new_exp3P = tonumber(exponent3P) + 1
    return "x^" .. new_exp3P .. "/" .. new_exp3P .. " + C"
  end
  -- a*x^n
  local coeff2, power2 = expr:match("^(%-?%d*%.?%d*)x%^([%d%.]+)$")
  if coeff2 and power2 then
    if coeff2 == "" then coeff2 = "1" end
    local new_exp4 = tonumber(power2) + 1
    local result2 = tonumber(coeff2) / new_exp4
    return tostring(result2) .. "x^" .. tostring(new_exp4) .. " + C"
  end
  -- a*x^(n)
  local coeff2P, power2P = expr:match("^(%-?%d*%.?%d*)x%^%(([%d%.%-]+)%)$")
  if coeff2P and power2P then
    if coeff2P == "" then coeff2P = "1" end
    local new_exp4P = tonumber(power2P) + 1
    local result2P = tonumber(coeff2P) / new_exp4P
    return tostring(result2P) .. "x^" .. tostring(new_exp4P) .. " + C"
  end
  -- a*x
  coeff2 = expr:match("^(%-?%d*%.?%d*)x$")
  if coeff2 then
    if coeff2 == "" then coeff2 = "1" end
    return coeff2 .. "*0.5x^2 + C"
  end
  -- sums: split at '+' outside parentheses
  local function split_terms(expr, op)
    local terms = {}
    local level, last = 0, 1
    for i = 1, #expr do
      local c = expr:sub(i,i)
      if c == "(" then level = level + 1 end
      if c == ")" then level = level - 1 end
      if c == op and level == 0 then
        table.insert(terms, expr:sub(last, i-1))
        last = i+1
      end
    end
    if last <= #expr then
      table.insert(terms, expr:sub(last))
    end
    return terms
  end
  -- sums
  if expr:find("%+") then
    local terms = split_terms(expr, "+")
    local out = {}
    for i, term in ipairs(terms) do
      table.insert(out, integrate(term))
    end
    return table.concat(out, " + ")
  end
  -- differences
  if expr:find("%-") then
    local terms = split_terms(expr, "-")
    local out = {}
    for i, term in ipairs(terms) do
      if i == 1 then
        table.insert(out, integrate(term))
      else
        table.insert(out, "-("..integrate(term)..")")
      end
    end
    return table.concat(out, " ")
  end
  return "∫ not supported for: " .. expr

end

-- Expand simple powers
function expand(expr)
    -- (x+a)^2 -> x^2+2ax+a^2
    local a, b = expr:match("^%((x)%+([%d%.%-]+)%)%^2$")
    if a and b then
        return "x^2+" .. tostring(2*tonumber(b)) .. "x+" .. tostring(tonumber(b)*tonumber(b))
    end
    -- (a*x+b)^2
    local c, d, e = expr:match("^%(([%d%.%-]*)x%+([%d%.%-]+)%)%^2$")
    if c and d then
        local cx = tonumber(c) ~= 0 and tonumber(c) or 1
        local bx = tonumber(d)
        return tostring(cx*cx).."x^2+"..tostring(2*cx*bx).."x+"..tostring(bx*bx)
    end
    -- (x+a)^3
    local a2, b2 = expr:match("^%((x)%+([%d%.%-]+)%)%^3$")
    if a2 and b2 then
        local bnum = tonumber(b2)
        return "x^3+"..tostring(3*bnum).."x^2+"..tostring(3*bnum^2).."x+"..tostring(bnum^3)
    end
    -- Default: cannot expand
    return "Expand not supported for: " .. expr
end

-- Substitute variable
function subs(expr, var, val)
    local replaced = expr:gsub(var, "(" .. val .. ")")
    local success, res = pcall(function()
        if replaced:match("^[%d%+%-%*/%^%.%(%)]+$") then
            return load("return "..replaced)()
        else
            return replaced
        end
    end)
    if success then
        return tostring(res)
    else
        return replaced
    end
end

-- Polynomial factoring (quadratics only for now: ax^2+bx+c)
function factor(expr)
    local a, b, c = expr:match("^(%-?%d*)x%^2%+([%-?%d]*)x%+([%-?%d]*)$")
    if a and b and c then
        a = tonumber(a ~= "" and a or "1")
        b = tonumber(b ~= "" and b or "0")
        c = tonumber(c ~= "" and c or "0")
        local D = b^2 - 4*a*c
        if D < 0 then return "Irreducible over ℝ" end
        local sqrtD = math.sqrt(D)
        local r1 = (-b + sqrtD) / (2*a)
        local r2 = (-b - sqrtD) / (2*a)
        return string.format("%g*(x-%g)*(x-%g)", a, r1, r2)
    end
    return "Factoring not supported for: "..expr
end

-- GCD and LCM of two integers
function gcd(a, b)
    a = tonumber(a) b = tonumber(b)
    if not a or not b then return "GCD error" end
    while b ~= 0 do a, b = b, a % b end
    return tostring(math.abs(a))
end
function lcm(a, b)
    a = tonumber(a) b = tonumber(b)
    if not a or not b then return "LCM error" end
    return tostring(math.floor(math.abs(a * b) / tonumber(gcd(a, b))))
end

-- Trigonometric identities for sin, cos, tan double angle
function trigid(expr)
    if expr == "sin(2x)" then return "2sin(x)cos(x)" end
    if expr == "cos(2x)" then return "cos(x)^2 - sin(x)^2" end
    if expr == "tan(2x)" then return "2tan(x)/(1-tan(x)^2)" end
    if expr == "sin^2(x)" then return "(1-cos(2x))/2" end
    if expr == "cos^2(x)" then return "(1+cos(2x))/2" end
    return "Trig identity not supported for: "..expr
end

-- ETK View System (copied from S2.lua)
defaultFocus = nil

View = class()

function View:init(window)
	self.window = window
	self.widgetList = {}
	self.focusList = {}
	self.currentFocus = 0
	self.currentCursor = "default"
	self.prev_mousex = 0
	self.prev_mousey = 0
end

function View:invalidate()
	self.window:invalidate()
end

function View:setCursor(cursor)
	if cursor ~= self.currentCursor then
		self.currentCursor = cursor
		self:invalidate()
	end
end

function View:add(o)
	table.insert(self.widgetList, o)
	self:repos(o)
	if o.acceptsFocus then
		table.insert(self.focusList, 1, o)
		if self.currentFocus > 0 then
			self.currentFocus = self.currentFocus + 1
		end
	end
	return o
end

function View:remove(o)
	if self:getFocus() == o then
		o:releaseFocus()
	end
	local i = 1
	local f = 0
	while i <= #self.focusList do
		if self.focusList[i] == o then
			f = i
		end
		i = i + 1
	end
	if f > 0 then
		if self:getFocus() == o then
			self:tabForward()
		end
		table.remove(self.focusList, f)
		if self.currentFocus > f then
			self.currentFocus = self.currentFocus - 1
		end
	end
	f = 0
	i = 1
	while i <= #self.widgetList do
		if self.widgetList[i] == o then
			f = i
		end
		i = i + 1
	end
	if f > 0 then
		table.remove(self.widgetList, f)
	end
end

function View:repos(o)
	local x = o.x
	local y = o.y
	local w = o.w
	local h = o.h
	if o.hConstraint == "right" then
		x = scrWidth - o.w - o.dx1
	elseif o.hConstraint == "center" then
		x = (scrWidth - o.w + o.dx1) / 2
	elseif o.hConstraint == "justify" then
		w = scrWidth - o.x - o.dx1
	end
	if o.vConstraint == "bottom" then
		y = scrHeight - o.h - o.dy1
	elseif o.vConstraint == "middle" then
		y = (scrHeight - o.h + o.dy1) / 2
	elseif o.vConstraint == "justify" then
		h = scrHeight - o.y - o.dy1
	end
	o:repos(x, y)
	o:resize(w, h)
end

function View:resize()
	for _, o in ipairs(self.widgetList) do
		self:repos(o)
	end
end

function View:hide(o)
	if o.visible then
		o.visible = false
		self:releaseFocus(o)
		if o:contains(self.prev_mousex, self.prev_mousey) then
			o:onMouseLeave(o.x - 1, o.y - 1)
		end
		self:invalidate()
	end
end

function View:show(o)
	if not o.visible then
		o.visible = true
		if o:contains(self.prev_mousex, self.prev_mousey) then
			o:onMouseEnter(self.prev_mousex, self.prev_mousey)
		end
		self:invalidate()
	end
end

function View:getFocus()
	if self.currentFocus == 0 then
		return nil
	end
	return self.focusList[self.currentFocus]
end

function View:setFocus(obj)
	if self.currentFocus ~= 0 then
		if self.focusList[self.currentFocus] == obj then
			return
		end
		self.focusList[self.currentFocus]:releaseFocus()
	end
	self.currentFocus = 0
	for i = 1, #self.focusList do
		if self.focusList[i] == obj then
			self.currentFocus = i
			obj:setFocus()
			self:invalidate()
			break
		end
	end
end

function View:releaseFocus(obj)
	if self.currentFocus ~= 0 then
		if self.focusList[self.currentFocus] == obj then
			self.currentFocus = 0
			obj:releaseFocus()
			self:invalidate()
		end
	end
end

function View:sendStringToFocus(str)
	local o = self:getFocus()
	if not o then
		o = defaultFocus
		self:setFocus(o)
	end
	if o then
		if o.visible then
			if o:addString(str) then
				self:invalidate()
			else
				o = nil
			end
		end
	end

	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible then
				if o:addString(str) then
					self:setFocus(o)
					self:invalidate()
					break
				end
			end
		end
	end
end

function View:backSpaceHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsBackSpace then
			o:backSpaceHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsBackSpace then
				o:backSpaceHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

function View:tabForward()
	local nextFocus = self.currentFocus + 1
	if nextFocus > #self.focusList then
		nextFocus = 1
	end
	self:setFocus(self.focusList[nextFocus])
	if self:getFocus() then
		if not self:getFocus().visible then
			self:tabForward()
		end
	end
	self:invalidate()
end

function View:tabBackward()
	local nextFocus = self.currentFocus - 1
	if nextFocus < 1 then
		nextFocus = #self.focusList
	end
	self:setFocus(self.focusList[nextFocus])
	if not self:getFocus().visible then
		self:tabBackward()
	end
	self:invalidate()
end

function View:onMouseDown(x, y)
	for _, o in ipairs(self.widgetList) do
		if o.visible and o.acceptsFocus and o:contains(x, y) then
			self.mouseCaptured = o
			o:onMouseDown(o, window, x - o.x, y - o.y)
			self:setFocus(o)
			self:invalidate()
			return
		end
	end
	if self:getFocus() then
		self:setFocus(nil)
		self:invalidate()
	end
end

function View:onMouseMove(x, y)
	local prev_mousex = self.prev_mousex
	local prev_mousey = self.prev_mousey
	for _, o in ipairs(self.widgetList) do
		local xyin = o:contains(x, y)
		local prev_xyin = o:contains(prev_mousex, prev_mousey)
		if xyin and not prev_xyin and o.visible then
			o:onMouseEnter(x, y)
			self:invalidate()
		elseif prev_xyin and (not xyin or not o.visible) then
			o:onMouseLeave(x, y)
			self:invalidate()
		end
	end
	self.prev_mousex = x
	self.prev_mousey = y
end

function View:onMouseUp(x, y)
	local mc = self.mouseCaptured
	if mc then
		self.mouseCaptured = nil
		if mc:contains(x, y) then
			mc:onMouseUp(x - mc.x, y - mc.y)
		end
	end
end

function View:enterHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsEnter then
			o:enterHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsEnter then
				o:enterHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

function View:arrowLeftHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsArrowLeft then
			o:arrowLeftHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsArrowLeft then
				o:arrowLeftHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

function View:arrowRightHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsArrowRight then
			o:arrowRightHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsArrowRight then
				o:arrowRightHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

function View:arrowUpHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsArrowUp then
			o:arrowUpHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsArrowUp then
				o:arrowUpHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

function View:arrowDownHandler()
	local o = self:getFocus()
	if o then
		if o.visible and o.acceptsArrowDown then
			o:arrowDownHandler()
			self:setFocus(o)
			self:invalidate()
		else
			o = nil
		end
	end
	if not o then
		for _, o in ipairs(self.focusList) do
			if o.visible and o.acceptsArrowDown then
				o:arrowDownHandler()
				self:setFocus(o)
				self:invalidate()
				break
			end
		end
	end
end

function View:paint(gc)
	local fo = self:getFocus()
	for _, o in ipairs(self.widgetList) do
		if o.visible then
			o:paint(gc, fo == o)
			if fo == o then
				gc:setColorRGB(100, 150, 255)
				gc:drawRect(o.x - 1, o.y - 1, o.w + 1, o.h + 1)
				gc:setPen("thin", "smooth")
				gc:setColorRGB(0, 0, 0)
			end
		end
	end
	cursor.set(self.currentCursor)
end

theView = nil

Widget = class()

function Widget:setHConstraints(hConstraint, dx1)
	self.hConstraint = hConstraint
	self.dx1 = dx1
end

function Widget:setVConstraints(vConstraint, dy1)
	self.vConstraint = vConstraint
	self.dy1 = dy1
end

function Widget:init(view, x, y, w, h)
	self.xOrig = x
	self.yOrig = y
	self.view = view
	self.x = x
	self.y = y
	self.w = w
	self.h = h
	self.acceptsFocus = false
	self.visible = true
	self.acceptsEnter = false
	self.acceptsEscape = false
	self.acceptsTab = false
	self.acceptsDelete = false
	self.acceptsBackSpace = false
	self.acceptsReturn = false
	self.acceptsArrowUp = false
	self.acceptsArrowDown = false
	self.acceptsArrowLeft = false
	self.acceptsArrowRight = false
	self.hConstraint = "left"
	self.vConstraint = "top"
end

function Widget:repos(x, y)
	self.x = x
	self.y = y
end

function Widget:resize(w, h)
	self.w = w
	self.h = h
end

function Widget:setFocus() end
function Widget:releaseFocus() end

function Widget:contains(x, y)
	return x >= self.x and x <= self.x + self.w
			and y >= self.y and y <= self.y + self.h
end

function Widget:onMouseEnter(x, y) end
function Widget:onMouseLeave(x, y) end
function Widget:paint(gc, focused) end
function Widget:enterHandler() end
function Widget:escapeHandler() end
function Widget:tabHandler() end
function Widget:deleteHandler() end
function Widget:backSpaceHandler() end
function Widget:returnHandler() end
function Widget:arrowUpHandler() end
function Widget:arrowDownHandler() end
function Widget:arrowLeftHandler() end
function Widget:arrowRightHandler() end
function Widget:onMouseDown(x, y) end
function Widget:onMouseUp(x, y) end

Button = class(Widget)

function Button:init(view, x, y, w, h, default, command, shortcut)
	Widget.init(self, view, x, y, w, h)
	self.acceptsFocus = true
	self.command = command or function() end
	self.default = default
	self.shortcut = shortcut
	self.clicked = false
	self.highlighted = false
	self.acceptsEnter = true
end

function Button:enterHandler()
	if self.acceptsEnter then
		self:command()
	end
end

function Button:escapeHandler()
	if self.acceptsEscape then
		self:command()
	end
end

function Button:tabHandler()
	if self.acceptsTab then
		self:command()
	end
end

function Button:deleteHandler()
	if self.acceptsDelete then
		self:command()
	end
end

function Button:backSpaceHandler()
	if self.acceptsBackSpace then
		self:command()
	end
end

function Button:returnHandler()
	if self.acceptsReturn then
		self:command()
	end
end

function Button:arrowUpHandler()
	if self.acceptsArrowUp then
		self:command()
	end
end

function Button:arrowDownHandler()
	if self.acceptsArrowDown then
		self:command()
	end
end

function Button:arrowLeftHandler()
	if self.acceptsArrowLeft then
		self:command()
	end
end

function Button:arrowRightHandler()
	if self.acceptsArrowRight then
		self:command()
	end
end

function Button:onMouseDown(x, y)
	self.clicked = true
	self.highlighted = true
end

function Button:onMouseEnter(x, y)
	theView:setCursor("hand pointer")
	if self.clicked and not self.highlighted then
		self.highlighted = true
	end
end

function Button:onMouseLeave(x, y)
	theView:setCursor("default")
	if self.clicked and self.highlighted then
		self.highlighted = false
	end
end

function Button:cancelClick()
	if self.clicked then
		self.highlighted = false
		self.clicked = false
	end
end

function Button:onMouseUp(x, y)
	self:cancelClick()
	self:command()
end

function Button:addString(str)
	if str == " " or str == self.shortcut then
		self:command()
		return true
	end
	return false
end

ImgLabel = class(Widget)

function ImgLabel:init(view, x, y, img)
	self.img = image.new(img)
	self.w = image.width(self.img)
	self.h = image.height(self.img)
	Widget.init(self, view, x, y, self.w, self.h)
end

function ImgLabel:paint(gc, focused)
	gc:drawImage(self.img, self.x, self.y)
end

ImgButton = class(Button)

function ImgButton:init(view, x, y, img, command, shortcut)
	self.img = image.new(img)
	self.w = image.width(self.img)
	self.h = image.height(self.img)
	Button.init(self, view, x, y, self.w, self.h, false, command, shortcut)
end

function ImgButton:paint(gc, focused)
	gc:drawImage(self.img, self.x, self.y)
end

TextButton = class(Button)

function TextButton:init(view, x, y, text, command, shortcut)
	self.textid = text
	self.text = getLocaleText(text)
	self:resize(0, 0)
	Button.init(self, view, x, y, self.w, self.h, false, command, shortcut)
end

function TextButton:resize(w, h)
	self.text = getLocaleText(self.textid)
	self.w = getStringWidth(self.text) + 5
	self.h = getStringHeight(self.text) + 5
end

function TextButton:paint(gc, focused)
	gc:setColorRGB(223, 223, 223)
	gc:drawRect(self.x + 1, self.y + 1, self.w - 2, self.h - 2)
	gc:setColorRGB(191, 191, 191)
	gc:fillRect(self.x + 1, self.y + 1, self.w - 3, self.h - 3)
	gc:setColorRGB(223, 223, 223)
	gc:drawString(self.text, self.x + 3, self.y + 3, "top")
	gc:setColorRGB(0, 0, 0)
	gc:drawString(self.text, self.x + 2, self.y + 2, "top")
	gc:drawRect(self.x, self.y, self.w - 2, self.h - 2)
end

VScrollBar = class(Widget)

function VScrollBar:init(view, x, y, w, h)
	self.pos = 10
	self.siz = 10
	Widget.init(self, view, x, y, w, h)
end

function VScrollBar:paint(gc, focused)
	gc:setColorRGB(0, 0, 0)
	gc:drawRect(self.x, self.y, self.w, self.h)
	gc:fillRect(self.x + 2, self.y + self.h - (self.h - 4) * (self.pos + self.siz) / 100 - 2, self.w - 3, math.max(1, (self.h - 4) * self.siz / 100 + 1))
end

TextLabel = class(Widget)

function TextLabel:init(view, x, y, text)
	self:setText(text)
	Widget.init(self, view, x, y, self.w, self.h)
end

function TextLabel:resize(w, h)
	self.text = getLocaleText(self.textid)
	self.w = getStringWidth(self.text)
	self.h = getStringHeight(self.text)
end

function TextLabel:setText(text)
	self.textid = text
	self.text = getLocaleText(text)
	self:resize(0, 0)
end

function TextLabel:getText()
	return self.text
end

function TextLabel:paint(gc, focused)
	gc:setColorRGB(0, 0, 0)
	gc:drawString(self.text, self.x, self.y, "top")
end

RichTextEditor = class(Widget)

function RichTextEditor:init(view, x, y, w, h, text)
	self.editor = D2Editor.newRichText()
	self.readOnly = false
	self:repos(x, y)
	self.editor:setFontSize(fsize)
	self.editor:setFocus(false)
	self.text = text
	self:resize(w, h)
	Widget.init(self, view, x, y, self.w, self.h, true)
	self.acceptsFocus = true
	self.editor:setExpression(text)
	self.editor:setBorder(1)
end

function RichTextEditor:onMouseEnter(x, y)
	theView:setCursor("text")
end

function RichTextEditor:onMouseLeave(x, y)
	theView:setCursor("default")
end

function RichTextEditor:repos(x, y)
	if not self.editor then return end
	self.editor:setBorderColor((showEditorsBorders and 0) or 0xffffff )
	self.editor:move(x, y)
	Widget.repos(self, x, y)
end

function RichTextEditor:resize(w, h)
	if not self.editor then return end
	self.editor:resize(w, h)
	Widget.resize(self, w, h)
end

function RichTextEditor:setFocus()
	self.editor:setFocus(true)
end

function RichTextEditor:releaseFocus()
	self.editor:setFocus(false)
end

function RichTextEditor:addString(str)
	local currentText = self.editor:getText() or ""
	self.editor:setText(currentText .. str)
	return true
end

function RichTextEditor:paint(gc, focused) end

MathEditor = class(RichTextEditor)

function ulen(str)
	if not str then return 0 end
	local n = string.len(str)
	local i = 1
	local j = 1
	local c
	while (j <= n) do
		c = string.len(string.usub(str, i, i))
		j = j + c
		i = i + 1
	end
	return i - 1
end

function MathEditor:init(view, x, y, w, h, text)
	RichTextEditor.init(self, view, x, y, w, h, text)
	self.editor:setBorder(1)
	self.acceptsEnter = true
	self.acceptsBackSpace = true
	self.result = false
	self.editor:registerFilter({
		arrowLeft = function()
			_, curpos = self.editor:getExpressionSelection()
			if curpos < 7 then
				on.arrowLeft()
				return true
			end
			return false
		end,
		arrowRight = function()
			currentText, curpos = self.editor:getExpressionSelection()
			if curpos > ulen(currentText) - 2 then
				on.arrowRight()
				return true
			end
			return false
		end,
		tabKey = function()
			theView:tabForward()
			return true
		end,
		mouseDown = function(x, y)
			theView:onMouseDown(x, y)
			return false
		end,
		backspaceKey = function()
			if (self == fctEditor) then
				self:fixCursor()
				_, curpos = self.editor:getExpressionSelection()
				if curpos <= 6 then return true end
				return false
			else
				self:backSpaceHandler()
				return true
			end
		end,
		deleteKey = function()
			if (self == fctEditor) then
				self:fixCursor()
				currentText, curpos = self.editor:getExpressionSelection()
				if curpos >= ulen(currentText) - 1 then return true end
				return false
			else
				self:backSpaceHandler()
				return true
			end
		end,
		enterKey = function()
			self:enterHandler()
			return true
		end,
		returnKey = function()
			theView:enterHandler()
			return true
		end,
		escapeKey = function()
			on.escapeKey()
			return true
		end,
		charIn = function(c)
			if (self == fctEditor) then
				self:fixCursor()
				return false
			else
				return self.readOnly
			end
		end
	})
end

function MathEditor:fixContent()
	local currentText = self.editor:getExpressionSelection()
	if currentText == "" or currentText == nil then
		self.editor:createMathBox()
	end
end

function MathEditor:fixCursor()
	local currentText, curpos, selstart = self.editor:getExpressionSelection()
	local l = ulen(currentText)
	if curpos < 6 or selstart < 6 or curpos > l - 1 or selstart > l - 1 then
		if curpos < 6 then curpos = 6 end
		if selstart < 6 then selstart = 6 end
		if curpos > l - 1 then curpos = l - 1 end
		if selstart > l - 1 then selstart = l - 1 end
		self.editor:setExpression(currentText, curpos, selstart)
	end
end

function MathEditor:getExpression()
	if not self.editor then return "" end
	local rawexpr = self.editor:getExpression()
	local expr = ""
	local n = string.len(rawexpr)
	local b = 0
	local bs = 0
	local bi = 0
	local status = 0
	local i = 1
	while i <= n do
		local c = string.sub(rawexpr, i, i)
		if c == "{" then
			b = b + 1
		elseif c == "}" then
			b = b - 1
		end
		if status == 0 then
			if string.sub(rawexpr, i, i + 5) == "\\0el {" then
				bs = i + 6
				i = i + 5
				status = 1
				bi = b
				b = b + 1
			end
		else
			if b == bi then
				status = 0
				expr = expr .. string.sub(rawexpr, bs, i - 1)
			end
		end
		i = i + 1
	end
	return expr
end

function MathEditor:setFocus()
	if not self.editor then return end
	self.editor:setFocus(true)
end

function MathEditor:releaseFocus()
	if not self.editor then return end
	self.editor:setFocus(false)
end

function MathEditor:addString(str)
	if not self.editor then return false end
	self:fixCursor()
	local currentText, curpos, selstart = self.editor:getExpressionSelection()
	local newText = string.usub(currentText, 1, math.min(curpos, selstart)) .. str .. string.usub(currentText, math.max(curpos, selstart) + 1, ulen(currentText))
	self.editor:setExpression(newText, math.min(curpos, selstart) + ulen(str))
	return true
end

function MathEditor:backSpaceHandler()
    -- No-op or custom deletion logic (history removal not implemented)
end

function MathEditor:enterHandler()
    -- Call the custom on.enterKey handler instead of missing global
    on.enterKey()
end

function MathEditor:paint(gc)
	if showHLines and not self.result then
		gc:setColorRGB(100, 100, 100)
		local ycoord = self.y - (showEditorsBorders and 0 or 2)
		gc:drawLine(1, ycoord, platform.window:width() - sbv.w - 2, ycoord)
		gc:setColorRGB(0, 0, 0)
	end
end

function on.arrowUp()
  if theView then
    if theView:getFocus() == fctEditor then
      on.tabKey()
    else
      on.tabKey()
      if theView:getFocus() ~= fctEditor then on.tabKey() end
    end
    reposView()
  end
end

function on.arrowDown()
  if theView then
    on.backtabKey()
    if theView:getFocus() ~= fctEditor then on.backtabKey() end
    reposView()
  end
end

function on.arrowLeft()
  if theView then
    on.tabKey()
    reposView()
  end
end

function on.arrowRight()
  if theView then
    on.backtabKey()
    reposView()
  end
end

function on.charIn(ch)
  if theView then theView:sendStringToFocus(ch) end
end

function on.tabKey()
  if theView then theView:tabForward(); reposView() end
end

function on.backtabKey()
  if theView then theView:tabBackward(); reposView() end
end

function on.enterKey()
  if not fctEditor or not fctEditor.getExpression then return end

  local input = fctEditor:getExpression()
  if not input or input == "" then return end

  local result = ""
  _G.luaCASerror = false
  local success, err = pcall(function()
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
    elseif input:sub(1,6) == "solve(" and input:sub(-1) == ")" then
      local eqn = input:match("solve%((.+)%)")
      if eqn and not eqn:find("=") then
        eqn = eqn .. "=0"
      end
      result = eqn and solve(eqn) or "Invalid solve format"
    elseif input:sub(1,4) == "let " then
      result = define(input)
    elseif input:sub(1,7) == "expand(" and input:sub(-1) == ")" then
        local inner = input:match("expand%((.+)%)")
        result = inner and expand(inner) or "Invalid expand format"
    elseif input:sub(1,5) == "subs(" and input:sub(-1) == ")" then
        local inner, var, val = input:match("subs%(([^,]+),%s*([^,]+),%s*([^%)]+)%)")
        result = (inner and var and val) and subs(inner, var, val) or "Invalid subs format"
    elseif input:sub(1,7) == "factor(" and input:sub(-1) == ")" then
        local inner = input:match("factor%((.+)%)")
        result = inner and factor(inner) or "Invalid factor format"
    elseif input:sub(1,4) == "gcd(" and input:sub(-1) == ")" then
        local a, b = input:match("gcd%(([^,]+),%s*([^%)]+)%)")
        result = (a and b) and gcd(a, b) or "Invalid gcd format"
    elseif input:sub(1,4) == "lcm(" and input:sub(-1) == ")" then
        local a, b = input:match("lcm%(([^,]+),%s*([^%)]+)%)")
        result = (a and b) and lcm(a, b) or "Invalid lcm format"
    elseif input:sub(1,7) == "trigid(" and input:sub(-1) == ")" then
        local inner = input:match("trigid%((.+)%)")
        result = inner and trigid(inner) or "Invalid trigid format"
    elseif input:match("%w+%(.+%)") then
      result = evalFunction(input)
    elseif input:sub(1,9) == "simplify(" and input:sub(-1) == ")" then
      local inner = input:match("simplify%((.+)%)")
      result = inner and simplify(inner) or "Invalid simplify format"
    else
      result = simplify(input)
    end
    if result == "" or not result then
      result = "No result. Internal CAS fallback used."
    end
  end)
  if not success then
    result = "Error: " .. tostring(err)
    _G.luaCASerror = true
  end

  -- Add to history display
  addME(input, result)

  -- Clear the input editor and ready for next input
  if fctEditor and fctEditor.editor then
    fctEditor.editor:setText("")
    fctEditor:fixContent()
  end

  -- Redraw UI
  if platform and platform.window and platform.window.invalidate then
    platform.window:invalidate()
  end

  -- Optionally save last result globally if needed
  res = result
end

function on.returnKey()
  on.enterKey()
end

function on.mouseMove(x, y)
  if theView then theView:onMouseMove(x, y) end
end

function on.mouseDown(x, y)
  if theView then theView:onMouseDown(x, y) end
end

function on.mouseUp(x, y)
  if theView then theView:onMouseUp(x, y) end
end

function initFontGC(gc)
	gc:setFont(font, style, fsize)
end

function getStringHeightGC(text, gc)
	initFontGC(gc)
	return gc:getStringHeight(text)
end

function getStringHeight(text)
	return platform.withGC(getStringHeightGC, text)
end

function getStringWidthGC(text, gc)
	initFontGC(gc)
	return gc:getStringWidth(text)
end

function getStringWidth(text)
	return platform.withGC(getStringWidthGC, text)
end


----------------------------------------------------------------------
--                           History Layout                           --
----------------------------------------------------------------------

-- Find the “partner” editor for a history entry
function getParME(editor)
    for i = 1, #histME2 do
        if histME2[i].editor == editor then
            return histME1[i]
        end
    end
    return nil
end

-- Map a D2Editor instance back to its MathEditor wrapper
function getME(editor)
    if fctEditor and fctEditor.editor == editor then
        return fctEditor
    else
        for i = 1, #histME1 do
            if histME1[i].editor == editor then
                return histME1[i]
            end
        end
        for i = 1, #histME2 do
            if histME2[i].editor == editor then
                return histME2[i]
            end
        end
    end
    return nil
end

-- Get the “index” of a given MathEditor in the history stack
function getMEindex(me)
    if fctEditor and fctEditor.editor == me then
        return 0
    else
        local ti = 0
        for i = #histME1, 1, -1 do
            if histME1[i] == me then
                return ti
            end
            ti = ti + 1
        end
        ti = 0
        for i = #histME2, 1, -1 do
            if histME2[i] == me then
                return ti
            end
            ti = ti + 1
        end
    end
    return 0
end

-- Global offset for history scrolling
ioffset = 0

function reposView()
    local focusedME = theView:getFocus()
    if not focusedME or focusedME == fctEditor then return end

    local index = getMEindex(focusedME)
    local maxIterations = 10 -- prevent infinite loops
    for _ = 1, maxIterations do
        local y = focusedME.y
        local h = focusedME.h
        local y0 = fctEditor.y

        if y < 0 and ioffset < index then
            ioffset = ioffset + 1
            reposME()
        elseif y + h > y0 and ioffset > index then
            ioffset = ioffset - 1
            reposME()
        else
            break
        end
    end
end

-- When a history editor resizes, lay out paired entries side-by-side
function resizeMEpar(editor, w, h)
    local pare = getParME(editor)
    if pare then
        resizeMElim(editor, w, h, pare.w + (pare.dx1 or 0) * 2)
    else
        resizeME(editor, w, h)
    end
end

-- Generic resize for any MathEditor
function resizeME(editor, w, h)
    if not editor then return end
    resizeMElim(editor, w, h, scrWidth / 2)
end

-- Internal workhorse for resizing (limits width, then calls reposME)
function resizeMElim(editor, w, h, lim)
    if not editor then return end
    local met = getME(editor)
    if met then
        met.needw = w
        met.needh = h
        w = math.max(w, 0)
        w = math.min(w, scrWidth - (met.dx1 or 0) * 2)
        if met ~= fctEditor then
            w = math.min(w, (scrWidth - lim) - 2 * (met.dx1 or 0) + 1)
        end
        h = math.max(h, strFullHeight + 8)
        met:resize(w, h)
        reposME()
        theView:invalidate()
    end
    return editor
end

-- “Scroll” and reflow all history MathEditors on screen
function reposME()
    local totalh, beforeh, visih = 0, 0, 0

    -- First, position the input editor at the bottom
    fctEditor.y = scrHeight - fctEditor.h
    theView:repos(fctEditor)

    -- Update scrollbar to fill from input up
    sbv:setVConstraints("justify", scrHeight - fctEditor.y + border)
    theView:repos(sbv)

    local y = fctEditor.y
    local i0 = math.max(#histME1, #histME2)

    for i = i0, 1, -1 do
        local h1, h2 = 0, 0
        if i <= #histME1 then h1 = math.max(h1, histME1[i].h) end
        if i <= #histME2 then h2 = math.max(h2, histME2[i].h) end
        local h = math.max(h1, h2)

        local ry
        if (i0 - i) >= ioffset then
            if y >= 0 then
                if y >= h + border then
                    visih = visih + h + border
                else
                    visih = visih + y
                end
            end
            y = y - h - border
            ry = y
            totalh = totalh + h + border
        else
            ry = scrHeight
            beforeh = beforeh + h + border
            totalh = totalh + h + border
        end

        -- Place the “expression” editor on the left
        if i <= #histME1 then
            histME1[i].y = ry
            theView:repos(histME1[i])
        end
        -- Place its paired “result” editor on the right, vertically aligned
        if i <= #histME2 then
            histME2[i].y = ry + math.max(0, h1 - h2)
            theView:repos(histME2[i])
        end
    end

    if totalh == 0 then
        sbv.pos = 0
        sbv.siz = 100
    else
        sbv.pos = beforeh * 100 / totalh
        sbv.siz = visih * 100 / totalh
    end

    theView:invalidate()
end

function initGUI()
    showEditorsBorders = false
    showHLines = true
    -- local riscas = math.evalStr("iscas()")
    -- if (riscas == "true") then iscas = true end
    local id = math.eval("sslib\\getid()")
    if id then caslib = id end
    scrWidth = platform.window:width()
    scrHeight = platform.window:height()
    if scrWidth > 0 and scrHeight > 0 then
        theView = View(platform.window)

        -- Vertical scroll bar for history
        sbv = VScrollBar(theView, 0, -1, 5, scrHeight + 1)
        sbv:setHConstraints("right", 0)
        theView:add(sbv)

        -- Input editor at bottom (MathEditor)
        fctEditor = MathEditor(theView, 2, border, scrWidth - 4 - sbv.w, 30, "")
        fctEditor:setHConstraints("justify", 1)
        fctEditor:setVConstraints("bottom", 1)
        fctEditor.editor:setSizeChangeListener(function(editor, w, h)
            return resizeME(editor, w, h)
        end)
        theView:add(fctEditor)
        fctEditor.result = res
        fctEditor.editor:setText("")
        fctEditor:fixContent()

        -- First-focus is input editor
        theView:setFocus(fctEditor)
        inited = true
    end

    toolpalette.enableCopy(true)
    toolpalette.enablePaste(true)
end

function resizeGC(gc)
	scrWidth = platform.window:width()
	scrHeight = platform.window:height()
	if not inited then
		initGUI()
	end
	if inited then
		initFontGC(gc)
		strFullHeight = gc:getStringHeight("H")
		strHeight = strFullHeight - 3
		theView:resize()
		reposME()
		theView:invalidate()
	end
end

function on.resize()
	platform.withGC(resizeGC)
end

forcefocus = true

function on.activate()
	forcefocus = true
end

dispinfos = true

function on.paint(gc)
	if not inited then
		initGUI()
		initFontGC(gc)
		strFullHeight = gc:getStringHeight("H")
		strHeight = strFullHeight - 3
	end
	if inited then
		-- Removed display of "Last: ..." result at the top
		local obj = theView:getFocus()
		initFontGC(gc)
		if not obj then theView:setFocus(fctEditor) end
		if (forcefocus) then
			if obj == fctEditor then
				fctEditor.editor:setFocus(true)
				if fctEditor.editor:hasFocus() then forcefocus = false end
			else
				forcefocus = false
			end
		end
		if dispinfos then
			-- Draw status box: green if OK, red if error, always visible top left
			local engineStatus = "LuaCAS Engine: Enabled"
			local statusColor = {0, 127, 0} -- green
			if _G.luaCASerror then
				engineStatus = "LuaCAS Engine: NONE"
				statusColor = {200, 0, 0} -- red
			end
			local boxX, boxY = 8, 8
			local boxPaddingX, boxPaddingY = 10, 3
			local fontToUse = "sansserif"
			local fontStyle = "b"
			local fontSize = 11
			gc:setFont(fontToUse, fontStyle, fontSize)
			local textW = gc:getStringWidth(engineStatus)
			local textH = gc:getStringHeight(engineStatus)
			gc:setColorRGB(statusColor[1], statusColor[2], statusColor[3])
			gc:fillRect(boxX, boxY, textW + boxPaddingX * 2, textH + boxPaddingY * 2)
			gc:setColorRGB(255,255,255)
			gc:drawString(engineStatus, boxX + boxPaddingX, boxY + boxPaddingY, "top")
			-- restore font for rest of UI
			gc:setFont(font, style, fsize)
		end
		-- Output string fallback for "main" view
		if true then -- "main" view block
			local output = fctEditor and fctEditor.result
			-- local outputStr = output or ""
			local outputStr = (output and output ~= "") and output or "(no output)"
			-- If you want to draw the output somewhere, do so here.
			gc:setColorRGB(0, 127, 0)
			gc:drawString(outputStr, 10, scrHeight - 25, "top")
		end
		theView:paint(gc)
	end
end

font = "sansserif"
style = "r"
fsize = 9

scrWidth = 0
scrHeight = 0
inited = false
iscas = false
caslib = "NONE"
delim = " ≟ "
border = 3

strHeight = 0
strFullHeight = 0



-- Initialize empty history tables
histME1 = {}
histME2 = {}


function addME(expr, res)
	mee = MathEditor(theView, border, border, 50, 30, "")
	mee.readOnly = true
	table.insert(histME1, mee)
	mee:setHConstraints("left", border)
	mee.editor:setSizeChangeListener(function(editor, w, h)
		return resizeME(editor, w + 3, h)
	end)
	mee.editor:setExpression("\\0el {" .. expr .. "}", 0)
	mee:fixCursor()
	mee.editor:setReadOnly(true)
	theView:add(mee)

	mer = MathEditor(theView, border, border, 50, 30, "")
    mer.result = true
    mer.readOnly = true
	table.insert(histME2, mer)
	mer:setHConstraints("right", scrWidth - sbv.x + border)
	mer.editor:setSizeChangeListener(function(editor, w, h)
				return resizeMEpar(editor, w + border, h)
	end)
	mer.editor:setExpression("\\0el {" .. res .. "}", 0)
	mer:fixCursor()
	mer.editor:setReadOnly(true)
	theView:add(mer)
	reposME()

-- Any unhandled errors will cause LuaCAS Engine status to go NONE (red)
end