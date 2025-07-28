-- solve.lua - Now with 50% less mathematical masturbation
-- Because apparently some of us can count past 10 without taking our shoes off

local ast = rawget(_G, "ast") or require("ast")
local errors = _G.errors

-- Helper to format expressions nicely for steps
local function format_expr(ast_node)
  if not ast_node then return "nil" end
  if type(ast_node) == "number" then return tostring(ast_node) end
  if type(ast_node) == "string" then return ast_node end
  if type(ast_node) ~= "table" then return tostring(ast_node) end
  
  if ast_node.type == "number" then return tostring(ast_node.value) end
  if ast_node.type == "variable" then return ast_node.name end
  if ast_node.type == "symbol" then return ast_node.name end
  
  if ast_node.type == "add" then 
    if ast_node.args then
      local parts = {}
      for _, arg in ipairs(ast_node.args) do
        table.insert(parts, format_expr(arg))
      end
      return table.concat(parts, " + ")
    else
      return format_expr(ast_node.left) .. " + " .. format_expr(ast_node.right)
    end
  end
  
  if ast_node.type == "sub" then 
    return format_expr(ast_node.left) .. " - " .. format_expr(ast_node.right)
  end
  
  if ast_node.type == "mul" then 
    if ast_node.args then
      local parts = {}
      for _, arg in ipairs(ast_node.args) do
        local part = format_expr(arg)
        if arg.type == "add" or arg.type == "sub" then
          part = "(" .. part .. ")"
        end
        table.insert(parts, part)
      end
      return table.concat(parts, "·")
    else
      return format_expr(ast_node.left) .. "·" .. format_expr(ast_node.right)
    end
  end
  
  if ast_node.type == "div" then 
    local num = format_expr(ast_node.left)
    local den = format_expr(ast_node.right)
    if ast_node.left.type == "add" or ast_node.left.type == "sub" then
      num = "(" .. num .. ")"
    end
    if ast_node.right.type == "add" or ast_node.right.type == "sub" then
      den = "(" .. den .. ")"
    end
    return num .. "/" .. den
  end
  
  if ast_node.type == "power" or ast_node.type == "pow" then 
    local base = ast_node.left or ast_node.base
    local exp = ast_node.right or ast_node.exp or ast_node.exponent
    local base_str = format_expr(base)
    if base.type ~= "variable" and base.type ~= "number" then
      base_str = "(" .. base_str .. ")"
    end
    return base_str .. "^" .. format_expr(exp)
  end
  
  if ast_node.type == "neg" then 
    local inner = ast_node.arg or ast_node.value
    local inner_str = format_expr(inner)
    if inner.type == "add" or inner.type == "sub" then
      inner_str = "(" .. inner_str .. ")"
    end
    return "-" .. inner_str
  end
  
  if ast_node.type == "func" then
    local argstrs = {}
    for _, arg in ipairs(ast_node.args or {}) do
      table.insert(argstrs, format_expr(arg))
    end
    return ast_node.name .. "(" .. table.concat(argstrs, ", ") .. ")"
  end
  
  if ast_node.type == "eq" or ast_node.type == "equation" then 
    return format_expr(ast_node.left) .. " = " .. format_expr(ast_node.right)
  end
  
  return "UNKNOWN[" .. (ast_node.type or "no_type") .. "]"
end

-- Complexity analyzer - because not all equations deserve a PhD dissertation
local function analyzeComplexity(equation_str, coeffs, degree)
    local complexity = {
        score = 0,
        is_trivial = false,
        reasons = {}
    }
    
    -- Check for simple integer coefficients
    local all_integers = true
    local all_small = true
    local non_zero_count = 0
    
    for deg, coeff in pairs(coeffs) do
        if coeff ~= 0 then
            non_zero_count = non_zero_count + 1
            if coeff ~= math.floor(coeff) then
                all_integers = false
            end
            if math.abs(coeff) > 100 then
                all_small = false
            end
        end
    end
    
    -- Scoring system for complexity
    if degree == 1 then
        complexity.score = 1
        table.insert(complexity.reasons, "linear equation")
    elseif degree == 2 then
        complexity.score = 2
        -- Check if it's a simple form like ax² = b
        if non_zero_count == 2 and coeffs[1] == 0 then
            complexity.score = 1.5
            complexity.is_trivial = true
            table.insert(complexity.reasons, "trivial quadratic (ax² = b)")
        elseif all_integers and all_small then
            complexity.score = 2
            table.insert(complexity.reasons, "simple quadratic")
        else
            complexity.score = 3
            table.insert(complexity.reasons, "general quadratic")
        end
    elseif degree == 3 then
        complexity.score = 4
        table.insert(complexity.reasons, "cubic equation")
    elseif degree == 4 then
        complexity.score = 5
        -- Check for biquadratic
        if (coeffs[3] or 0) == 0 and (coeffs[1] or 0) == 0 then
            complexity.score = 3.5
            table.insert(complexity.reasons, "biquadratic equation")
        else
            table.insert(complexity.reasons, "quartic equation")
        end
    end
    
    -- Additional complexity factors
    if not all_integers then
        complexity.score = complexity.score + 0.5
        table.insert(complexity.reasons, "non-integer coefficients")
    end
    
    if not all_small then
        complexity.score = complexity.score + 0.5
        table.insert(complexity.reasons, "large coefficients")
    end
    
    return complexity
