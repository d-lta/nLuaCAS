-- TODO: Make sure all equation types listed above are *actually* supported in the code below. If not, add matcher and solver logic.
-- Supported equation formats by the symbolic solver:
--   * Linear:       ax + b = 0,   ax = b,   x + b = 0,   x = b
--   * Quadratic:    ax^2 + bx + c = 0,   ax^2 + bx = c,   x^2 + bx + c = d
--   * Cubic:        ax^3 + bx^2 + cx + d = 0, etc.
--   * Trigonometric: sin(x) = a, cos(x) = a, tan(x) = a
--   * Exponential:   a^x = b, exp(x) = a
--   * Logarithmic:   ln(x) = a
--   * General form:  lhs = rhs, will be handled if reducible to above forms
--   * Fallback:      Newton's method for numeric answers if not symbolically solvable

-- SUPPORTED EQUATION FORMATS
-- This solver handles the following equation types:
-- 1. Linear equations:       ax + b = c       (x = ...)
-- 2. Quadratic equations:    ax^2 + bx + c = d  (x = ...)
-- 3. Cubic equations:        ax^3 + bx^2 + cx + d = e
-- 4. Trigonometric:          sin(x) = a, cos(x) = a, tan(x) = a
-- 5. Exponential/log:        exp(x) = a, ln(x) = b, a^x = b
-- 6. Fallback: symbolic rearrangement, Newton's numeric solve
--
-- If you want to add more patterns (e.g., systems, piecewise, abs, etc), add more matcher functions.

-- solve.lua
-- Corrected Symbolic solver for equations: accepts AST (or string), returns solution(s) as string/AST

local ast = rawget(_G, "ast") or require("ast")
local errors = _G.errors
 
-- Basic sanity checks for node identity
local function isNum(ast)
    return ast and ast.type == "number"
end
local function isVar(ast, v)
    return ast and ast.type == "variable" and (not v or ast.name == v)
end

-- Ensure parser and simplify are loaded
local parser = rawget(_G, "parser") or require("parser")
local simplify = rawget(_G, "simplify") or require("simplify")

-- Deep copy for ASTs
local function deepCopy(obj)
    if type(obj) ~= "table" then return obj end
    local res = {}
    for k, v in pairs(obj) do res[k] = deepCopy(v) end
    return res
end

-- Simple AST pretty printer
local function astToString(ast)
    if not ast then return "?" end
    if ast.type == "number" then return tostring(ast.value) end
    if ast.type == "variable" then return ast.name end
    if ast.type == "add" then return "("..astToString(ast.left).."+"..astToString(ast.right)..")" end
    if ast.type == "sub" then return "("..astToString(ast.left).."-"..astToString(ast.right)..")" end
    if ast.type == "mul" then return astToString(ast.left).."*"..astToString(ast.right) end
    if ast.type == "div" then return astToString(ast.left).."/"..astToString(ast.right) end
    if ast.type == "power" then return astToString(ast.left).."^"..astToString(ast.right) end
    if ast.type == "neg" then return "-("..astToString(ast.value)..")" end
    if ast.type == "func" then
        local argstrs = {}
        for _, arg in ipairs(ast.args or {}) do
            table.insert(argstrs, astToString(arg))
        end
        return ast.name .. "(" .. table.concat(argstrs, ",") .. ")"
    end
    if ast.type == "matrix" then
      local row_strs = {}
      for _, row in ipairs(ast.rows) do
        local col_strs = {}
        for _, elem in ipairs(row) do
          table.insert(col_strs, astToString(elem))
        end
        table.insert(row_strs, "[" .. table.concat(col_strs, ", ") .. "]")
      end
      return "[" .. table.concat(row_strs, ", ") .. "]"
    end
    if ast.type == "eq" or ast.type == "equation" then return astToString(ast.left).." = "..astToString(ast.right) end
    if ast.type == "symbol" then return ast.name end
    if ast.type == "pm" then
        return "(" .. astToString(ast.left) .. " ± " .. astToString(ast.right) .. ")"
    end
    return "?"
end

