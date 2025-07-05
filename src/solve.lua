local function safe_sqrt(x)
    if type(x) == "table" then
        -- x is complex: sqrt(x) = sqrt(r) * exp(i * theta/2)
        local a, b = x.re or 0, x.im or 0
        local r = math.sqrt(a^2 + b^2)
        local theta = math.atan2(b, a)
        local sqrt_r = math.sqrt(r)
        return {
            re = sqrt_r * math.cos(theta / 2),
            im = sqrt_r * math.sin(theta / 2)
        }
    elseif x >= 0 then
        return math.sqrt(x)
    else
        return { re = 0, im = math.sqrt(-x) }
    end
end

-- solve.lua - Complete Fixed Edition
-- Now with 100% less orphaned code and 200% more actual functionality

local ast = rawget(_G, "ast") or require("ast")
local errors = _G.errors

-- Utility: checks if an AST node contains a variable (recursive)
function contains_var(node, var)
    if type(node) ~= "table" then return false end
    if node.type == "variable" and node.name == var then return true end
    for k, v in pairs(node) do
        if type(v) == "table" and contains_var(v, var) then return true end
    end
    return false
end
 
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

-- Simple AST pretty printer (now with 100% less existential crisis)
local function astToString(ast)
    if not ast then return "nil" end
    if type(ast) == "number" then return tostring(ast) end
    if type(ast) == "string" then return ast end
    if type(ast) ~= "table" then return tostring(ast) end
    
    if ast.type == "number" then return tostring(ast.value) end
    if ast.type == "variable" then return ast.name end
    if ast.type == "symbol" then return ast.name end
    
    -- Handle both old-style (left/right) and new-style (args array) structures
    if ast.type == "add" then 
        if ast.args then
            local parts = {}
            for _, arg in ipairs(ast.args) do
                table.insert(parts, astToString(arg))
            end
            return "(" .. table.concat(parts, "+") .. ")"
        else
            return "(" .. astToString(ast.left) .. "+" .. astToString(ast.right) .. ")"
        end
    end
    
    if ast.type == "sub" then 
        if ast.args then
            local parts = {}
            for i, arg in ipairs(ast.args) do
                if i == 1 then
                    table.insert(parts, astToString(arg))
                else
                    table.insert(parts, "-" .. astToString(arg))
                end
            end
            return "(" .. table.concat(parts, "") .. ")"
        else
            return "(" .. astToString(ast.left) .. "-" .. astToString(ast.right) .. ")"
        end
    end
    
    if ast.type == "mul" then 
        if ast.args then
            local parts = {}
            for _, arg in ipairs(ast.args) do
                table.insert(parts, astToString(arg))
            end
            return table.concat(parts, "*")
        else
            return astToString(ast.left) .. "*" .. astToString(ast.right)
        end
    end
    
    if ast.type == "div" then return astToString(ast.left) .. "/" .. astToString(ast.right) end
    if ast.type == "power" or ast.type == "pow" then 
        -- Handle both possible field names because apparently consistency is optional
        local base = ast.left or ast.base
        local exp = ast.right or ast.exp or ast.exponent
        return astToString(base) .. "^" .. astToString(exp)
    end
    if ast.type == "neg" then 
        local inner = ast.arg or ast.value
        return "-(" .. astToString(inner) .. ")" 
    end
    if ast.type == "func" then
        local argstrs = {}
        for _, arg in ipairs(ast.args or {}) do
            table.insert(argstrs, astToString(arg))
        end
        return ast.name .. "(" .. table.concat(argstrs, ",") .. ")"
    end
    if ast.type == "eq" or ast.type == "equation" then 
        return astToString(ast.left) .. " = " .. astToString(ast.right) 
    end
    if ast.type == "pm" then
        return "(" .. astToString(ast.left) .. " ± " .. astToString(ast.right) .. ")"
    end
    
    -- Instead of giving up like a quitter, let's be more informative
    return "UNKNOWN[" .. (ast.type or "no_type") .. "]"
end