end

-- Step filtering based on complexity
local function filterSteps(steps, complexity)
    if not steps or #steps == 0 then return steps end
    
    local filtered = {}
    local skip_patterns = {}
    
    -- Define what to skip based on complexity
    if complexity.is_trivial then
        skip_patterns = {
            "Extracting polynomial coefficients",
            "After simplification",
            "Rearranging to standard form",
            "Standard quadratic form",
            "Discriminant:",
            "Where a =",
            "Using quadratic formula",
            "Polynomial degree",
            "Variable to solve for",
            "Converting to equation form",
            "This is a %w+ equation"
        }
    elseif complexity.score < 3 then
        skip_patterns = {
            "Extracting polynomial coefficients",
            "After simplification",
            "Variable to solve for",
            "Polynomial degree"
        }
    elseif complexity.score < 4 then
        skip_patterns = {
            "Variable to solve for"
        }
    end
    
    -- Filter steps
    for _, step in ipairs(steps) do
        local skip = false
        for _, pattern in ipairs(skip_patterns) do
            if string.find(step.description, pattern) then
                skip = true
                break
            end
        end
        
        if not skip then
            table.insert(filtered, step)
        end
    end
    
    -- For trivial equations, keep only the essentials
    if complexity.is_trivial and #filtered > 4 then
        local essential = {}
        table.insert(essential, steps[1]) -- Original equation
        
        -- Find and keep the actual solution steps
        for i = #steps, 1, -1 do
            if string.find(steps[i].description, "=") and 
               (string.find(steps[i].description, "x") or 
                string.find(steps[i].description, "y") or 
                string.find(steps[i].description, "Solution")) then
                table.insert(essential, 1, steps[i])
                if #essential >= 3 then break end
            end
        end
        
        return essential
    end
    
    return filtered
end

local function safe_sqrt(x)
    if type(x) == "table" then
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

function contains_var(node, var)
    if type(node) ~= "table" then return false end
    if node.type == "variable" and node.name == var then return true end
    for k, v in pairs(node) do
        if type(v) == "table" and contains_var(v, var) then return true end
    end
    return false
end

local function isNum(ast)
    return ast and ast.type == "number"
end

local function isVar(ast, v)
    return ast and ast.type == "variable" and (not v or ast.name == v)
end

local parser = rawget(_G, "parser") or require("parser")
local simplify = rawget(_G, "simplify") or require("simplify")

local function deepCopy(obj)
    if type(obj) ~= "table" then return obj end
    local res = {}
    for k, v in pairs(obj) do res[k] = deepCopy(v) end
    return res
end

-- Enhanced polynomial coefficient extraction with steps
local function polyCoeffs(ast, var, maxdeg, steps)
    local coeffs = {}
    
    -- Only add this step for non-trivial equations
    if steps and (not _G.suppress_basic_steps) then
        table.insert(steps, { description = "Extracting polynomial coefficients from: " .. format_expr(ast) })
    end

    if simplify and simplify.simplify then
        ast = simplify.simplify(ast)
        if steps and (not _G.suppress_basic_steps) then
            table.insert(steps, { description = "After simplification: " .. format_expr(ast) })
        end
    end

    local function getBaseExp(node)
        local base = node.left or node.base
        local exp = node.right or node.exp
        return base, exp
    end

    local function walk(node, sign)
        sign = sign or 1
        if not node then return end

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
            local children = node.args or { node.left, node.right }
            local coeff = sign
            local var_power = 0
            local unknown = false
            
            for j, child in ipairs(children) do
                if isNum(child) then
                    coeff = coeff * child.value
                elseif isVar(child, var) then
                    var_power = var_power + 1
                elseif (child.type == "power" or child.type == "pow") then
                    local base, exp = getBaseExp(child)
                    if isVar(base, var) and isNum(exp) then
                        var_power = var_power + exp.value
                    else
                        unknown = true
                        break
                    end
                else
                    if contains_var(child, var) then
                        unknown = true
                        break
                    else
                        local val
                        if isNum(child) then 
                            val = child.value
                        elseif child.type == "neg" and isNum(child.arg or child.value) then 
                            val = -(child.arg or child.value).value
                        end
                        if val then
                            coeff = coeff * val
                        else
                            unknown = true
                            break
                        end
                    end
                end
            end
            if not unknown then
                coeffs[var_power] = (coeffs[var_power] or 0) + coeff
            end
        elseif (node.type == "power" or node.type == "pow") then
            local base, exp = getBaseExp(node)
            if isVar(base, var) and isNum(exp) then
                coeffs[exp.value] = (coeffs[exp.value] or 0) + sign
            end
        elseif isVar(node, var) then
            coeffs[1] = (coeffs[1] or 0) + sign
        elseif isNum(node) then
            coeffs[0] = (coeffs[0] or 0) + (sign * node.value)
        else
            if node.type == "neg" then
                local inner = node.arg or node.value
                walk(inner, -sign)
            end
        end
    end

    walk(ast)
    
    if steps and (not _G.suppress_basic_steps) then
        local coeff_strs = {}
        for deg = 4, 0, -1 do
            if coeffs[deg] and coeffs[deg] ~= 0 then
                local coeff_val = coeffs[deg]
                if deg == 0 then
                    table.insert(coeff_strs, tostring(coeff_val))
                elseif deg == 1 then
                    if coeff_val == 1 then
                        table.insert(coeff_strs, var)
                    elseif coeff_val == -1 then
                        table.insert(coeff_strs, "-" .. var)
                    else
                        table.insert(coeff_strs, coeff_val .. var)
                    end
                else
                    if coeff_val == 1 then
                        table.insert(coeff_strs, var .. "^" .. deg)
                    elseif coeff_val == -1 then
                        table.insert(coeff_strs, "-" .. var .. "^" .. deg)
                    else
                        table.insert(coeff_strs, coeff_val .. var .. "^" .. deg)
                    end
                end
            end
        end
        if #coeff_strs > 0 then
            table.insert(steps, { description = "Identified polynomial: " .. table.concat(coeff_strs, " + "):gsub("%+ %-", "- ") .. " = 0" })
        end
        
        local coeff_list = {}
        for deg = 0, 4 do
            if coeffs[deg] then
                table.insert(coeff_list, "a" .. deg .. " = " .. coeffs[deg])
            end
        end
        if #coeff_list > 0 then
            table.insert(steps, { description = "Coefficients: " .. table.concat(coeff_list, ", ") })
        end
    end
    
    return coeffs