-- Evaluate simple expressions (needed for numeric fallback)
local function eval(ast, vars)
    vars = vars or {}
    if ast.type == "number" then return ast.value end
    if ast.type == "variable" then return vars[ast.name] or error("Variable "..ast.name.." unassigned") end
    if ast.type == "add" then return eval(ast.left, vars) + eval(ast.right, vars) end
    if ast.type == "sub" then return eval(ast.left, vars) - eval(ast.right, vars) end
    if ast.type == "mul" then return eval(ast.left, vars) * eval(ast.right, vars) end
    if ast.type == "div" then return eval(ast.left, vars) / eval(ast.right, vars) end
    if ast.type == "power" or ast.type == "pow" then
        return eval(ast.left, vars) ^ eval(ast.right, vars)
    end
    if ast.type == "neg" then return -eval(ast.value, vars) end
    -- basic functions
    if ast.type == "func" then
        local fn = math[ast.name]
        if fn then
            local args = {}
            for _, arg in ipairs(ast.args) do
                table.insert(args, eval(arg, vars))
            end
            return fn(table.unpack(args))
        end
    end
    -- Handle custom "equation" node type: evaluate as lhs - rhs
    if ast.type == "equation" then
        return eval(ast.left, vars) - eval(ast.right, vars)
    end
    error("Eval: unsupported node type "..tostring(ast.type))
end

-- CORRECTED polynomial coefficient extraction
local function polyCoeffs(ast, var, maxdeg)
    local coeffs = {}

    print("[polyCoeffs] input AST:", astToString(ast))

    -- Force canonical expansion to help coefficient extraction
    if simplify and simplify.simplify then
        ast = simplify.simplify(ast)
    end

    local function walk(node, sign)
        print("[polyCoeffs][walk] node type:", node.type, "node:", astToString(node))
        sign = sign or 1

        if node.type == "add" then
            local children = node.args or { node.left, node.right }
            for _, child in ipairs(children) do
                walk(child, sign)
            end
        elseif node.type == "sub" then
            local children = node.args or { node.left, node.right }
            walk(children[1], sign)
            for i = 2, #children do
                walk(children[i], -sign)
            end
        elseif node.type == "mul" then
            local coeff = sign
            local var_power = 0

            local children = node.args or { node.left, node.right }
            for _, child in ipairs(children) do
                if isNum(child) then
                    coeff = coeff * child.value
                elseif isVar(child, var) then
                    var_power = var_power + 1
                elseif (child.type == "power" or child.type == "pow") and isVar(child.left or child.base, var) and isNum(child.right or child.exp) then
                    var_power = var_power + (child.right or child.exp).value
                else
                    -- unsupported term, not a polynomial
                    return
                end
            end

            coeffs[var_power] = (coeffs[var_power] or 0) + coeff
        elseif (node.type == "power" or node.type == "pow") and isVar(node.left or node.base, var) and isNum(node.right or node.exp) then
            coeffs[(node.right or node.exp).value] = (coeffs[(node.right or node.exp).value] or 0) + sign
        elseif isVar(node, var) then
            coeffs[1] = (coeffs[1] or 0) + sign
        elseif isNum(node) then
            coeffs[0] = (coeffs[0] or 0) + (sign * node.value)
        end
    end

    walk(ast)
    print("[polyCoeffs] coeffs table:", coeffs)
    for deg, coeff in pairs(coeffs) do
      print("  degree", deg, "=>", coeff)
    end
    return coeffs
end

-- Linear equation matcher: supports ax + b = c, ax = b, x + b = c, x = b
local function matchLinearEq(eq, var)
    -- Accept forms: ax + b = c, ax = b, x + b = c, x = b
    if eq.type ~= "equation" then return nil end
    local l, r = eq.left, eq.right
    -- If right side is not zero, normalize: (l - r) = 0
    local norm = { type="sub", left=l, right=r }
    local coeffs = polyCoeffs(norm, var)
    if not coeffs then return nil end
    local a = coeffs[1] or 0
    local b = coeffs[0] or 0
    if a == 0 then return nil end
    -- Solution is x = -b/a
    local solution_value = -b / a
    return ast.number(solution_value)
end