-- CORRECTED polynomial coefficient extraction
local function polyCoeffs(ast, var, maxdeg)
    local coeffs = {}

    print("[polyCoeffs] input AST:", astToString(ast))

    -- Force canonical expansion to help coefficient extraction
    if simplify and simplify.simplify then
        ast = simplify.simplify(ast)
        print("[polyCoeffs] after simplification:", astToString(ast))
    end

    -- Helper: robustly get left/right or base/exp
    local function getBaseExp(node)
        local base = node.left or node.base
        local exp = node.right or node.exp
        return base, exp
    end

    -- Recursively walk the AST to extract polynomial terms
    local function walk(node, sign)
        sign = sign or 1
        if not node then return end
        print("[polyCoeffs][walk] node type:", node.type, "node:", astToString(node), "sign:", sign)

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
            -- Try to find a polynomial term: coeff * var^deg
            local children = node.args or { node.left, node.right }
            local coeff = sign
            local var_power = 0
            local unknown = false
            print("[polyCoeffs][mul] processing multiplication with", #children, "children")
            for j, child in ipairs(children) do
                print("[polyCoeffs][mul] child", j, ":", astToString(child), "type:", child.type)
                -- Check for variable, power, or constant
                if isNum(child) then
                    print("[polyCoeffs][mul] found number:", child.value)
                    coeff = coeff * child.value
                elseif isVar(child, var) then
                    print("[polyCoeffs][mul] found variable:", child.name)
                    var_power = var_power + 1
                elseif (child.type == "power" or child.type == "pow") then
                    local base, exp = getBaseExp(child)
                    print("[polyCoeffs][mul] found power: base=", astToString(base), "exp=", astToString(exp))
                    if isVar(base, var) and isNum(exp) then
                        print("[polyCoeffs][mul] power of variable:", exp.value)
                        var_power = var_power + exp.value
                    else
                        print("[polyCoeffs][mul] non-polynomial power, skipping")
                        unknown = true
                        break
                    end
                else
                    -- If the term contains the variable in a non-polynomial way, skip
                    if contains_var(child, var) then
                        print("[polyCoeffs][mul] child contains variable non-polynomially, skipping")
                        unknown = true
                        break
                    else
                        -- treat as numeric factor if possible
                        local val
                        if isNum(child) then 
                            val = child.value
                            print("[polyCoeffs][mul] treating as numeric factor:", val)
                        elseif child.type == "neg" and isNum(child.arg or child.value) then 
                            val = -(child.arg or child.value).value
                            print("[polyCoeffs][mul] treating as negative factor:", val)
                        end
                        if val then
                            coeff = coeff * val
                        else
                            print("[polyCoeffs][mul] unknown non-variable term, skipping")
                            unknown = true
                            break
                        end
                    end
                end
            end
            if not unknown then
                coeffs[var_power] = (coeffs[var_power] or 0) + coeff
                print(string.format("[polyCoeffs][mul] Detected term: coeff=%s degree=%s", tostring(coeff), tostring(var_power)))
            else
                print("[polyCoeffs][mul] Skipped non-polynomial term:", astToString(node))
            end
        elseif (node.type == "power" or node.type == "pow") then
            local base, exp = getBaseExp(node)
            if isVar(base, var) and isNum(exp) then
                coeffs[exp.value] = (coeffs[exp.value] or 0) + sign
                print(string.format("[polyCoeffs][pow] Detected term: coeff=%s degree=%s", tostring(sign), tostring(exp.value)))
            else
                print("[polyCoeffs][pow] Skipped non-polynomial power:", astToString(node))
            end
        elseif isVar(node, var) then
            coeffs[1] = (coeffs[1] or 0) + sign
            print(string.format("[polyCoeffs][var] Detected term: coeff=%s degree=1", tostring(sign)))
        elseif isNum(node) then
            coeffs[0] = (coeffs[0] or 0) + (sign * node.value)
            print(string.format("[polyCoeffs][num] Detected term: coeff=%s degree=0", tostring(sign * node.value)))
        else
            -- Try to handle negative nodes: -(...)
            if node.type == "neg" then
                local inner = node.arg or node.value
                print("[polyCoeffs] handling negation of:", astToString(inner))
                walk(inner, -sign)
            else
                print("[polyCoeffs] Skipped unknown node:", astToString(node))
            end
        end
    end

    walk(ast)
    print("[polyCoeffs] coeffs table:")
    for deg, coeff in pairs(coeffs) do
        print("  degree", deg, "=>", coeff)
    end
    return coeffs
end

-- MASSIVELY IMPROVED simplifyIfConstant function
local function simplifyIfConstant(astnode)
    print("[simplifyIfConstant] Input:", astToString(astnode))
    
    if not astnode then 
        print("[simplifyIfConstant] Input is nil, returning nil")
        return astnode 
    end
    
    -- First, try global simplify if available
    if simplify and simplify.simplify then
        local simplified = simplify.simplify(astnode)
        print("[simplifyIfConstant] After global simplify:", astToString(simplified))
        astnode = simplified
    end
    
    -- Aggressive constant evaluation
    local function aggressiveEval(node)
        if not node or type(node) ~= "table" then 
            print("[aggressiveEval] Non-table node:", tostring(node))
            return node 
        end
        
        print("[aggressiveEval] Processing node type:", node.type, "value:", astToString(node))
        
        if node.type == "number" then 
            print("[aggressiveEval] Already a number:", node.value)
            return node 
        end
        
        -- Handle subtraction: a - b
        if node.type == "sub" and node.left and node.right then
            local left = aggressiveEval(node.left)
            local right = aggressiveEval(node.right)
            print("[aggressiveEval] Sub: left=", astToString(left), "right=", astToString(right))
            
            if left.type == "number" and right.type == "number" then
                local result = { type = "number", value = left.value - right.value }
                print("[aggressiveEval] Sub result:", result.value)
                return result
            end
            
            -- Handle a - (-b) = a + b
            if right.type == "neg" then
                local right_inner = right.arg or right.value
                print("[aggressiveEval] Converting a - (-b) to a + b")
                return aggressiveEval({ type = "add", args = { left, right_inner } })
            end
            
            return { type = "sub", left = left, right = right }
        end
        
        -- Handle multiplication with aggressive coefficient extraction
        if node.type == "mul" and node.args then
            local product = 1
            local non_numeric = {}
            
            print("[aggressiveEval] Mul with", #node.args, "args")
            for i, arg in ipairs(node.args) do
                local eval_arg = aggressiveEval(arg)
                print("[aggressiveEval] Mul arg", i, ":", astToString(eval_arg))
                
                if eval_arg.type == "number" then
                    product = product * eval_arg.value
                    print("[aggressiveEval] Accumulated product:", product)
                elseif eval_arg.type == "neg" then
                    local inner = eval_arg.arg or eval_arg.value
                    if inner.type == "number" then
                        product = product * (-inner.value)
                        print("[aggressiveEval] Negative number, product:", product)
                    else
                        table.insert(non_numeric, eval_arg)
                    end
                else
                    table.insert(non_numeric, eval_arg)
                end
            end
            
            print("[aggressiveEval] Final product:", product, "non-numeric count:", #non_numeric)
            
            if #non_numeric == 0 then
                return { type = "number", value = product }
            elseif product == 1 and #non_numeric == 1 then
                return non_numeric[1]
            else
                local result_args = {}
                if product ~= 1 then
                    table.insert(result_args, { type = "number", value = product })
                end
                for _, arg in ipairs(non_numeric) do
                    table.insert(result_args, arg)
                end
                return { type = "mul", args = result_args }
            end
        end
        
        -- Handle addition
        if node.type == "add" and node.args then
            local sum = 0
            local non_numeric = {}
            
            for _, arg in ipairs(node.args) do
                local eval_arg = aggressiveEval(arg)
                if eval_arg.type == "number" then
                    sum = sum + eval_arg.value
                else
                    table.insert(non_numeric, eval_arg)
                end
            end
            
            if #non_numeric == 0 then
                return { type = "number", value = sum }
            else
                local result_args = {}
                if sum ~= 0 then
                    table.insert(result_args, { type = "number", value = sum })
                end
                for _, arg in ipairs(non_numeric) do
                    table.insert(result_args, arg)
                end
                if #result_args == 1 then
                    return result_args[1]
                else
                    return { type = "add", args = result_args }
                end
            end
        end
        
        -- Handle powers
        if (node.type == "pow" or node.type == "power") then
            local base = aggressiveEval(node.base or node.left)
            local exp = aggressiveEval(node.exp or node.right)
            
            if base.type == "number" and exp.type == "number" and not _G.showComplex then
                return { type = "number", value = base.value ^ exp.value }
            end
            
            return { type = node.type, base = base, exp = exp, left = base, right = exp }
        end
        
        -- Handle negation
        if node.type == "neg" then
            local inner = aggressiveEval(node.arg or node.value)
            if inner.type == "number" then
                return { type = "number", value = -inner.value }
            end
            if inner.type == "neg" then
                return inner.arg or inner.value -- Double negative
            end
            return { type = "neg", arg = inner }
        end
        
        -- Handle functions (like sqrt)
        if node.type == "func" and node.args then
            local eval_args = {}
            local all_numeric = true
            
            for i, arg in ipairs(node.args) do
                eval_args[i] = aggressiveEval(arg)
                if eval_args[i].type ~= "number" then
                    all_numeric = false
                end
            end
            
            if all_numeric and node.name == "sqrt" and #eval_args == 1 then
                local val = eval_args[1].value
                if val >= 0 and not _G.showComplex then
                    return { type = "number", value = math.sqrt(val) }
                elseif val < 0 and _G.showComplex then
                    return {
                        type = "mul",
                        args = {
                            { type = "func", name = "sqrt", args = { { type = "number", value = -val } } },
                            { type = "symbol", name = "i" }
                        }
                    }
                end
            end
            
            return { type = "func", name = node.name, args = eval_args }
        end
        
        return node
    end
    
    local result = aggressiveEval(astnode)
    print("[simplifyIfConstant] Final result:", astToString(result))
    return result
end
-- Safe cube root to handle negative numbers
local function cbrt(x)
    if x >= 0 then
        return x^(1/3)
    else
        return -(-x)^(1/3)
    end
end

local function matchQuadraticEq(eq, var)
    print("\n[matchQuadraticEq] ===== QUADRATIC SOLVER DEBUG BEGINS =====")
    print("[matchQuadraticEq] Input equation:", astToString(eq))
    
    -- Accept forms: ax^2 + bx + c = d
    if eq.type ~= "equation" then 
        print("[matchQuadraticEq] Not an equation, aborting")
        return nil 
    end
    
    local l, r = eq.left, eq.right
    print("[matchQuadraticEq] Left side:", astToString(l))
    print("[matchQuadraticEq] Right side:", astToString(r))
    
    -- Normalize by subtracting right from left: (l - r) = 0
    local norm = { type = "sub", left = l, right = r }
    print("[matchQuadraticEq] Normalized form:", astToString(norm))
    
    local coeffs = polyCoeffs(norm, var)
    if not coeffs then 
        print("[matchQuadraticEq] Failed to extract coefficients")
        return nil 
    end
    
    local a = coeffs[2] or 0
    local b = coeffs[1] or 0
    local c = coeffs[0] or 0

    -- PATCH: Handle quadratic in x^2 (biquadratic/quartic with no odd powers)
    local a4 = coeffs[4] or 0
    local a2 = coeffs[2] or 0
    local a0 = coeffs[0] or 0
    local a3 = coeffs[3] or 0
    local a1 = coeffs[1] or 0
    if a4 ~= 0 and a2 ~= 0 and a0 ~= 0 and (a3 == 0 or not a3) and (a1 == 0 or not a1) then
        print("[matchQuadraticEq] Detected quadratic in x^2 (biquadratic)")
        -- Solve y^2 + b y + c = 0, where y = x^2
        local y_a = a4
        local y_b = a2
        local y_c = a0
        -- Use quadratic formula for y
        local disc = y_b^2 - 4 * y_a * y_c
        if disc < 0 and not _G.showComplex then
            print("[matchQuadraticEq] No real solutions for biquadratic")
            return nil
        end
        local sqrt_disc = math.sqrt(math.abs(disc))
        local y1 = (-y_b + sqrt_disc) / (2 * y_a)
        local y2 = (-y_b - sqrt_disc) / (2 * y_a)
        local results = {}
        -- For each y, x = ±sqrt(y)
        for _, yval in ipairs({y1, y2}) do
            if not _G.showComplex and yval < 0 then
                -- skip this yval, do nothing
            else
                if _G.showComplex then
                    -- Symbolic: always show radicals, even for negatives (so roots may be imaginary)
                    local x_pos = { type = "func", name = "sqrt", args = { { type = "number", value = yval } } }
                    local x_neg = { type = "neg", arg = x_pos }
                    table.insert(results, x_pos)
                    table.insert(results, x_neg)
                else
                    -- Only real roots, as decimal numbers
                    if yval >= 0 then
                        local root = math.sqrt(yval)
                        table.insert(results, { type = "number", value = root })
                        table.insert(results, { type = "number", value = -root })
                    end
                end
            end
        end
        print("[matchQuadraticEq] Biquadratic roots (x):", table.concat(
            (function() local t = {}; for _,r in ipairs(results) do table.insert(t, astToString(r)); end; return t end)(),
            ", "))
        return results
    end
    
    print("[matchQuadraticEq] Extracted coefficients: a=", a, "b=", b, "c=", c)
    
    if a == 0 then 
        print("[matchQuadraticEq] Not quadratic (a=0), aborting")
        return nil 
    end

    -- Helper: Create proper AST number nodes
    local function makeNum(val)
        return { type = "number", value = val }
    end

    -- Build coefficient nodes
    local a_node = makeNum(a)
    local b_node = makeNum(b)
    local c_node = makeNum(c)
    local four_node = makeNum(4)
    local two_node = makeNum(2)

    print("[matchQuadraticEq] Created coefficient nodes:")
    print("  a_node:", astToString(a_node))
    print("  b_node:", astToString(b_node))
    print("  c_node:", astToString(c_node))

    -- Compute discriminant: D = b^2 - 4*a*c
    local b_sq = { type = "power", left = b_node, right = makeNum(2) }
    local four_ac = { type = "mul", args = { four_node, a_node, c_node } }
    local disc = { type = "sub", left = b_sq, right = four_ac }

    print("\n=== DISCRIMINANT DEBUG DISASTER ===")
    print("b_sq AST:", astToString(b_sq))
    print("four_ac AST:", astToString(four_ac)) 
    print("Raw discriminant AST:", astToString(disc))

    -- Always simplify discriminant to a number so sqrt can be clean
    disc = simplifyIfConstant(disc)
    print("Simplified discriminant AST:", astToString(disc))
    print("Discriminant type:", disc.type)
    if disc.type == "number" then 
        print("Discriminant value:", disc.value)
    else
        print("Discriminant is NOT a number - mathematical tragedy continues")
    end
    print("=== END OF DISCRIMINANT SUFFERING ===\n")

    -- Build sqrt(D) and simplify it
    local sqrt_disc = { type = "func", name = "sqrt", args = { disc } }
    local sqrt_disc_simp = simplifyIfConstant(sqrt_disc)

    print("Raw sqrt AST:", astToString(sqrt_disc))
    print("Simplified sqrt AST:", astToString(sqrt_disc_simp))

    -- Compute -b
    local minus_b = { type = "neg", arg = b_node }
    minus_b = simplifyIfConstant(minus_b)
    print("Minus b:", astToString(minus_b))

    -- Compute denominator 2a
    local denom = { type = "mul", args = { two_node, a_node } }
    denom = simplifyIfConstant(denom)
    print("Denominator 2a:", astToString(denom))

    -- Build the two solutions: (-b ± √D) / 2a
    local numerator_plus = { type = "add", args = { minus_b, sqrt_disc_simp } }
    local numerator_minus = { type = "sub", left = minus_b, right = sqrt_disc_simp }

    local plus_case = { type = "div", left = numerator_plus, right = denom }
    local minus_case = { type = "div", left = numerator_minus, right = denom }

    print("Before final simplification:")
    print("  plus_case:", astToString(plus_case))
    print("  minus_case:", astToString(minus_case))

    -- CRITICALLY IMPORTANT: Simplify the solutions FIRST
    if _G.showComplex then
        -- Preserve symbolic radicals and fractions
        plus_case = simplify.simplify(plus_case)
        minus_case = simplify.simplify(minus_case)
    else
        plus_case = simplifyIfConstant(plus_case)
        minus_case = simplifyIfConstant(minus_case)
    end

    print("After final simplification:")
    print("  plus_case:", astToString(plus_case))
    print("  minus_case:", astToString(minus_case))

    -- THE ACTUAL FIX: Always return the simplified separate roots
    -- Because nobody wants to see mathematical hieroglyphics when the answer is clean
    print("[matchQuadraticEq] Returning simplified separate roots because we're not savages")
    print("[matchQuadraticEq] Final answers: x =", astToString(plus_case), "and x =", astToString(minus_case))
    print("[matchQuadraticEq] ===== QUADRATIC SOLVER DEBUG ENDS (SUCCESSFULLY) =====\n")
    return { plus_case, minus_case }
end

-- Cubic equation matcher (debugging version)
local function matchCubicEq(eq, var)
    print("\n[matchCubicEq] ===== CUBIC SOLVER DEBUG BEGINS =====")
    print("[matchCubicEq] Input equation:", astToString(eq))

    if eq.type ~= "equation" then 
        print("[matchCubicEq] Not an equation, aborting")
        return nil 
    end

    local l, r = eq.left, eq.right
    local norm = { type = "sub", left = l, right = r }
    print("[matchCubicEq] Normalized form:", astToString(norm))

    local coeffs = polyCoeffs(norm, var)
    if not coeffs then 
        print("[matchCubicEq] Failed to extract coefficients")
        return nil 
    end

    local a = coeffs[3] or 0
    local b = coeffs[2] or 0
    local c = coeffs[1] or 0
    local d = coeffs[0] or 0

    print(string.format("[matchCubicEq] Extracted coefficients: a=%s, b=%s, c=%s, d=%s", a, b, c, d))

    if a == 0 then
        print("[matchCubicEq] Not a cubic (a=0), aborting")
        return nil
    end

    local delta = b / (3 * a)
    print("[matchCubicEq] Depressed substitution delta =", delta)

    local p = (3*a*c - b^2) / (3*a^2)
    local q = (2*b^3 - 9*a*b*c + 27*a^2*d) / (27*a^3)

    print(string.format("[matchCubicEq] Depressed cubic: t^3 + %.6f*t + %.6f = 0", p, q))

    local discriminant = (q/2)^2 + (p/3)^3
    print("[matchCubicEq] Discriminant =", discriminant)

    local roots = {}

    if discriminant > 0 then
        print("[matchCubicEq] One real root, two complex roots (explicit complex form)")

        local sqrt_disc = math.sqrt(discriminant)
        local u = cbrt(-q/2 + sqrt_disc)
        local v = cbrt(-q/2 - sqrt_disc)
        local t1 = u + v

        if _G.showComplex then
            local symbolic_root = {
                type = "sub",
                left = {
                    type = "add",
                    args = {
                        {
                            type = "func",
                            name = "cbrt",
                            args = {
                                {
                                    type = "sub",
                                    left = { type = "number", value = -q/2 },
                                    right = {
                                        type = "func",
                                        name = "sqrt",
                                        args = { { type = "number", value = discriminant } }
                                    }
                                }
                            }
                        },
                        {
                            type = "func",
                            name = "cbrt",
                            args = {
                                {
                                    type = "add",
                                    left = { type = "number", value = -q/2 },
                                    right = {
                                        type = "func",
                                        name = "sqrt",
                                        args = { { type = "number", value = discriminant } }
                                    }
                                }
                            }
                        }
                    }
                },
                right = { type = "number", value = delta }
            }
            table.insert(roots, simplifyIfConstant(symbolic_root))
        else
            local x1 = t1 - delta
            table.insert(roots, { type = "number", value = x1 })
        end

        -- Complex conjugate pair: real = -t1/2 - delta, imag = ± sqrt(3)*(u - v)/2
        local real_part = (-t1/2) - delta
        local imag_part = math.sqrt(3)*(u - v)/2

        if _G.showComplex then
            local sqrt3 = { type = "func", name = "sqrt", args = { { type = "number", value = 3 } } }
            local symbolic_root2 = {
                type = "add",
                args = {
                    {
                        type = "div",
                        left = { type = "neg", arg = { type = "number", value = t1 } },
                        right = { type = "number", value = 2 }
                    },
                    {
                        type = "mul",
                        args = {
                            sqrt3,
                            {
                                type = "div",
                                left = { type = "number", value = (u - v) },
                                right = { type = "number", value = 2 }
                            },
                            { type = "symbol", name = "i" }
                        }
                    }
                }
            }
            local symbolic_root3 = {
                type = "add",
                args = {
                    {
                        type = "div",
                        left = { type = "neg", arg = { type = "number", value = t1 } },
                        right = { type = "number", value = 2 }
                    },
                    {
                        type = "mul",
                        args = {
                            { type = "neg", arg = { type = "func", name = "sqrt", args = { { type = "number", value = 3 } } } },
                            {
                                type = "div",
                                left = { type = "number", value = (u - v) },
                                right = { type = "number", value = 2 }
                            },
                            { type = "symbol", name = "i" }
                        }
                    }
                }
            }
            table.insert(roots, simplifyIfConstant(symbolic_root2))
            table.insert(roots, simplifyIfConstant(symbolic_root3))
        else
            local root2 = { type = "add", args = {
                { type = "number", value = real_part },
                { type = "mul", args = {
                    { type = "number", value = imag_part },
                    { type = "symbol", name = "i" }
                }}
            }}
            local root3 = { type = "add", args = {
                { type = "number", value = real_part },
                { type = "mul", args = {
                    { type = "number", value = -imag_part },
                    { type = "symbol", name = "i" }
                }}
            }}
            table.insert(roots, simplifyIfConstant(root2))
            table.insert(roots, simplifyIfConstant(root3))
        end
    elseif discriminant == 0 then
        print("[matchCubicEq] Triple or double real roots")
        local u = cbrt(-q/2)
        local t1 = 2*u
        local t2 = -u

        -- New block: Properly distinguish between triple and double roots
        local precision = _G.precision or _G.precision_digits or 4
        local function roundnum(x)
            local mult = 10 ^ precision
            return math.floor(x * mult + 0.5) / mult
        end

        local x1 = roundnum(t1 - delta)
        local x2 = roundnum(t2 - delta)

        -- Distinguish between single and double roots
        if math.abs(x1 - x2) < 1e-10 then
            -- Triple root case
            table.insert(roots, { type = "number", value = x1 })
            table.insert(roots, { type = "number", value = x1 })
            table.insert(roots, { type = "number", value = x1 })
        else
            -- Double root at x2
            table.insert(roots, { type = "number", value = x1 })
            table.insert(roots, { type = "number", value = x2 })
            table.insert(roots, { type = "number", value = x2 })
        end
    else
        print("[matchCubicEq] Three distinct real roots (casus irreducibilis)")
        local r = math.sqrt(-(p^3) / 27)
        local phi = math.acos(-q / (2 * math.sqrt(-(p^3)/27)))
        local t1 = 2 * math.sqrt(-qp/3) * math.cos(phi / 3)
        local t2 = 2 * math.sqrt(-p/3) * math.cos((phi + 2*math.pi) / 3)
        local t3 = 2 * math.sqrt(-p/3) * math.cos((phi + 4*math.pi) / 3)
        local x1 = t1 - delta
        local x2 = t2 - delta
        local x3 = t3 - delta
        -- For three real roots, _G.showComplex not relevant, always real
        table.insert(roots, { type = "number", value = x1 })
        table.insert(roots, { type = "number", value = x2 })
        table.insert(roots, { type = "number", value = x3 })
    end

    print("[matchCubicEq] Final roots:")
    for i, r in ipairs(roots) do
        print(string.format("  Root %d: %s", i, astToString(r)))
    end

    print("[matchCubicEq] ===== CUBIC SOLVER DEBUG ENDS =====\n")
    return roots
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
    if coeffs[2] and coeffs[2] ~= 0 then return nil end -- Quadratic term present, not linear
    if a == 0 then return nil end
    -- Solution is x = -b/a
    local solution_value = -b / a
    return ast.number(solution_value)
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

-- Main solve function
function solve(input_expr, var)
    print("\n[solve] ===== MAIN SOLVE FUNCTION BEGINS =====")
    print("[solve] Input expression:", tostring(input_expr))
    print("[solve] Variable:", tostring(var))
    
    local parser = rawget(_G, "parser") or require("parser")
    local ast_mod = rawget(_G, "ast") or require("ast")
    local simplify = rawget(_G, "simplify") or require("simplify")

    local expr = input_expr
    if type(expr) == "string" then
        print("[solve] Parsing string input:", expr)
        -- Insert '*' between a digit and a letter or digit and '('
        local s = expr
        s = s:gsub("(%d)(%a)", "%1*%2")
        s = s:gsub("(%d)(%()", "%1*%2")
        print("[solve] After implicit multiplication:", s)
        expr = parser.parse(s)
    end
    if not expr then
        error(errors.invalid("solve", "parse failed, got nil AST"))
    end
    
    print("[solve] Parsed AST:", astToString(expr))

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

    print("[solve] Using variable:", var)

    -- Canonicalize equation as eq-node (lhs = rhs), or expr = 0
    if expr.type == "equation" then
        expr = ast_mod.eq(expr.left, expr.right)
    elseif expr.type ~= "equation" then
        expr = ast_mod.eq(expr, ast_mod.number(0))
    end

    print("[solve] Canonicalized equation:", astToString(expr))

    -- Always simplify first
    expr = simplify.simplify(expr)
    print("[solve] After initial simplification:", astToString(expr))

    -- Try all known matchers
    local diff = simplify.simplify(ast_mod.sub(expr.left, expr.right))
    local fallback_eq = ast_mod.eq(diff, ast_mod.number(0))
    
    print("[solve] Normalized difference:", astToString(diff))
    print("[solve] Fallback equation:", astToString(fallback_eq))

    -- Find polynomial degree
    local coeffs = polyCoeffs(fallback_eq.left, var)
    local maxdeg = 0
    for d, _ in pairs(coeffs) do
        if d > maxdeg then maxdeg = d end
    end

    if maxdeg == 1 then
        local ans_lin = matchLinearEq(fallback_eq, var)
        if ans_lin then
            print("[solve] Linear solution found:", astToString(ans_lin))
            local rhs
            if type(ans_lin) ~= "table" then
                rhs = ast_mod.number(ans_lin)
            else
                rhs = ans_lin
            end
            local eq_ast = ast_mod.eq(ast_mod.symbol(var), rhs)
            local simplified_eq = simplify.simplify(eq_ast)
            local result = astToString(simplified_eq)
            if simplified_eq and simplified_eq.type == "sub"
                and simplified_eq.left and simplified_eq.right
                and simplified_eq.left.type == "variable"
                and simplified_eq.right.type == "number" then
                result = simplified_eq.left.name .. " = " .. tostring(simplified_eq.right.value)
            end
            print("[solve] Final linear result:", result)
            if type(var) == "table" and type(var.store) == "function" then
                var.store("last_solve_mode", _G.lastSolveModeFlag or (_G.showComplex and "complex" or "decimal"))
            end
            return result
        end
    elseif maxdeg == 2 then
        local ans_quad = matchQuadraticEq(fallback_eq, var)
        if ans_quad then
            print("[solve] Quadratic solution found")
            local pieces = {}
            for i, root in ipairs(ans_quad) do
                table.insert(pieces, var .. " = " .. astToString(root))
            end
            local result = table.concat(pieces, ", ")
            print("[solve] Final quadratic result:", result)
            if type(var) == "table" and type(var.store) == "function" then
                var.store("last_solve_mode", _G.lastSolveModeFlag or (_G.showComplex and "complex" or "decimal"))
            end
            return result
        end
    elseif maxdeg == 3 then
        local ans_cubic = matchCubicEq(fallback_eq, var)
        if ans_cubic then
            print("[solve] Cubic solution found")
            local result = {}
            for i, root in ipairs(ans_cubic) do
                table.insert(result, var .. " = " .. astToString(root))
            end
            local final_result = table.concat(result, ", ")
            print("[solve] Final cubic result:", final_result)
            if type(var) == "table" and type(var.store) == "function" then
                var.store("last_solve_mode", _G.lastSolveModeFlag or (_G.showComplex and "complex" or "decimal"))
            end
            return final_result
        end
    elseif maxdeg == 4 then
        local ans_quartic = matchQuarticEq(fallback_eq, var)
        if ans_quartic then
            print("[solve] Quartic solution found")
            local result = {}
            for i, root in ipairs(ans_quartic) do
                table.insert(result, var .. " = " .. astToString(root))
            end
            local final_result = table.concat(result, ", ")
            print("[solve] Final quartic result:", final_result)
            if type(var) == "table" and type(var.store) == "function" then
                var.store("last_solve_mode", _G.lastSolveModeFlag or (_G.showComplex and "complex" or "decimal"))
            end
            return final_result
        end
    end


    print("[solve] No analytical solution found")
    return "No solution found"
end

-- Quartic equation matcher: ax^4 + bx^3 + cx^2 + dx + e = 0
local function matchQuarticEq(eq, var)
    print("\n[matchQuarticEq] ===== QUARTIC SOLVER DEBUG BEGINS =====")
    if eq.type ~= "equation" then
        print("[matchQuarticEq] Not an equation, aborting")
        return nil
    end
    local l, r = eq.left, eq.right
    local norm = { type = "sub", left = l, right = r }
    print("[matchQuarticEq] Normalized form:", astToString(norm))
    local coeffs = polyCoeffs(norm, var)
    if not coeffs then print("[matchQuarticEq] Failed to extract coefficients") return nil end
    local a = coeffs[4] or 0
    local b = coeffs[3] or 0
    local c = coeffs[2] or 0
    local d = coeffs[1] or 0
    local e = coeffs[0] or 0
    print(string.format("[matchQuarticEq] Extracted coefficients: a=%s, b=%s, c=%s, d=%s, e=%s", a, b, c, d, e))
    if a == 0 then print("[matchQuarticEq] Not quartic (a=0), aborting") return nil end

    -- Attempt to factor as two quadratics: (x^2 + px + q)(x^2 + rx + s) = 0
    local function try_quartic_factoring(a, b, c, d, e)
        -- Only attempt if all coefficients are integers (to avoid floating imprecision)
        if math.floor(a) ~= a or math.floor(b) ~= b or math.floor(c) ~= c or math.floor(d) ~= d or math.floor(e) ~= e then return nil end
        -- Try to solve: (x^2 + p x + q)(x^2 + r x + s) = ax^4 + bx^3 + cx^2 + dx + e
        -- This expands to:
        -- a x^4 + b x^3 + c x^2 + d x + e =
        -- x^4 + (p + r)x^3 + (q + pr + s)x^2 + (ps + qr)x + qs
        -- Here, a = 1 assumed (normalize first); else, factor out 'a'
        if a ~= 1 then
            b = b / a; c = c / a; d = d / a; e = e / a
        end
        for p = -10, 10 do for r = -10, 10 do
        for q = -10, 10 do for s = -10, 10 do
            if (p + r == b) and (q + p*r + s == c) and (p*s + q*r == d) and (q*s == e) then
                -- We found a factorization!
                return {p=p, q=q, r=r, s=s}
            end
        end end end end
        return nil
    end

    local factors = try_quartic_factoring(a, b, c, d, e)
    if factors then
        print("[matchQuarticEq] Factored as (x^2+"..factors.p.."x+"..factors.q..")*(x^2+"..factors.r.."x+"..factors.s..")")
        -- Solve both quadratics, propagate _G.showComplex to allow/deny complex roots
        local roots1 = matchQuadraticEq(
            { type="equation", left={type="add", args={
                {type="pow", base={type="variable", name=var}, exp={type="number", value=2}},
                {type="mul", args={{type="number", value=factors.p}, {type="variable", name=var}}},
                {type="number", value=factors.q}
            }}, right={type="number", value=0}}, var)
        local roots2 = matchQuadraticEq(
            { type="equation", left={type="add", args={
                {type="pow", base={type="variable", name=var}, exp={type="number", value=2}},
                {type="mul", args={{type="number", value=factors.r}, {type="variable", name=var}}},
                {type="number", value=factors.s}
            }}, right={type="number", value=0}}, var)
        local all_roots = {}
        if roots1 then for _, rt in ipairs(roots1) do table.insert(all_roots, rt) end end
        if roots2 then for _, rt in ipairs(roots2) do table.insert(all_roots, rt) end end
        return all_roots
    end

    -- Normalize coefficients
    b = b / a
    c = c / a
    d = d / a
    e = e / a

    -- Ferrari's method (numeric version)
    local p = c - 3 * b^2 / 8
    local q = b^3 / 8 - b * c / 2 + d
    local r = e - 3 * b^4 / 256 + b^2 * c / 16 - b * d / 4
    print(string.format("[matchQuarticEq] Depressed quartic: y^4 + %.6f*y^2 + %.6f*y + %.6f = 0", p, q, r))

    -- Solve resolvent cubic
    local cubicA = 1
    local cubicB = 2 * p
    local cubicC = p^2 - 4 * r
    local cubicD = -q^2
    local cubicRoots = solveCubicReal(cubicA, cubicB, cubicC, cubicD)
    local z = cubicRoots[1]  -- Use first real root
    print("[matchQuarticEq] Chose resolvent root z =", z)

    -- Helper for complex division
    local function div_complex(a, b)
        -- Divides a by b, where either may be real or complex tables
        local a_re = type(a) == "table" and a.re or a
        local a_im = type(a) == "table" and (a.im or 0) or 0
        local b_re = type(b) == "table" and b.re or b
        local b_im = type(b) == "table" and (b.im or 0) or 0
        if b_im == 0 then
            -- b is real
            if type(a) == "table" then
                return { re = a_re / b_re, im = a_im / b_re }
            else
                return a_re / b_re
            end
        end
        -- Complex division
        local denom = b_re^2 + b_im^2
        return {
            re = (a_re * b_re + a_im * b_im) / denom,
            im = (a_im * b_re - a_re * b_im) / denom
        }
    end

    -- Helper for complex multiplication
    local function mul_complex(a, b)
        local a_re = type(a) == "table" and a.re or a
        local a_im = type(a) == "table" and (a.im or 0) or 0
        local b_re = type(b) == "table" and b.re or b
        local b_im = type(b) == "table" and (b.im or 0) or 0
        return {
            re = a_re * b_re - a_im * b_im,
            im = a_re * b_im + a_im * b_re
        }
    end

    local sqrt1 = safe_sqrt(2 * z - p)
    local sqrt1v = type(sqrt1) == "table" and sqrt1.re or sqrt1
    --local sqrt2 = (type(sqrt1) == "table") and 0 or (q / (2 * sqrt1))
    --local S1 = sqrt1
    --local S2 = sqrt2
    local S1 = sqrt1
    local S2 = div_complex(q, type(sqrt1) == "table" and { re = 2 * (sqrt1.re or 0), im = 2 * (sqrt1.im or 0) } or (2 * sqrt1))

    local roots = {}
    local precision = _G.precision or _G.precision_digits or 4
    local function roundnum(x)
        if not x then return 0 end
        local mult = 10 ^ precision
        return math.floor(x * mult + 0.5) / mult
    end
    local function format_root(val)
        if type(val) == "table" and val.im and val.im ~= 0 then
            return {
                type = "add",
                args = {
                    { type = "number", value = roundnum(val.re) },
                    {
                        type = "mul",
                        args = {
                            { type = "number", value = roundnum(val.im) },
                            { type = "symbol", name = "i" }
                        }
                    }
                }
            }
        else
            return { type = "number", value = roundnum(type(val) == "table" and val.re or val) }
        end
    end

    local function add_complex(a, b)
        if type(a) == "table" and type(b) == "table" then
            return { re = a.re + b.re, im = (a.im or 0) + (b.im or 0) }
        elseif type(a) == "table" then
            return { re = a.re + b, im = a.im }
        elseif type(b) == "table" then
            return { re = a + b.re, im = b.im }
        else
            return a + b
        end
    end

    local function sub_complex(a, b)
        if type(a) == "table" and type(b) == "table" then
            return { re = a.re - b.re, im = (a.im or 0) - (b.im or 0) }
        elseif type(a) == "table" then
            return { re = a.re - b, im = a.im }
        elseif type(b) == "table" then
            return { re = a - b.re, im = -b.im }
        else
            return a - b
        end
    end

    local function neg_complex(a)
        if type(a) == "table" then
            return { re = -(a.re or 0), im = -(a.im or 0) }
        else
            return -a
        end
    end

    local function div2(val)
        if type(val) == "table" then
            return { re = val.re / 2, im = (val.im or 0) / 2 }
        else
            return val / 2
        end
    end

    local t1 = add_complex(S1, safe_sqrt(sub_complex(-(2 * z + p), neg_complex(mul_complex(2, S2)))))
    local t2 = sub_complex(S1, safe_sqrt(sub_complex(-(2 * z + p), neg_complex(mul_complex(2, S2)))))
    local t3 = add_complex(neg_complex(S1), safe_sqrt(sub_complex(-(2 * z + p), mul_complex(2, S2))))
    local t4 = sub_complex(neg_complex(S1), safe_sqrt(sub_complex(-(2 * z + p), mul_complex(2, S2))))

    local base = -b / 4
    local y1 = add_complex(base, div2(t1))
    local y2 = add_complex(base, div2(t2))
    local y3 = add_complex(base, div2(t3))
    local y4 = add_complex(base, div2(t4))

    print(string.format("[matchQuarticEq] Numeric roots: %s, %s, %s, %s",
        type(y1)=="table" and (y1.re or "")..(y1.im and ("+"..y1.im.."i") or "") or tostring(y1),
        type(y2)=="table" and (y2.re or "")..(y2.im and ("+"..y2.im.."i") or "") or tostring(y2),
        type(y3)=="table" and (y3.re or "")..(y3.im and ("+"..y3.im.."i") or "") or tostring(y3),
        type(y4)=="table" and (y4.re or "")..(y4.im and ("+"..y4.im.."i") or "") or tostring(y4)
    ))

    -- Before constructing roots, if _G.showComplex is not set and any root is complex, skip or return only real roots
    if not _G.showComplex then
        local real_roots = {}
        for _, y in ipairs({y1, y2, y3, y4}) do
            if type(y) == "table" and (y.im and math.abs(y.im) > 1e-10) then
                -- skip complex root
            else
                -- real root
                local val = y
                if type(y) == "table" then val = y.re end
                table.insert(real_roots, format_root(val))
            end
        end
        if #real_roots == 0 then
            print("[matchQuarticEq] No real roots found")
            return {"No real roots"}
        else
            return real_roots
        end
    end

    return {
        format_root(y1),
        format_root(y2),
        format_root(y3),
        format_root(y4)
    }
end

function solveCubicReal(a, b, c, d)
    b = b / a; c = c / a; d = d / a
    local p = c - b^2 / 3
    local q = 2 * b^3 / 27 - b * c / 3 + d
    local roots = {}
    local discriminant = (q / 2)^2 + (p / 3)^3
    if discriminant > 0 then
        local u = cbrt(-q / 2 + math.sqrt(discriminant))
        local v = cbrt(-q / 2 - math.sqrt(discriminant))
        table.insert(roots, u + v - b / 3)
    else
        local r = math.sqrt(-p^3 / 27)
        local phi = math.acos(-q / (2 * r))
        local t = 2 * math.sqrt(-p / 3)
        table.insert(roots, t * math.cos(phi / 3) - b / 3)
        table.insert(roots, t * math.cos((phi + 2 * math.pi) / 3) - b / 3)
        table.insert(roots, t * math.cos((phi + 4 * math.pi) / 3) - b / 3)
    end
    return roots
end

-- Export functions
_G.solve = solve
_G.polyCoeffs = polyCoeffs
_G.matchLinearEq = matchLinearEq
_G.matchQuadraticEq = matchQuadraticEq
_G.astToString = astToString
_G.matchCubicEq = matchCubicEq
_G.matchQuarticEq = matchQuarticEq