end

local function simplifyIfConstant(astnode)
    if not astnode then return astnode end
    
    if simplify and simplify.simplify then
        local simplified = simplify.simplify(astnode)
        astnode = simplified
    end
    
    local function aggressiveEval(node)
        if not node or type(node) ~= "table" then return node end
        
        if node.type == "number" then return node end
        
        if node.type == "sub" and node.left and node.right then
            local left = aggressiveEval(node.left)
            local right = aggressiveEval(node.right)
            
            if left.type == "number" and right.type == "number" then
                return { type = "number", value = left.value - right.value }
            end
            
            if right.type == "neg" then
                local right_inner = right.arg or right.value
                return aggressiveEval({ type = "add", args = { left, right_inner } })
            end
            
            return { type = "sub", left = left, right = right }
        end
        
        if node.type == "mul" and node.args then
            local product = 1
            local non_numeric = {}
            
            for i, arg in ipairs(node.args) do
                local eval_arg = aggressiveEval(arg)
                
                if eval_arg.type == "number" then
                    product = product * eval_arg.value
                elseif eval_arg.type == "neg" then
                    local inner = eval_arg.arg or eval_arg.value
                    if inner.type == "number" then
                        product = product * (-inner.value)
                    else
                        table.insert(non_numeric, eval_arg)
                    end
                else
                    table.insert(non_numeric, eval_arg)
                end
            end
            
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
        
        if (node.type == "pow" or node.type == "power") then
            local base = aggressiveEval(node.base or node.left)
            local exp = aggressiveEval(node.exp or node.right)
            
            if base.type == "number" and exp.type == "number" and not _G.showComplex then
                return { type = "number", value = base.value ^ exp.value }
            end
            
            return { type = node.type, base = base, exp = exp, left = base, right = exp }
        end
        
        if node.type == "neg" then
            local inner = aggressiveEval(node.arg or node.value)
            if inner.type == "number" then
                return { type = "number", value = -inner.value }
            end
            if inner.type == "neg" then
                return inner.arg or inner.value
            end
            return { type = "neg", arg = inner }
        end
        
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
    
    return aggressiveEval(astnode)
end

local function cbrt(x)
    if x >= 0 then
        return x^(1/3)
    else
        return -(-x)^(1/3)
    end
end

-- Linear equation solver with steps
local function matchLinearEq(eq, var, steps)
    if eq.type ~= "equation" then return nil end
    
    table.insert(steps, { description = "Solving linear equation: " .. format_expr(eq) })
    
    local l, r = eq.left, eq.right
    local norm = { type="sub", left=l, right=r }
    
    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "Rearranging to standard form: " .. format_expr(norm) .. " = 0" })
    end
    
    local coeffs = polyCoeffs(norm, var, nil, steps)
    if not coeffs then return nil end
    
    local a = coeffs[1] or 0
    local b = coeffs[0] or 0
    
    if coeffs[2] and coeffs[2] ~= 0 then return nil end
    if a == 0 then return nil end
    
    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "For linear equation a" .. var .. " + b = 0, where a = " .. a .. " and b = " .. b })
        table.insert(steps, { description = "Solution: " .. var .. " = -b/a = -(" .. b .. ")/(" .. a .. ")" })
    end
    
    local solution_value = -b / a
    table.insert(steps, { description = var .. " = " .. solution_value })
    
    return ast.number(solution_value)
end