local function matchQuadraticEq(eq, var)
    -- Accept forms: ax^2 + bx + c = d
    if eq.type ~= "equation" then return nil end
    local l, r = eq.left, eq.right
    -- Normalize by subtracting right from left: (l - r) = 0
    local norm = { type = "sub", left = l, right = r }
    local coeffs = polyCoeffs(norm, var)
    if not coeffs then return nil end
    local a = coeffs[2] or 0
    local b = coeffs[1] or 0
    local c = coeffs[0] or 0
    if a == 0 then return nil end

    local num_node = function(v) return ast.number(v) end
    -- Build AST nodes for a, b, c
    local a_node = num_node(a)
    local b_node = num_node(b)
    local c_node = num_node(c)
    local four_node = num_node(4)
    local two_node  = num_node(2)

    -- Compute discriminant: D = b^2 - 4*a*c
    local b_sq    = ast.pow(b_node, num_node(2))
    local four_ac = ast.mul({ four_node, a_node, c_node })
    local disc    = ast.sub(b_sq, four_ac)

    -- Build sqrt(D)
    local sqrt_disc = ast.func("sqrt", { disc })
    -- Compute -b
    local minus_b = ast.neg(b_node)
    -- Compute denominator 2a
    local denom = ast.mul({ two_node, a_node })

    -- Plus and minus solutions:
    local plus_case  = ast.div(ast.add({ minus_b,        sqrt_disc }), denom)
    local minus_case = ast.div(ast.sub(minus_b,        sqrt_disc ), denom)

    -- Construct ± in one node:
    local root_pm = ast.div(
        ast.add({ minus_b, { type = "pm", left = sqrt_disc, right = ast.number(0) } }),
        denom
    )

    return { plus_case, minus_case, root_pm }
end

-- Cardano's method for cubics: ax^3+bx^2+cx+d=e
local function matchCubicEq(eq, var)
    if eq.type == "equation" then
        local l = eq.left
        local r = eq.right
        -- Normalize by subtracting right from left
        local coeffs = polyCoeffs({type="sub", left=l, right=r}, var)
        if not coeffs then return nil end
        local a = coeffs[3] or 0
        local b = coeffs[2] or 0
        local c = coeffs[1] or 0
        local d = coeffs[0] or 0
        if a ~= 0 then
            -- Depressed cubic: t^3 + pt + q = 0
            local p = (3*a*c - b^2)/(3*a^2)
            local q = (2*b^3 - 9*a*b*c + 27*a^2*d)/(27*a^3)
            local roots = {}
            local delta = (q^2)/4 + (p^3)/27
            if delta > 0 then
                local sqrt_delta = math.sqrt(delta)
                local u = ((-q)/2 + sqrt_delta)^(1/3)
                local v = ((-q)/2 - sqrt_delta)^(1/3)
                local root = u + v - b/(3*a)
                table.insert(roots, root)
                return roots
            elseif delta == 0 then
                local u = (-q/2)^(1/3)
                local r1 = 2*u - b/(3*a)
                local r2 = -u - b/(3*a)
                return { r1, r2 }
            else
                -- Three real roots
                local r = math.sqrt(-p^3/27)
                local phi = math.acos(-q/(2*r))
                local t = 2*math.sqrt(-p/3)
                for k=0,2 do
                    local angle = (phi+2*math.pi*k)/3
                    local root = t*math.cos(angle) - b/(3*a)
                    table.insert(roots, root)
                end
                return roots
            end
        end
    end
    return nil
end
-- Match simple isolated variable equation: x = b
local function matchSimpleIsolatedVarEq(eq, var)
    -- Matches x = b (variable alone on left, constant or expr on right)
    if eq.type ~= "equation" then return nil end
    if isVar(eq.left, var) and not contains_var(eq.right, var) then
        return ast.eq(ast.symbol(var), copy(eq.right))
    end
    return nil
end

