-- Symbolic solver for equations
-- Tries matching known forms before falling back to numerical brute force
-- May or may not give useful answers, depending on how kind your equation is
-- solve.lua
-- Symbolic solver for equations: accepts AST (or string), returns solution(s) as string/AST
-- Works with ast.lua and simplify.lua
 
-- Basic sanity checks for node identity
-- These functions pretend to know what a variable is
-- Utility to check node type
local function isNum(ast)
    return ast and ast.type == "number"
end
local function isVar(ast, v)
    return ast and ast.type == "variable" and (not v or ast.name == v)
end

-- In case you want to mutate stuff without causing mysterious side effects later
-- Deep copy for ASTs
local function deepCopy(obj)
    if type(obj) ~= "table" then return obj end
    local res = {}
    for k, v in pairs(obj) do res[k] = deepCopy(v) end
    return res
end

-- Converts ASTs back into readable strings
-- Emphasis on "readable", not necessarily "good"
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
    if ast.type == "eq" then return astToString(ast.left).." = "..astToString(ast.right) end
    if ast.type == "symbol" then return ast.name end
    return "?"
end

-- Poor man's interpreter for fallback numerical methods
-- Assumes math library knows what it's doing
-- Evaluate simple expressions (needed for numeric fallback)
local function eval(ast, vars)
    vars = vars or {}
    if ast.type == "number" then return ast.value end
    if ast.type == "variable" then return vars[ast.name] or error("Variable "..ast.name.." unassigned") end
    if ast.type == "add" then return eval(ast.left, vars) + eval(ast.right, vars) end
    if ast.type == "sub" then return eval(ast.left, vars) - eval(ast.right, vars) end
    if ast.type == "mul" then return eval(ast.left, vars) * eval(ast.right, vars) end
    if ast.type == "div" then return eval(ast.left, vars) / eval(ast.right, vars) end
    if ast.type == "power" then return eval(ast.left, vars) ^ eval(ast.right, vars) end
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
    error("Eval: unsupported node type "..tostring(ast.type))
end

-- Attempts to coerce expressions into polynomials
-- Good luck if you feed it anything more exotic
-- Extract coefficients for ax^n + bx + c + ... (monomials in var)
local function polyCoeffs(ast, var, maxdeg)
    -- Returns: { [0]=c, [1]=b, [2]=a, ... }
    local coeffs = {}
    local function walk(node)
        if node.type == "add" or node.type == "sub" then
            local l = walk(node.left)
            local r = walk(node.right)
            for k,v in pairs(l) do coeffs[k] = (coeffs[k] or 0) + v end
            for k,v in pairs(r) do
                coeffs[k] = (coeffs[k] or 0) + (node.type=="add" and v or -v)
            end
            return coeffs
        elseif node.type == "mul" then
            if isNum(node.left) and isVar(node.right, var) then
                coeffs[1] = (coeffs[1] or 0) + node.left.value
            elseif isNum(node.right) and isVar(node.left, var) then
                coeffs[1] = (coeffs[1] or 0) + node.right.value
            elseif isNum(node.left) and node.right.type == "power"
                    and isVar(node.right.left, var)
                    and isNum(node.right.right) then
                coeffs[node.right.right.value] = (coeffs[node.right.right.value] or 0) + node.left.value
            end
        elseif node.type == "power" and isVar(node.left, var) and isNum(node.right) then
            coeffs[node.right.value] = (coeffs[node.right.value] or 0) + 1
        elseif isVar(node, var) then
            coeffs[1] = (coeffs[1] or 0) + 1
        elseif isNum(node) then
            coeffs[0] = (coeffs[0] or 0) + node.value
        end
        return coeffs
    end
    walk(ast)
    return coeffs
end

-- These are where the "symbolic" magic happens
-- Spoiler: it's mostly matching and algebra trivia
-- Pattern-matcher for common forms
local function matchLinearEq(eq, var)
    -- ax + b = 0
    if eq.type == "eq" then
        local l = eq.left
        local r = eq.right
        local coeffs = polyCoeffs({type="sub", left=l, right=r}, var)
        local a = coeffs[1] or 0
        local b = coeffs[0] or 0
        if a ~= 0 then
            return -b/a
        end
    end
    return nil
end

local function matchQuadraticEq(eq, var)
    -- ax^2 + bx + c = 0
    if eq.type == "eq" then
        local l = eq.left
        local r = eq.right
        local coeffs = polyCoeffs({type="sub", left=l, right=r}, var)
        local a = coeffs[2] or 0
        local b = coeffs[1] or 0
        local c = coeffs[0] or 0
        if a ~= 0 then
            local D = b^2 - 4*a*c
            if D < 0 then return nil end
            local sqrtD = math.sqrt(D)
            return { (-b+sqrtD)/(2*a), (-b-sqrtD)/(2*a) }
        end
    end
    return nil
end

-- Cardano's method for cubics: ax^3+bx^2+cx+d=0
local function matchCubicEq(eq, var)
    if eq.type == "eq" then
        local l = eq.left
        local r = eq.right
        local coeffs = polyCoeffs({type="sub", left=l, right=r}, var)
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