-- Quadratic equation solver with detailed steps
local function matchQuadraticEq(eq, var, steps)
    if eq.type ~= "equation" then return nil end
    
    table.insert(steps, { description = "Solving quadratic equation: " .. format_expr(eq) })
    
    local l, r = eq.left, eq.right
    local norm = { type = "sub", left = l, right = r }
    
    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "Rearranging to standard form: " .. format_expr(norm) .. " = 0" })
    end
    
    local coeffs = polyCoeffs(norm, var, nil, steps)
    if not coeffs then return nil end
    
    local a = coeffs[2] or 0
    local b = coeffs[1] or 0
    local c = coeffs[0] or 0

    -- Handle biquadratic case (quartic with only even powers)
    local a4 = coeffs[4] or 0
    local a2 = coeffs[2] or 0
    local a0 = coeffs[0] or 0
    local a3 = coeffs[3] or 0
    local a1 = coeffs[1] or 0
    
    if a4 ~= 0 and a2 ~= 0 and a0 ~= 0 and (a3 == 0 or not a3) and (a1 == 0 or not a1) then
        table.insert(steps, { description = "This is a biquadratic equation (quadratic in " .. var .. "²)" })
        table.insert(steps, { description = "Let y = " .. var .. "², then: " .. a4 .. "y² + " .. a2 .. "y + " .. a0 .. " = 0" })
        
        local disc = a2^2 - 4 * a4 * a0
        table.insert(steps, { description = "Discriminant: Δ = b² - 4ac = (" .. a2 .. ")² - 4(" .. a4 .. ")(" .. a0 .. ") = " .. disc })
        
        if disc < 0 and not _G.showComplex then
            table.insert(steps, { description = "Discriminant < 0, no real solutions" })
            return nil
        end
        
        local sqrt_disc = math.sqrt(math.abs(disc))
        local y1 = (-a2 + sqrt_disc) / (2 * a4)
        local y2 = (-a2 - sqrt_disc) / (2 * a4)
        
        table.insert(steps, { description = "Solutions for y: y₁ = " .. y1 .. ", y₂ = " .. y2 })
        table.insert(steps, { description = "Since y = " .. var .. "², we have " .. var .. " = ±√y for each positive y" })
        
        local results = {}
        for i, yval in ipairs({y1, y2}) do
            if not _G.showComplex and yval < 0 then
                table.insert(steps, { description = "y" .. i .. " = " .. yval .. " < 0, skipping (no real square roots)" })
            else
                if _G.showComplex then
                    local x_pos = { type = "func", name = "sqrt", args = { { type = "number", value = yval } } }
                    local x_neg = { type = "neg", arg = x_pos }
                    table.insert(results, x_pos)
                    table.insert(results, x_neg)
                    table.insert(steps, { description = "From y" .. i .. " = " .. yval .. ": " .. var .. " = ±√(" .. yval .. ")" })
                else
                    if yval >= 0 then
                        local root = math.sqrt(yval)
                        table.insert(results, { type = "number", value = root })
                        table.insert(results, { type = "number", value = -root })
                        table.insert(steps, { description = "From y" .. i .. " = " .. yval .. ": " .. var .. " = ±" .. root })
                    end
                end
            end
        end
        return results
    end
    
    if a == 0 then return nil end

    -- Check if this is a trivial quadratic (ax² + c = 0)
    local is_trivial = (b == 0)
    
    if not is_trivial and not _G.suppress_basic_steps then
        table.insert(steps, { description = "Standard quadratic form: a" .. var .. "² + b" .. var .. " + c = 0" })
        table.insert(steps, { description = "Where a = " .. a .. ", b = " .. b .. ", c = " .. c })
    elseif is_trivial then
        -- For trivial quadratics, just show the key step
        table.insert(steps, { description = var .. "² = " .. (-c/a) })
    end
    
    if is_trivial then
        -- Direct solution for ax² + c = 0
        local val = -c/a
        if val < 0 and not _G.showComplex then
            table.insert(steps, { description = "No real solutions (negative square)" })
            return nil
        end
        
        local sqrt_val = math.sqrt(math.abs(val))
        table.insert(steps, { description = var .. " = ±" .. sqrt_val })
        
        local makeNum = function(v) return { type = "number", value = v } end
        return { makeNum(sqrt_val), makeNum(-sqrt_val) }
    end
    
    -- Calculate discriminant
    local discriminant = b^2 - 4*a*c
    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "Discriminant: Δ = b² - 4ac = (" .. b .. ")² - 4(" .. a .. ")(" .. c .. ")" })
        table.insert(steps, { description = "Δ = " .. b^2 .. " - " .. (4*a*c) .. " = " .. discriminant })
    end
    
    if discriminant < 0 and not _G.showComplex then
        table.insert(steps, { description = "Since Δ < 0, there are no real solutions" })
        return nil
    elseif discriminant == 0 then
        table.insert(steps, { description = "Since Δ = 0, there is one repeated real solution" })
    elseif discriminant > 0 then
        if not _G.suppress_basic_steps then
            table.insert(steps, { description = "Since Δ > 0, there are two distinct real solutions" })
        end
    end
    
    -- Apply quadratic formula
    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "Using quadratic formula: " .. var .. " = (-b ± √Δ)/(2a)" })
        table.insert(steps, { description = var .. " = (-(" .. b .. ") ± √(" .. discriminant .. "))/(2·" .. a .. ")" })
        table.insert(steps, { description = var .. " = (" .. (-b) .. " ± √(" .. discriminant .. "))/" .. (2*a) })
    end
    
    -- Build solutions
    local makeNum = function(val) return { type = "number", value = val } end
    local a_node = makeNum(a)
    local b_node = makeNum(b)
    local c_node = makeNum(c)
    local four_node = makeNum(4)
    local two_node = makeNum(2)

    local b_sq = { type = "power", left = b_node, right = makeNum(2) }
    local four_ac = { type = "mul", args = { four_node, a_node, c_node } }
    local disc = { type = "sub", left = b_sq, right = four_ac }
    disc = simplifyIfConstant(disc)

    local sqrt_disc = { type = "func", name = "sqrt", args = { disc } }
    local sqrt_disc_simp = simplifyIfConstant(sqrt_disc)

    local minus_b = { type = "neg", arg = b_node }
    minus_b = simplifyIfConstant(minus_b)

    local denom = { type = "mul", args = { two_node, a_node } }
    denom = simplifyIfConstant(denom)

    local numerator_plus = { type = "add", args = { minus_b, sqrt_disc_simp } }
    local numerator_minus = { type = "sub", left = minus_b, right = sqrt_disc_simp }

    local plus_case = { type = "div", left = numerator_plus, right = denom }
    local minus_case = { type = "div", left = numerator_minus, right = denom }

    if _G.showComplex then
        plus_case = simplify.simplify(plus_case)
        minus_case = simplify.simplify(minus_case)
    else
        plus_case = simplifyIfConstant(plus_case)
        minus_case = simplifyIfConstant(minus_case)
    end

    local sqrt_val = math.sqrt(math.abs(discriminant))
    local sol1 = (-b + sqrt_val) / (2*a)
    local sol2 = (-b - sqrt_val) / (2*a)
    
    table.insert(steps, { description = var .. "₁ = (" .. (-b) .. " + " .. sqrt_val .. ")/" .. (2*a) .. " = " .. sol1 })
    table.insert(steps, { description = var .. "₂ = (" .. (-b) .. " - " .. sqrt_val .. ")/" .. (2*a) .. " = " .. sol2 })

    return { plus_case, minus_case }