-- Solve simple trig equations, e.g. sin(x)=0, cos(x)=1, tan(x)=a
local function matchTrigEq(eq, var)
    if eq.type == "equation" then
        local l, r = eq.left, eq.right
        if l.type == "func" and isVar(l.args[1], var) then
            local fname = l.name
            if fname == "sin" then
                -- sin(x)=a → x=arcsin(a)+2πk, π-arcsin(a)+2πk
                if isNum(r) and r.value >= -1 and r.value <= 1 then
                    return {
                        ast.eq(ast.symbol(var), ast.add({ ast.func("arcsin", { r }), ast.symbol("2πk") })),
                        ast.eq(ast.symbol(var), ast.add({ ast.sub(ast.symbol("π"), ast.func("arcsin", { r })), ast.symbol("2πk") }))
                    }
                end
            elseif fname == "cos" then
                -- cos(x)=a → x=arccos(a)+2πk, -arccos(a)+2πk
                if isNum(r) and r.value >= -1 and r.value <= 1 then
                    return {
                        ast.eq(ast.symbol(var), ast.add({ ast.func("arccos", { r }), ast.symbol("2πk") })),
                        ast.eq(ast.symbol(var), ast.add({ ast.neg(ast.func("arccos", { r })), ast.symbol("2πk") }))
                    }
                end
            elseif fname == "tan" then
                -- tan(x)=a → x=arctan(a)+πk
                if isNum(r) then
                    return {
                        ast.eq(ast.symbol(var), ast.add({ ast.func("arctan", { r }), ast.symbol("πk") }))
                    }
                end
            end
        end
    end
    return nil
end

-- Solve exponential/logarithmic equations
local function matchExpLogEq(eq, var)
    if eq.type == "equation" then
        local l, r = eq.left, eq.right
        -- exp(x) = a → x=ln(a)
        if l.type == "func" and l.name == "exp" and isVar(l.args[1], var) and isNum(r) and r.value > 0 then
            return {
                ast.eq(ast.symbol(var), ast.func("ln", { r }))
            }
        end
        -- ln(x) = a → x=exp(a)
        if l.type == "func" and l.name == "ln" and isVar(l.args[1], var) and isNum(r) then
            return {
                ast.eq(ast.symbol(var), ast.func("exp", { r }))
            }
        end
        -- a^x = b → x=ln(b)/ln(a)
        if l.type == "power" and isNum(l.left) and isVar(l.right, var) and isNum(r) and l.left.value > 0 and r.value > 0 then
            return {
                ast.eq(ast.symbol(var), ast.div(ast.func("ln", { r }), ast.func("ln", { l.left })))
            }
        end
    end
    return nil
end

-- Fallback: Newton's method (symbolic evaluation if possible)
local function newtonSolve(eq, var, guess, maxiter)
    maxiter = maxiter or 8
    local x = guess or 1
    for i=1,maxiter do
        -- Numerical derivative by h
        local h = 1e-7
        local env = {}; env[var]=x
        local f = eval({type="sub", left=eq.left, right=eq.right}, env)
        local f1 = eval({type="sub", left=eq.left, right=eq.right}, (function() local e = {}; for k,v in pairs(env) do e[k]=v end; e[var]=x+h; return e end)())
        local dfdx = (f1-f)/h
        if math.abs(dfdx) < 1e-10 then break end
        local xnew = x - f/dfdx
        if math.abs(xnew-x) < 1e-10 then return xnew end
        x = xnew
    end
    return x
end

-- Utility: checks if an AST node contains a variable
local function contains_var(node, var)
  if type(node) ~= "table" then return false end
  if node.type == "variable" and node.name == var then return true end
  for k,v in pairs(node) do
    if contains_var(v, var) then return true end
  end
  return false
end

-- Helper to check if an AST node is a constant (number)
local function is_const(node)
  return node and node.type == "number"
end

-- Helper for variable test (for base case, mirror old code)
local function is_var(node)
  return node and node.type == "variable"
end

-- Helper to copy AST nodes (deep copy)
local function copy(node)
  if type(node) ~= "table" then return node end
  local res = {}
  for k,v in pairs(node) do res[k] = copy(v) end
  return res
end