-- Solve simple trig equations, e.g. sin(x)=0, cos(x)=1, tan(x)=a
local function matchTrigEq(eq, var)
    if eq.type == "eq" then
        local l, r = eq.left, eq.right
        if l.type == "func" and isVar(l.args[1], var) then
            local fname = l.name
            if fname == "sin" then
                -- sin(x)=a → x=arcsin(a)+2πk, π-arcsin(a)+2πk
                if isNum(r) and r.value >= -1 and r.value <= 1 then
                    return {
                        { type = "add", left = { type = "func", name = "arcsin", args = { r } }, right = { type = "symbol", name = "2πk" } },
                        { type = "add", left = { type = "sub", left = { type = "symbol", name = "π" }, right = { type = "func", name = "arcsin", args = { r } } }, right = { type = "symbol", name = "2πk" } }
                    }
                end
            elseif fname == "cos" then
                -- cos(x)=a → x=arccos(a)+2πk, -arccos(a)+2πk
                if isNum(r) and r.value >= -1 and r.value <= 1 then
                    return {
                        { type = "add", left = { type = "func", name = "arccos", args = { r } }, right = { type = "symbol", name = "2πk" } },
                        { type = "add", left = { type = "neg", value = { type = "func", name = "arccos", args = { r } } }, right = { type = "symbol", name = "2πk" } }
                    }
                end
            elseif fname == "tan" then
                -- tan(x)=a → x=arctan(a)+πk
                if isNum(r) then
                    return {
                        { type = "add", left = { type = "func", name = "arctan", args = { r } }, right = { type = "symbol", name = "πk" } }
                    }
                end
            end
        end
    end
    return nil
end

-- Solve exponential/logarithmic equations
local function matchExpLogEq(eq, var)
    if eq.type == "eq" then
        local l, r = eq.left, eq.right
        -- exp(x) = a → x=ln(a)
        if l.type == "func" and l.name == "exp" and isVar(l.args[1], var) and isNum(r) and r.value > 0 then
            return {
                { type = "eq", left = { type = "variable", name = var }, right = { type = "func", name = "ln", args = { r } } }
            }
        end
        -- ln(x) = a → x=exp(a)
        if l.type == "func" and l.name == "ln" and isVar(l.args[1], var) and isNum(r) then
            return {
                { type = "eq", left = { type = "variable", name = var }, right = { type = "func", name = "exp", args = { r } } }
            }
        end
        -- a^x = b → x=ln(b)/ln(a)
        if l.type == "power" and isNum(l.left) and isVar(l.right, var) and isNum(r) and l.left.value > 0 and r.value > 0 then
            return {
                { type = "eq", left = { type = "variable", name = var }, right = { type = "div", left = { type = "func", name = "ln", args = { r } }, right = { type = "func", name = "ln", args = { l.left } } } }
            }
        end
    end
    return nil
end

-- When all else fails, just guess a number and hope it converges
-- Symbolic failure, numerical optimism
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

-- Main interface: give it an equation, get some form of answer (maybe)
-- Includes desperate variable guessing and symbolic simplification
-- Top-level solve function (input: AST or string, variable name optional)
function solve(ast, var)
    -- Convert string input to AST if needed
    if type(ast) == "string" then
        if not buildAST then error("buildAST() not defined") end
        ast = buildAST(tokenize(ast))
    end
    -- Extract equation: make sure it's type="eq"
    if ast.type ~= "eq" then
        -- Try to treat as expr=0
        ast = { type="eq", left=ast, right={type="number", value=0} }
    end
    var = var or (function()
        -- try to guess variable
        local function findVar(node)
            if node.type == "variable" then return node.name end
            for _,k in ipairs{"left","right","value","args"} do
                if node[k] then
                    if type(node[k]) == "table" then
                        local res = findVar(node[k])
                        if res then return res end
                    elseif type(node[k]) == "table" then
                        for _,v in ipairs(node[k]) do
                            local res = findVar(v)
                            if res then return res end
                        end
                    end
                end
            end
            return nil
        end
        return findVar(ast.left) or findVar(ast.right) or "x"
    end)()

    -- Canonicalize and simplify left - right
    local diff = simplify.simplify({ type = "sub", left = ast.left, right = ast.right })
    ast = { type = "eq", left = diff, right = { type = "number", value = 0 } }

    -- Try all known matchers
    local ans = matchLinearEq(ast, var)
    if ans then return var.." = "..tostring(ans) end

    ans = matchQuadraticEq(ast, var)
    if ans then
        return var.."₁ = "..tostring(ans[1])..", "..var.."₂ = "..tostring(ans[2])
    end

    ans = matchCubicEq(ast, var)
    if ans then
        local outs = {}
        for i,v in ipairs(ans) do outs[#outs+1] = var..tostring(i).." = "..tostring(v) end
        return table.concat(outs, ", ")
    end

    ans = matchTrigEq(ast, var)
    if ans then
        if type(ans[1]) == "table" then
            local outs = {}
            for _,a in ipairs(ans) do table.insert(outs, astToString(a)) end
            return table.concat(outs, ", ")
        else
            return table.concat(ans, ", ")
        end
    end

    ans = matchExpLogEq(ast, var)
    if ans then
        if type(ans[1]) == "table" then
            local outs = {}
            for _,a in ipairs(ans) do table.insert(outs, astToString(a)) end
            return table.concat(outs, ", ")
        else
            return table.concat(ans, ", ")
        end
    end

    -- Fallback: numerical
    local xnum = newtonSolve(ast, var)
    if xnum then
        return var.." ≈ "..tostring(xnum)
    end

    return "No solution found"
end

_G.solve = solve