end

-- Cubic equation solver with steps  
local function matchCubicEq(eq, var, steps)
    if eq.type ~= "equation" then return nil end

    table.insert(steps, { description = "Solving cubic equation: " .. format_expr(eq) })

    local l, r = eq.left, eq.right
    local norm = { type = "sub", left = l, right = r }
    
    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "Rearranging to standard form: " .. format_expr(norm) .. " = 0" })
    end

    local coeffs = polyCoeffs(norm, var, nil, steps)
    if not coeffs then return nil end

    local a = coeffs[3] or 0
    local b = coeffs[2] or 0
    local c = coeffs[1] or 0
    local d = coeffs[0] or 0

    if a == 0 then return nil end

    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "Standard cubic form: a" .. var .. "³ + b" .. var .. "² + c" .. var .. " + d = 0" })
        table.insert(steps, { description = "Where a = " .. a .. ", b = " .. b .. ", c = " .. c .. ", d = " .. d })
    end

    -- Reduce to depressed cubic
    local delta = b / (3 * a)
    table.insert(steps, { description = "Converting to depressed cubic using substitution " .. var .. " = t + " .. delta })
    
    local p = (3*a*c - b^2) / (3*a^2)
    local q = (2*b^3 - 9*a*b*c + 27*a^2*d) / (27*a^3)

    table.insert(steps, { description = "Depressed cubic: t³ + pt + q = 0" })
    table.insert(steps, { description = "Where p = " .. string.format("%.6f", p) .. " and q = " .. string.format("%.6f", q) })

    local discriminant = (q/2)^2 + (p/3)^3
    table.insert(steps, { description = "Discriminant: Δ = (q/2)² + (p/3)³ = " .. string.format("%.6f", discriminant) })

    local roots = {}

    if discriminant > 0 then
        table.insert(steps, { description = "Since Δ > 0: one real root and two complex conjugate roots" })

        local sqrt_disc = math.sqrt(discriminant)
        local u = cbrt(-q/2 + sqrt_disc)
        local v = cbrt(-q/2 - sqrt_disc)
        local t1 = u + v

        table.insert(steps, { description = "Using Cardano's formula:" })
        table.insert(steps, { description = "u = ∛(-q/2 + √Δ) = " .. string.format("%.6f", u) })
        table.insert(steps, { description = "v = ∛(-q/2 - √Δ) = " .. string.format("%.6f", v) })
        table.insert(steps, { description = "t₁ = u + v = " .. string.format("%.6f", t1) })

        local x1 = t1 - delta
        table.insert(steps, { description = "Real root: " .. var .. "₁ = t₁ - " .. delta .. " = " .. string.format("%.6f", x1) })

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
            table.insert(roots, { type = "number", value = x1 })
        end

        local real_part = (-t1/2) - delta
        local imag_part = math.sqrt(3)*(u - v)/2

        table.insert(steps, { description = "Complex roots: " .. var .. "₂,₃ = " .. string.format("%.6f", real_part) .. " ± " .. string.format("%.6f", imag_part) .. "i" })

        if _G.showComplex then
            local sqrt3 = { type = "func", name = "sqrt", args = { { type = "number", value = 3 } } }
            local symbolic_root2 = {
                type = "add",
                args = {
                    { type = "number", value = real_part },
                    {
                        type = "mul",
                        args = {
                            sqrt3,
                            { type = "number", value = (u - v) / 2 },
                            { type = "symbol", name = "i" }
                        }
                    }
                }
            }
            local symbolic_root3 = {
                type = "add",
                args = {
                    { type = "number", value = real_part },
                    {
                        type = "mul",
                        args = {
                            { type = "neg", arg = sqrt3 },
                            { type = "number", value = (u - v) / 2 },
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
        table.insert(steps, { description = "Since Δ = 0: repeated real roots" })
        
        local u = cbrt(-q/2)
        local t1 = 2*u
        local t2 = -u

        local x1 = t1 - delta
        local x2 = t2 - delta

        table.insert(steps, { description = "Using the double root formula:" })
        table.insert(steps, { description = "t₁ = 2∛(-q/2) = " .. string.format("%.6f", t1) })
        table.insert(steps, { description = "t₂ = -∛(-q/2) = " .. string.format("%.6f", t2) })

        local precision = _G.precision or _G.precision_digits or 4
        local function roundnum(x)
            local mult = 10 ^ precision
            return math.floor(x * mult + 0.5) / mult
        end

        x1 = roundnum(x1)
        x2 = roundnum(x2)

        if math.abs(x1 - x2) < 1e-10 then
            table.insert(steps, { description = "Triple root: " .. var .. " = " .. x1 .. " (multiplicity 3)" })
            table.insert(roots, { type = "number", value = x1 })
            table.insert(roots, { type = "number", value = x1 })
            table.insert(roots, { type = "number", value = x1 })
        else
            table.insert(steps, { description = "Roots: " .. var .. "₁ = " .. x1 .. ", " .. var .. "₂ = " .. var .. "₃ = " .. x2 .. " (double root)" })
            table.insert(roots, { type = "number", value = x1 })
            table.insert(roots, { type = "number", value = x2 })
            table.insert(roots, { type = "number", value = x2 })
        end

    else
        table.insert(steps, { description = "Since Δ < 0: three distinct real roots (casus irreducibilis)" })
        table.insert(steps, { description = "Using trigonometric solution method:" })
        
        local r = math.sqrt(-(p^3) / 27)
        local phi = math.acos(-q / (2 * math.sqrt(-(p^3)/27)))
        
        table.insert(steps, { description = "r = √(-(p³)/27) = " .. string.format("%.6f", r) })
        table.insert(steps, { description = "φ = arccos(-q/(2r)) = " .. string.format("%.6f", phi) })
        
        local t1 = 2 * math.sqrt(-p/3) * math.cos(phi / 3)
        local t2 = 2 * math.sqrt(-p/3) * math.cos((phi + 2*math.pi) / 3)
        local t3 = 2 * math.sqrt(-p/3) * math.cos((phi + 4*math.pi) / 3)
        
        local x1 = t1 - delta
        local x2 = t2 - delta
        local x3 = t3 - delta
        
        table.insert(steps, { description = "Three real roots:" })
        table.insert(steps, { description = var .. "₁ = " .. string.format("%.6f", x1) })
        table.insert(steps, { description = var .. "₂ = " .. string.format("%.6f", x2) })
        table.insert(steps, { description = var .. "₃ = " .. string.format("%.6f", x3) })
        
        table.insert(roots, { type = "number", value = x1 })
        table.insert(roots, { type = "number", value = x2 })
        table.insert(roots, { type = "number", value = x3 })
    end

    return roots
end

-- Quartic equation solver with steps
local function matchQuarticEq(eq, var, steps)
    if eq.type ~= "equation" then return nil end
    
    table.insert(steps, { description = "Solving quartic equation: " .. format_expr(eq) })
    
    local l, r = eq.left, eq.right
    local norm = { type = "sub", left = l, right = r }
    
    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "Rearranging to standard form: " .. format_expr(norm) .. " = 0" })
    end
    
    local coeffs = polyCoeffs(norm, var, nil, steps)
    if not coeffs then return nil end
    
    local a = coeffs[4] or 0
    local b = coeffs[3] or 0
    local c = coeffs[2] or 0
    local d = coeffs[1] or 0
    local e = coeffs[0] or 0
    
    if a == 0 then return nil end

    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "Standard quartic form: a" .. var .. "⁴ + b" .. var .. "³ + c" .. var .. "² + d" .. var .. " + e = 0" })
        table.insert(steps, { description = "Where a = " .. a .. ", b = " .. b .. ", c = " .. c .. ", d = " .. d .. ", e = " .. e })
    end

    -- Try factoring first
    local function try_quartic_factoring(a, b, c, d, e)
        if math.floor(a) ~= a or math.floor(b) ~= b or math.floor(c) ~= c or math.floor(d) ~= d or math.floor(e) ~= e then return nil end
        
        if a ~= 1 then
            b = b / a; c = c / a; d = d / a; e = e / a
        end
        
        for p = -10, 10 do for r = -10, 10 do
        for q = -10, 10 do for s = -10, 10 do
            if (p + r == b) and (q + p*r + s == c) and (p*s + q*r == d) and (q*s == e) then
                return {p=p, q=q, r=r, s=s}
            end
        end end end end
        return nil
    end

    local factors = try_quartic_factoring(a, b, c, d, e)
    if factors then
        table.insert(steps, { description = "Factored as: (" .. var .. "² + " .. factors.p .. var .. " + " .. factors.q .. ")(" .. var .. "² + " .. factors.r .. var .. " + " .. factors.s .. ") = 0" })
        table.insert(steps, { description = "Solving each quadratic factor separately:" })
        
        -- Create quadratic equations and solve them
        local quad1 = { 
            type="equation", 
            left={type="add", args={
                {type="pow", base={type="variable", name=var}, exp={type="number", value=2}},
                {type="mul", args={{type="number", value=factors.p}, {type="variable", name=var}}},
                {type="number", value=factors.q}
            }}, 
            right={type="number", value=0}
        }
        
        local quad2 = { 
            type="equation", 
            left={type="add", args={
                {type="pow", base={type="variable", name=var}, exp={type="number", value=2}},
                {type="mul", args={{type="number", value=factors.r}, {type="variable", name=var}}},
                {type="number", value=factors.s}
            }}, 
            right={type="number", value=0}
        }
        
        local roots1 = matchQuadraticEq(quad1, var, steps)
        local roots2 = matchQuadraticEq(quad2, var, steps)
        
        local all_roots = {}
        if roots1 then for _, rt in ipairs(roots1) do table.insert(all_roots, rt) end end
        if roots2 then for _, rt in ipairs(roots2) do table.insert(all_roots, rt) end end
        return all_roots
    end

    -- Ferrari's method
    table.insert(steps, { description = "Using Ferrari's method for quartic solution" })
    
    -- Normalize coefficients
    b = b / a
    c = c / a
    d = d / a
    e = e / a
    
    table.insert(steps, { description = "Dividing by leading coefficient: " .. var .. "⁴ + " .. b .. var .. "³ + " .. c .. var .. "² + " .. d .. var .. " + " .. e .. " = 0" })

    -- Depressed quartic
    local p = c - 3 * b^2 / 8
    local q = b^3 / 8 - b * c / 2 + d
    local r = e - 3 * b^4 / 256 + b^2 * c / 16 - b * d / 4
    
    table.insert(steps, { description = "Converting to depressed quartic using substitution " .. var .. " = y - b/4" })
    table.insert(steps, { description = "Depressed quartic: y⁴ + py² + qy + r = 0" })
    table.insert(steps, { description = "Where p = " .. string.format("%.6f", p) .. ", q = " .. string.format("%.6f", q) .. ", r = " .. string.format("%.6f", r) })

    -- Solve resolvent cubic
    table.insert(steps, { description = "Solving resolvent cubic: z³ + 2pz² + (p² - 4r)z - q² = 0" })
    
    local cubicA = 1
    local cubicB = 2 * p
    local cubicC = p^2 - 4 * r
    local cubicD = -q^2
    
    local cubicRoots = solveCubicReal(cubicA, cubicB, cubicC, cubicD)
    local z = cubicRoots[1]
    
    table.insert(steps, { description = "Using resolvent root z = " .. string.format("%.6f", z) })

    -- Ferrari's completion
    local sqrt1 = safe_sqrt(2 * z - p)
    local S1 = sqrt1
    
    local function div_complex(a, b)
        local a_re = type(a) == "table" and a.re or a
        local a_im = type(a) == "table" and (a.im or 0) or 0
        local b_re = type(b) == "table" and b.re or b
        local b_im = type(b) == "table" and (b.im or 0) or 0
        if b_im == 0 then
            if type(a) == "table" then
                return { re = a_re / b_re, im = a_im / b_re }
            else
                return a_re / b_re
            end
        end
        local denom = b_re^2 + b_im^2
        return {
            re = (a_re * b_re + a_im * b_im) / denom,
            im = (a_im * b_re - a_re * b_im) / denom
        }
    end
    
    local S2 = div_complex(q, type(sqrt1) == "table" and { re = 2 * (sqrt1.re or 0), im = 2 * (sqrt1.im or 0) } or (2 * sqrt1))

    table.insert(steps, { description = "Computing auxiliary values for Ferrari's method..." })

    -- The rest follows the complex arithmetic for quartic roots
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

    -- Complex arithmetic helpers (abbreviated for space)
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

    table.insert(steps, { description = "Four quartic roots computed using Ferrari's method" })

    if not _G.showComplex then
        local real_roots = {}
        for i, y in ipairs({y1, y2, y3, y4}) do
            if type(y) == "table" and (y.im and math.abs(y.im) > 1e-10) then
                -- skip complex root
            else
                local val = y
                if type(y) == "table" then val = y.re end
                table.insert(real_roots, format_root(val))
                table.insert(steps, { description = var .. " = " .. string.format("%.6f", val) })
            end
        end
        if #real_roots == 0 then
            table.insert(steps, { description = "All roots are complex (not displayed in real mode)" })
            return {"No real roots"}
        end
        return real_roots
    end

    table.insert(steps, { description = "Quartic solutions:" })
    for i, y in ipairs({y1, y2, y3, y4}) do
        if type(y) == "table" and y.im and y.im ~= 0 then
            table.insert(steps, { description = var .. "₊" .. i .. " = " .. string.format("%.6f", y.re) .. " + " .. string.format("%.6f", y.im) .. "i" })
        else
            local val = type(y) == "table" and y.re or y
            table.insert(steps, { description = var .. "₊" .. i .. " = " .. string.format("%.6f", val) })
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