local function solveAST(eq, var)
  -- Only handle equations
  if not eq or eq.type ~= "equation" then
    return { type = "unhandled_node", reason = "Not an equation", original = eq }
  end

  local lhs = eq.left
  local rhs = eq.right

  -- If variable only on one side, swap if needed
  if contains_var(rhs, var) and not contains_var(lhs, var) then
    lhs, rhs = rhs, lhs
  end

  -- Base case: variable alone
  if is_var(lhs) and lhs.name == var then
    -- Ensure rhs is a valid AST node
    local _rhs = rhs
    if type(_rhs) ~= "table" then
        _rhs = ast.number(_rhs)
    end
    return ast.eq(ast.symbol(var), copy(_rhs))
  end

  -- Directly handle simple isolated variable: x = b
  if is_var(lhs, var) and not contains_var(rhs, var) then
    return ast.eq(ast.symbol(var), copy(rhs))
  end

  -- If this is a polynomial equation, extract degree and use appropriate matcher
  local diff = simplify.simplify(ast.sub(lhs, rhs))
  local coeffs = polyCoeffs(diff, var)
  local highest_degree = 0
  if coeffs then
    for deg, _ in pairs(coeffs) do
      if deg > highest_degree then highest_degree = deg end
    end
    if highest_degree == 1 then
      local ans_lin = matchLinearEq(ast.eq(lhs, rhs), var)
      if ans_lin then
        return ast.eq(ast.symbol(var), ans_lin)
      end
    elseif highest_degree == 2 then
      local ans_quad = matchQuadraticEq(ast.eq(lhs, rhs), var)
      if ans_quad then
        -- Just return ± form for now
        local eq_pm = ans_quad[3] and ast.eq(ast.symbol(var), ans_quad[3])
        return eq_pm or ast.eq(ast.symbol(var), ans_quad[1])
      end
    elseif highest_degree == 3 then
      local ans_cubic = matchCubicEq(ast.eq(lhs, rhs), var)
      if ans_cubic then
        -- Return first root as symbolic solution (optionally, all)
        return ast.eq(ast.symbol(var), ast.number(ans_cubic[1]))
      end
    end
  end

  -- Try trig equations
  local trig = matchTrigEq(ast.eq(lhs, rhs), var)
  if trig then
    return trig[1]
  end

  -- Try exp/log equations
  local exp_log = matchExpLogEq(ast.eq(lhs, rhs), var)
  if exp_log then
    return exp_log[1]
  end

  -- If still not solved, try the classic pattern matching and structure-based recursion as before

  -- Linear: x + a = b  or x - a = b
  if lhs.type == "add" then
    for i, arg in ipairs(lhs.args) do
      if contains_var(arg, var) then
        -- x + a = b  --> x = b - a
        local others = {}
        for j, arg2 in ipairs(lhs.args) do if i ~= j then table.insert(others, arg2) end end
        local subtrahend = #others == 1 and others[1] or ast.add(table.unpack(others))
        local next_eq = ast.eq(arg, ast.sub(rhs, subtrahend))
        next_eq = simplify.simplify(next_eq)
        return solveAST(next_eq, var)
      end
    end
  elseif lhs.type == "sub" then
    if contains_var(lhs.left, var) and not contains_var(lhs.right, var) then
      -- x - a = b --> x = b + a
      local next_eq = ast.eq(lhs.left, ast.add(rhs, lhs.right))
      next_eq = simplify.simplify(next_eq)
      return solveAST(next_eq, var)
    elseif contains_var(lhs.right, var) and not contains_var(lhs.left, var) then
      -- a - x = b --> x = a - b
      local next_eq = ast.eq(lhs.right, ast.sub(lhs.left, rhs))
      next_eq = simplify.simplify(next_eq)
      return solveAST(next_eq, var)
    end
  elseif lhs.type == "mul" then
    for i, arg in ipairs(lhs.args) do
      if contains_var(arg, var) then
        -- x * a = b --> x = b / a
        local others = {}
        for j, arg2 in ipairs(lhs.args) do if i ~= j then table.insert(others, arg2) end end
        local divisor = #others == 1 and others[1] or ast.mul(table.unpack(others))
        local next_eq = ast.eq(arg, ast.div(rhs, divisor))
        next_eq = simplify.simplify(next_eq)
        return solveAST(next_eq, var)
      end
    end
  elseif lhs.type == "div" then
    if contains_var(lhs.left, var) and not contains_var(lhs.right, var) then
      -- x / a = b --> x = b * a
      local next_eq = ast.eq(lhs.left, ast.mul(rhs, lhs.right))
      next_eq = simplify.simplify(next_eq)
      return solveAST(next_eq, var)
    elseif contains_var(lhs.right, var) and not contains_var(lhs.left, var) then
      -- a / x = b --> x = a / b
      local next_eq = ast.eq(lhs.right, ast.div(lhs.left, rhs))
      next_eq = simplify.simplify(next_eq)
      return solveAST(next_eq, var)
    end
  elseif lhs.type == "pow" or lhs.type == "power" then
    if contains_var(lhs.left or lhs.base, var) and is_const(lhs.right or lhs.exp) then
      local base = lhs.left or lhs.base
      local exp = lhs.right or lhs.exp
      -- x^n = b --> x = b^(1/n)
      local next_eq = ast.eq(base, ast.pow(rhs, ast.div(ast.number(1), exp)))
      next_eq = simplify.simplify(next_eq)
      return solveAST(next_eq, var)
    elseif is_const(lhs.left or lhs.base) and contains_var(lhs.right or lhs.exp, var) then
      local base = lhs.left or lhs.base
      local exp = lhs.right or lhs.exp
      -- a^x = b --> x = ln(b) / ln(a)
      local next_eq = ast.eq(exp, ast.div(ast.func("ln", { rhs }), ast.func("ln", { base })))
      next_eq = simplify.simplify(next_eq)
      return solveAST(next_eq, var)
    end
  end

  -- fallback: unhandled → mark as unsolved equation
  return ast.eq(ast.symbol(var), { type = "unsolved", reason = "unhandled equation structure", original = eq })
end

-- Main solve function
function solve(input_expr, var)
    local parser = rawget(_G, "parser") or require("parser")
    local ast_mod = rawget(_G, "ast") or require("ast")
    local simplify = rawget(_G, "simplify") or require("simplify")

    local expr = input_expr
    if type(expr) == "string" then
        -- Insert '*' between a digit and a letter or digit and '('
        local s = expr
        s = s:gsub("(%d)(%a)", "%1*%2")
        s = s:gsub("(%d)(%()", "%1*%2")
        expr = parser.parse(s)
    end
    if not expr then
        error(errors.invalid("solve", "parse failed, got nil AST"))
    end

    var = var or (function()
        -- try to guess variable
        local function findVar(node)
            if not node or type(node) ~= "table" then return nil end
            if node.type == "variable" then return node.name end
            for _, k in ipairs { "left", "right", "value", "args" } do
                local child = node[k]
                if child then
                    if type(child) == "table" and not child[1] then
                        local res = findVar(child)
                        if res then return res end
                    elseif type(child) == "table" then
                        for _, v in ipairs(child) do
                            local res = findVar(v)
                            if res then return res end
                        end
                    end
                end
            end
            return nil
        end
        return findVar(expr.left) or findVar(expr.right) or "x"
    end)()

    -- Canonicalize equation as eq-node (lhs = rhs), or expr = 0
    if expr.type == "equation" then
        expr = ast_mod.eq(expr.left, expr.right)
    elseif expr.type ~= "equation" then
        expr = ast_mod.eq(expr, ast_mod.number(0))
    end

    -- Always simplify first
    expr = simplify.simplify(expr)

    -- Try new symbolic solver
    local result = solveAST(expr, var)
    -- If it returns unhandled_node, fall back to original matchers
    if result and result.type ~= "unhandled_node" then
        -- Further simplify the result before converting to string
        result = simplify.simplify(result)
        return astToString(result)
    end

    -- Try all known matchers
    local diff = simplify.simplify(ast_mod.sub(expr.left, expr.right))
    local fallback_eq = ast_mod.eq(diff, ast_mod.number(0))

    -- Try simple isolated variable matcher first (x = b)
    local ans_simple = matchSimpleIsolatedVarEq(expr, var)
    if not ans_simple then
        ans_simple = matchSimpleIsolatedVarEq(fallback_eq, var)
    end
    if ans_simple then
        local simplified_eq = simplify.simplify(ans_simple)
        return astToString(simplified_eq)
    end

    local ans_lin = matchLinearEq(fallback_eq, var)
    if ans_lin then
        -- Create proper equation AST
        local rhs
        if type(ans_lin) ~= "table" then
            rhs = ast_mod.number(ans_lin)
        else
            rhs = ans_lin
        end
        local eq_ast = ast_mod.eq(ast_mod.symbol(var), rhs)
        local simplified_eq = simplify.simplify(eq_ast)
        return astToString(simplified_eq)
    end

    local ans_quad = matchQuadraticEq(fallback_eq, var)
    if ans_quad then
        -- Try to evaluate both roots numerically. If not possible (i.e., discriminant negative), say no real roots.
        local function tryEvalRoot(root)
            local ok, val = pcall(function() return eval(root) end)
            if ok and type(val) == "number" and val == val and math.abs(val) ~= math.huge then
                return val
            end
            return nil
        end
        local v1 = tryEvalRoot(ans_quad[1])
        local v2 = tryEvalRoot(ans_quad[2])
        if v1 and v2 then
            return var .. " = " .. tostring(v1) .. ", " .. tostring(v2)
        else
            return "No real roots"
        end
    end

    local ans = matchCubicEq(fallback_eq, var)
    if ans then
        local outs = {}
        for i,v in ipairs(ans) do
            local eq_ast = ast_mod.eq(ast_mod.symbol(var), ast_mod.number(v))
            local simp = simplify.simplify(eq_ast)
            table.insert(outs, astToString(simp))
        end
        -- If all roots are equal, show just one, else all
        local all_equal = true
        if #outs > 1 then
            for i=2,#outs do
                if outs[i] ~= outs[1] then all_equal = false break end
            end
        end
        if all_equal then
            return outs[1]
        else
            return table.concat(outs, ", ")
        end
    end

    ans = matchTrigEq(fallback_eq, var)
    if ans then
        if type(ans[1]) == "table" and ans[1].type == "equation" then
            local outs = {}
            for _,a in ipairs(ans) do table.insert(outs, astToString(a)) end
            return table.concat(outs, ", ")
        else
            return table.concat(ans, ", ")
        end
    end

    ans = matchExpLogEq(fallback_eq, var)
    if ans then
        if type(ans[1]) == "table" and ans[1].type == "equation" then
            local outs = {}
            for _,a in ipairs(ans) do table.insert(outs, astToString(a)) end
            return table.concat(outs, ", ")
        else
            return table.concat(ans, ", ")
        end
    end

    -- Fallback: numerical
    local xnum = newtonSolve(fallback_eq, var)
    if xnum then
        return var.." ≈ "..tostring(xnum)
    end

    return "No solution found"