-- Main solve function with intelligent step filtering
function solve(input_expr, var)
    local steps = {}
    
    table.insert(steps, { description = "Solving equation: " .. tostring(input_expr) })

    local parser = rawget(_G, "parser") or require("parser")
    local ast_mod = rawget(_G, "ast") or require("ast")
    local simplify = rawget(_G, "simplify") or require("simplify")

    local expr = input_expr
    if type(expr) == "string" then
        local s = expr
        s = s:gsub("(%d)(%a)", "%1*%2")
        s = s:gsub("(%d)(%()", "%1*%2")
        if not _G.suppress_basic_steps then
            table.insert(steps, { description = "Parsing: " .. s })
        end
        expr = parser.parse(s)
    end
    if not expr then
        error(errors.invalid("solve", "parse failed, got nil AST"))
    end

    var = var or (function()
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

    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "Variable to solve for: " .. var })
    end

    if expr.type == "equation" then
        expr = ast_mod.eq(expr.left, expr.right)
    elseif expr.type ~= "equation" then
        expr = ast_mod.eq(expr, ast_mod.number(0))
        if not _G.suppress_basic_steps then
            table.insert(steps, { description = "Converting to equation form: " .. format_expr(expr) })
        end
    end

    expr = simplify.simplify(expr)
    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "After simplification: " .. format_expr(expr) })
    end

    local diff = simplify.simplify(ast_mod.sub(expr.left, expr.right))
    local fallback_eq = ast_mod.eq(diff, ast_mod.number(0))

    -- Find polynomial degree and analyze complexity
    local coeffs = polyCoeffs(fallback_eq.left, var, nil, steps)
    local maxdeg = 0
    for d, _ in pairs(coeffs) do
        if d > maxdeg then maxdeg = d end
    end

    -- Analyze complexity before proceeding
    local complexity = analyzeComplexity(format_expr(expr), coeffs, maxdeg)
    
    -- Set suppression flag for basic steps based on complexity
    if complexity.is_trivial then
        _G.suppress_basic_steps = true
    end

    if not _G.suppress_basic_steps then
        table.insert(steps, { description = "Polynomial degree: " .. maxdeg })
    end

    local result, raw_steps
    
    if maxdeg == 1 then
        if not _G.suppress_basic_steps then
            table.insert(steps, { description = "This is a linear equation" })
        end
        local ans_lin = matchLinearEq(fallback_eq, var, steps)
        if ans_lin then
            local rhs
            if type(ans_lin) ~= "table" then
                rhs = ast_mod.number(ans_lin)
            else
                rhs = ans_lin
            end
            local eq_ast = ast_mod.eq(ast_mod.symbol(var), rhs)
            local simplified_eq = simplify.simplify(eq_ast)
            result = format_expr(simplified_eq)
            if simplified_eq and simplified_eq.type == "sub"
                and simplified_eq.left and simplified_eq.right
                and simplified_eq.left.type == "variable"
                and simplified_eq.right.type == "number" then
                result = simplified_eq.left.name .. " = " .. tostring(simplified_eq.right.value)
            end
            raw_steps = steps
        end
    elseif maxdeg == 2 then
        if not _G.suppress_basic_steps then
            table.insert(steps, { description = "This is a quadratic equation" })
        end
        local ans_quad = matchQuadraticEq(fallback_eq, var, steps)
        if ans_quad then
            local pieces = {}
            for i, root in ipairs(ans_quad) do
                table.insert(pieces, var .. " = " .. format_expr(root))
            end
            result = table.concat(pieces, ", ")
            raw_steps = steps
        end
    elseif maxdeg == 3 then
        if not _G.suppress_basic_steps then
            table.insert(steps, { description = "This is a cubic equation" })
        end
        local ans_cubic = matchCubicEq(fallback_eq, var, steps)
        if ans_cubic then
            local pieces = {}
            for i, root in ipairs(ans_cubic) do
                table.insert(pieces, var .. " = " .. format_expr(root))
            end
            result = table.concat(pieces, ", ")
            raw_steps = steps
        end
    elseif maxdeg == 4 then
        if not _G.suppress_basic_steps then
            table.insert(steps, { description = "This is a quartic equation" })
        end
        local ans_quartic = matchQuarticEq(fallback_eq, var, steps)
        if ans_quartic then
            local pieces = {}
            for i, root in ipairs(ans_quartic) do
                table.insert(pieces, var .. " = " .. format_expr(root))
            end
            result = table.concat(pieces, ", ")
            raw_steps = steps
        end
    end

    if not result then
        table.insert(steps, { description = "No analytical solution method available for this equation" })
        if _G.errors then
            error(_G.errors.get("solve(not_today_satan)") or "No analytical solution found")
        else
            return "No analytical solution found", steps
        end
    end

    -- Apply intelligent filtering
    local filtered_steps = filterSteps(raw_steps, complexity)
    
    -- Clean up global state
    _G.suppress_basic_steps = nil
    
    return result, filtered_steps
end

-- Export functions with steps support
_G.solve = solve
_G.polyCoeffs = polyCoeffs
_G.matchLinearEq = matchLinearEq
_G.matchQuadraticEq = matchQuadraticEq
_G.matchCubicEq = matchCubicEq
_G.matchQuarticEq = matchQuarticEq
_G.format_expr = format_expr
_G.analyzeComplexity = analyzeComplexity
_G.filterSteps = filterSteps