end

-- Public interface: string or AST in, solution AST or unhandled node out
local function solve_symbolic(expr, var)
  local parser = rawget(_G, "parser") or require("parser")
  local simplify = rawget(_G, "simplify") or require("simplify")
  if type(expr) == "string" then expr = parser.parse(expr) end
  if not expr then error(errors.invalid("solve", "symbolic parse failed: " .. tostring(expr))) end
  var = var or "x"
  -- handle input like "lhs = rhs" or plain expr = 0
  if expr.type == "equation" then
    expr = ast.eq(expr.left, expr.right)
  elseif expr.type ~= "equation" then
    expr = ast.eq(expr, ast.number(0))
  end
  expr = simplify.simplify(expr)
  local result = solveAST(expr, var)
  return result
end

-- Export functions
_G.solve = solve
_G.solveAST = solveAST
_G.solve_symbolic = solve_symbolic
_G.polyCoeffs = polyCoeffs
_G.matchLinearEq = matchLinearEq
_G.matchQuadraticEq = matchQuadraticEq
_G.matchCubicEq = matchCubicEq
_G.matchSimpleIsolatedVarEq = matchSimpleIsolatedVarEq
_G.astToString = astToString

--[[
Extending to new equation types:
To add support for a new equation type, write a matcher function (see matchLinearEq, matchQuadraticEq, etc.),
normalize the equation (subtract right from left if needed), extract coefficients or pattern-match as required,
and add your matcher to the main solve function before the fallback.
]]