local simplify = {}



-- Helper: get precision from flag or default
local function get_precision()
    
    -- local prec = var and var.recall and var.recall("nLuaCAS_precision_pref")
    -- if type(prec) == "number" and prec >= 0 then return prec end
    return nil 
end

-- Helper: round to precision
local function round_to_precision(val, precision)
    local mult = 10 ^ (precision or 4)
    return math.floor(val * mult + 0.5) / mult
end
local ast = rawget(_G, "ast") or require("ast")
local parser = rawget(_G, "parser") or require("parser")

-- ===== UTILITY FUNCTIONS (The Boring But Essential Shit) =====

local function num(n) return {type="number", value=n} end
local function var(name) return {type="variable", name=name} end

local function is_num(e) return e and e.type == "number" end
local function is_var(e) return e and e.type == "variable" end
local function is_pow(e) return e and e.type == "pow" end
local function is_add(e) return e and e.type == "add" end
local function is_mul(e) return e and e.type == "mul" end
local function is_sin(e) return e and e.type == "sin" end
local function is_cos(e) return e and e.type == "cos" end
local function is_ln(e) return e and e.type == "ln" end
local function is_exp(e) return e and e.type == "exp" end

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k,v in pairs(t) do c[k] = deepcopy(v) end
    return c
end

-- ===== TENSOR MULTIPLICATION HELPER =====
local function tensor_multiply(t1, t2)
    if not (t1 and t1.type == "tensor" and t2 and t2.type == "tensor") then
        return nil
    end

    local function is_vector(t)
        for _, e in ipairs(t.elements) do
            if e.type == "tensor" then return false end
        end
        return true
    end

    local function is_matrix(t)
        for _, row in ipairs(t.elements) do
            if row.type ~= "tensor" then return false end
        end
        return true
    end

    if is_vector(t1) and is_vector(t2) then
        -- Dot product
        local sum = 0
        for i=1, math.min(#t1.elements, #t2.elements) do
            local e1, e2 = t1.elements[i], t2.elements[i]
            if e1.type == "number" and e2.type == "number" then
                sum = sum + e1.value * e2.value
            else
                return nil -- Non-numeric elements, bail
            end
        end
        return { type = "number", value = sum }
    elseif is_matrix(t1) and is_matrix(t2) then
        -- Matrix multiplication: (m x n) * (n x p)
        local m = #t1.elements
        local n = #t1.elements[1].elements
        local n2 = #t2.elements
        local p = #t2.elements[1].elements
        if n ~= n2 then return nil end

        local result = {}
        for i=1,m do
            local row = {}
            for j=1,p do
                local sum = 0
                for k=1,n do
                    local a = t1.elements[i].elements[k]
                    local b = t2.elements[k].elements[j]
                    if a.type == "number" and b.type == "number" then
                        sum = sum + a.value * b.value
                    else
                        return nil
                    end
                end
                table.insert(row, { type = "number", value = sum })
            end
            table.insert(result, { type = "tensor", elements = row })
        end
        return { type = "tensor", elements = result }
    elseif is_matrix(t1) and is_vector(t2) then
        -- Matrix * vector
        local m = #t1.elements
        local n = #t1.elements[1].elements
        local len = #t2.elements
        if n ~= len then return nil end

        local result = {}
        for i=1,m do
            local sum = 0
            for j=1,n do
                local a = t1.elements[i].elements[j]
                local b = t2.elements[j]
                if a.type == "number" and b.type == "number" then
                    sum = sum + a.value * b.value
                else
                    return nil
                end
            end
            table.insert(result, { type = "number", value = sum })
        end
        return { type = "tensor", elements = result }
    else
        return nil -- Unsupported tensor shapes
    end
end

-- Helper: pretty print AST nodes for debugging (recursive)
local function ast_to_string(node, visited, depth)
    visited = visited or {}
    depth = depth or 0
    local indent = string.rep("  ", depth)
    if type(node) ~= "table" then
        return tostring(node)
    end
    if visited[node] then
        return indent .. "<cycle>"
    end
    visited[node] = true
    local parts = {}
    table.insert(parts, indent .. "{")
    for k, v in pairs(node) do
        local keystr = tostring(k)
        if type(v) == "table" then
            table.insert(parts, indent .. "  " .. keystr .. " = " .. ast_to_string(v, visited, depth + 1))
        else
            table.insert(parts, indent .. "  " .. keystr .. " = " .. tostring(v))
        end
    end
    table.insert(parts, indent .. "}")
    return table.concat(parts, "\n")
end

-- Simple hash for expression comparison
local function expr_hash(expr)
    if type(expr) ~= "table" then return tostring(expr) end
    
    local parts = {expr.type}
    if expr.type == "number" then
        table.insert(parts, tostring(expr.value))
    elseif expr.type == "variable" then
        table.insert(parts, expr.name)
    elseif expr.type == "pow" then
        table.insert(parts, expr_hash(expr.base))
        table.insert(parts, expr_hash(expr.exp))
    elseif expr.type == "sin" or expr.type == "cos" or expr.type == "ln" or expr.type == "exp" then
        table.insert(parts, expr_hash(expr.arg))
    elseif (expr.type == "add" or expr.type == "mul") and expr.args then
        local arg_hashes = {}
        for _, arg in ipairs(expr.args) do
            table.insert(arg_hashes, expr_hash(arg))
        end
        table.sort(arg_hashes) -- Commutative operations
        for _, hash in ipairs(arg_hashes) do
            table.insert(parts, hash)
        end
    end
    
    return table.concat(parts, "|")
end

local function expr_equal(a, b)
    return expr_hash(a) == expr_hash(b)
end

-- ===== STEP 1: FLATTEN ASSOCIATIVE OPERATIONS =====
-- Because nested additions/multiplications are the devil

local function flatten(expr)
    if not (is_add(expr) or is_mul(expr)) or not expr.args then return expr end
    
    local flattened = {}
    local op_type = expr.type
    
    local function collect_args(e)
        if e.type == op_type and e.args then
            for _, arg in ipairs(e.args) do
                collect_args(arg)
            end
        else
            table.insert(flattened, e)
        end
    end
    
    for _, arg in ipairs(expr.args) do
        collect_args(arg)
    end
    
    return {type = op_type, args = flattened}
end

-- ===== STEP 2: SORT ARGUMENTS FOR COMMUTATIVITY =====
-- Because order matters for consistency, not math

local function get_power_of_var(expr, var_name)
    -- Return exponent if expr is base^exp where base is var_name
    if expr.type == "pow" and expr.base.type == "variable" and expr.base.name == var_name then
        if expr.exp.type == "number" then
            return expr.exp.value
        end
    elseif expr.type == "variable" and expr.name == var_name then
        return 1
    elseif expr.type == "number" then
        return 0
    end
    return nil -- Cannot determine power
end

local function sort_args(expr)
    if not ((expr.type == "add" or expr.type == "mul") and expr.args) then return expr end
    
    local sorted_args = deepcopy(expr.args)
    -- If addition, try to sort by power of x ascending
    if expr.type == "add" then
        table.sort(sorted_args, function(a, b)
            local a_pow = get_power_of_var(a, "x")
            local b_pow = get_power_of_var(b, "x")
            if a_pow and b_pow then
                return a_pow < b_pow
            elseif a_pow then
                return true
            elseif b_pow then
                return false
            else
                return expr_hash(a) < expr_hash(b)
            end
        end)
    else
        -- For multiplication, keep original expr_hash sorting
        table.sort(sorted_args, function(a, b)
            return expr_hash(a) < expr_hash(b)
        end)
    end
    
    return {type = expr.type, args = sorted_args}
end

-- ===== STEP 3: CONSTANT FOLDING (The Easy Wins) =====

-- fold_constants: The Elegant Edition


local function fold_constants(expr)
    if not expr or type(expr) ~= "table" then return expr end
    if expr.type == "<unknown>" then return expr end

    -- Helper: create a number node (because apparently this needs to be a function)
    local function make_num(val)
        return { type = "number", value = val }
    end

    -- Helper: round number to current precision if needed
    local function round_number_if_needed(expr)
        if expr and expr.type == "number" then
            local p = get_precision()
            if p and p >= 0 then
                return { type = "number", value = round_to_precision(expr.value, p) }
            end
        end
        return expr
    end

    -- Helper: extract numeric value from node, handling negation gracefully
    local function extract_numeric_value(node)
        if node.type == "number" then
            return node.value, true
        elseif node.type == "neg" then
            local inner = node.arg or node.value
            if inner and inner.type == "number" then
                return -inner.value, true
            end
        end
        return nil, false
    end

    -- Handle addition: collect numbers, preserve everything else
    if expr.type == "add" and expr.args then
        local numeric_sum = 0
        local non_numeric_terms = {}
        local found_numbers = false

        for _, term in ipairs(expr.args) do
            local folded_term = fold_constants(term)
            local numeric_val, is_numeric = extract_numeric_value(folded_term)
            
            if is_numeric then
                numeric_sum = numeric_sum + numeric_val
                found_numbers = true
            else
                table.insert(non_numeric_terms, folded_term)
            end
        end

        -- Assemble the result with mathematical dignity
        local result_terms = {}
        if found_numbers and numeric_sum ~= 0 then
            table.insert(result_terms, make_num(numeric_sum))
        end
        for _, term in ipairs(non_numeric_terms) do
            table.insert(result_terms, term)
        end

        -- Return the most elegant representation
        if #result_terms == 0 then return round_number_if_needed(make_num(0)) end
        if #result_terms == 1 then return round_number_if_needed(result_terms[1]) end
        return { type = "add", args = result_terms }
    end

    -- Handle multiplication: the source of discriminant trauma
    if expr.type == "mul" and expr.args then
        local numeric_product = 1
        local non_numeric_factors = {}
        local found_numbers = false

        for _, factor in ipairs(expr.args) do
            local folded_factor = fold_constants(factor)
            local numeric_val, is_numeric = extract_numeric_value(folded_factor)
            
            if is_numeric then
                numeric_product = numeric_product * numeric_val
                found_numbers = true
            else
                table.insert(non_numeric_factors, folded_factor)
            end
        end

        -- PATCH: Distribute numeric factors over negations
        local patched_factors = {}
        for _, factor in ipairs(non_numeric_factors) do
            if factor.type == "neg" and factor.arg then
                -- Distribute all previous numeric_product into the negation
                table.insert(patched_factors, {type = "mul", args = {{type="number", value = -1 * numeric_product}, fold_constants(factor.arg)}})
                numeric_product = 1
                found_numbers = false
            else
                table.insert(patched_factors, factor)
            end
        end
        non_numeric_factors = patched_factors

        -- Handle the mathematical realities
        if numeric_product == 0 then return round_number_if_needed(make_num(0)) end

        -- Assemble result with appropriate elegance
        local result_factors = {}
        if found_numbers and (numeric_product ~= 1 or #non_numeric_factors == 0) then
            table.insert(result_factors, make_num(numeric_product))
        end
        for _, factor in ipairs(non_numeric_factors) do
            table.insert(result_factors, factor)
        end

        if #result_factors == 0 then return round_number_if_needed(make_num(1)) end
        if #result_factors == 1 then return round_number_if_needed(result_factors[1]) end
        return { type = "mul", args = result_factors }
    end

    -- Handle subtraction: where quadratic dreams go to die
    if expr.type == "sub" and expr.left and expr.right then
        local left = fold_constants(expr.left)
        local right = fold_constants(expr.right)

        -- Extract numeric values for direct computation
        local left_val, left_is_num = extract_numeric_value(left)
        local right_val, right_is_num = extract_numeric_value(right)

        -- Handle pure numeric subtraction
        if left_is_num and right_is_num then
            return round_number_if_needed(make_num(left_val - right_val))
        end

        -- Handle subtraction of negative: a - (-b) = a + b
        if right.type == "neg" then
            local right_inner = right.arg or right.value
            return fold_constants({ type = "add", args = { left, right_inner } })
        end

        -- Handle special case: 0 - x = -x
        if left_is_num and left_val == 0 then
            return fold_constants({ type = "neg", arg = right })
        end

        -- Handle special case: x - 0 = x
        if right_is_num and right_val == 0 then
            return round_number_if_needed(left)
        end

        return { type = "sub", left = left, right = right }
    end

    -- Handle division: because completeness matters
    if expr.type == "div" and expr.left and expr.right then
        local left = fold_constants(expr.left)
        local right = fold_constants(expr.right)

        local left_val, left_is_num = extract_numeric_value(left)
        local right_val, right_is_num = extract_numeric_value(right)

        if left_is_num and right_is_num and right_val ~= 0 then
            return round_number_if_needed(make_num(left_val / right_val))
        end

        -- x / 1 = x
        if right_is_num and right_val == 1 then
            return round_number_if_needed(left)
        end

        -- 0 / x = 0 (assuming x ≠ 0)
        if left_is_num and left_val == 0 then
            return round_number_if_needed(make_num(0))
        end

        return { type = "div", left = left, right = right }
    end

    -- Handle powers: because the quadratic formula demands it
    if expr.type == "pow" then
        local base = fold_constants(expr.base or expr.left)
        local exp = fold_constants(expr.exp or expr.right)

        local base_val, base_is_num = extract_numeric_value(base)
        local exp_val, exp_is_num = extract_numeric_value(exp)

        -- Simplify i^2 = -1
        if base.type == "symbol" and base.name == "i" and exp_is_num and exp_val == 2 then
            return round_number_if_needed(make_num(-1))
        end

        -- Handle numeric powers
        if base_is_num and exp_is_num and not _G.showComplex then
            -- Special cases to avoid numerical disasters
            if base_val == 0 and exp_val > 0 then return round_number_if_needed(make_num(0)) end
            if base_val == 0 and exp_val == 0 then return round_number_if_needed(make_num(1)) end
            if exp_val == 0 then return round_number_if_needed(make_num(1)) end
            if exp_val == 1 then return round_number_if_needed(base) end
            return round_number_if_needed(make_num(base_val ^ exp_val))
        end

        -- x^0 = 1
        if exp_is_num and exp_val == 0 then
            return round_number_if_needed(make_num(1))
        end

        -- x^1 = x
        if exp_is_num and exp_val == 1 then
            return round_number_if_needed(base)
        end

        -- 0^x = 0 (for positive x)
        if base_is_num and base_val == 0 then
            return round_number_if_needed(make_num(0))
        end

        -- 1^x = 1
        if base_is_num and base_val == 1 then
            return round_number_if_needed(make_num(1))
        end

        return { type = "pow", base = base, exp = exp }
    end

    -- Handle negation: with proper respect for double negatives
    if expr.type == "neg" then
        local inner = fold_constants(expr.arg or expr.value)
        local inner_val, inner_is_num = extract_numeric_value(inner)

        if inner_is_num then
            return round_number_if_needed(make_num(-inner_val))
        end

        -- Handle double negation: -(-x) = x
        if inner.type == "neg" then
            return fold_constants(inner.arg or inner.value)
        end

        return { type = "neg", arg = inner }
    end

    -- Handle functions: sqrt, sin, cos, etc.
    if expr.type == "func" and expr.args then
        local folded_args = {}
        local all_numeric = true
        
        for i, arg in ipairs(expr.args) do
            folded_args[i] = fold_constants(arg)
            if not extract_numeric_value(folded_args[i]) then
                all_numeric = false
            end
        end

        -- Handle sqrt of numeric values, including sqrt(-1) = i
        if expr.name == "sqrt" and #folded_args == 1 then
            local val, is_num = extract_numeric_value(folded_args[1])
            if is_num then
                if val >= 0 and not _G.showComplex then
                    return round_number_if_needed(make_num(math.sqrt(val)))
                elseif val == -1 then
                    return { type = "symbol", name = "i" }
                end
            end
        end

        -- Handle root(n, x) = x^(1/n)
        if expr.name == "root" and #folded_args == 2 then
            return {
                type = "pow",
                base = folded_args[2],
                exp = { type = "div", left = make_num(1), right = folded_args[1] }
            }
        end

        return { type = "func", name = expr.name, args = folded_args }
    end

    -- For everything else, recursively fold children
    local result = {}
    for k, v in pairs(expr) do
        if type(v) == "table" and k ~= "args" then
            result[k] = fold_constants(v)
        else
            result[k] = v
        end
    end

    -- At the end, round number if needed
    if result and result.type == "number" then
        result = round_number_if_needed(result)
    end
    return result
end

-- Helper: recursively simplify children before folding constants
local function fold_constants_recursive(expr)
    if type(expr) ~= "table" then return expr end
    -- Recursively process children
    local new_expr = deepcopy(expr)
    if is_num(new_expr) and new_expr.value == 0 then
        new_expr.value = 0  -- Normalize any -0 to 0
    end
    if new_expr.type == "pow" then
        new_expr.base = fold_constants_recursive(new_expr.base)
        new_expr.exp = fold_constants_recursive(new_expr.exp)
    elseif new_expr.type == "sin" or new_expr.type == "cos" or new_expr.type == "ln" or new_expr.type == "exp" then
        new_expr.arg = fold_constants_recursive(new_expr.arg)
    elseif (new_expr.type == "add" or new_expr.type == "mul") and new_expr.args then
        for i = 1, #new_expr.args do
            new_expr.args[i] = fold_constants_recursive(new_expr.args[i])
        end
    elseif new_expr.type == "func" and new_expr.args then
        for i = 1, #new_expr.args do
            new_expr.args[i] = fold_constants_recursive(new_expr.args[i])
        end
    elseif new_expr.type == "neg" and new_expr.arg then
        new_expr.arg = fold_constants_recursive(new_expr.arg)
    elseif new_expr.type == "sub" and new_expr.left and new_expr.right then
        new_expr.left = fold_constants_recursive(new_expr.left)
        new_expr.right = fold_constants_recursive(new_expr.right)
    end
    return fold_constants(new_expr)
end

-- ===== STEP 4: COLLECT LIKE TERMS (The Real Work) =====

local function extract_coefficient_and_base(expr)
    if is_num(expr) then
        return expr.value, num(1)
    end
    
    if is_mul(expr) and expr.args then
        local coeff = 1
        local base_parts = {}
        
        for _, arg in ipairs(expr.args) do
            if is_num(arg) then
                coeff = coeff * arg.value
            else
                table.insert(base_parts, arg)
            end
        end
        
        local base
        if #base_parts == 0 then
            base = num(1)
        elseif #base_parts == 1 then
            base = base_parts[1]
        else
            base = {type = "mul", args = base_parts}
        end
        
        return coeff, base
    end
    
    return 1, expr
end

local function collect_like_terms(expr)
    if not (is_add(expr) and expr.args) then return expr end

    local groups = {}

    for _, term in ipairs(expr.args) do
        local t = term
        local sign = 1
        if t.type == "neg" then
            t = t.arg or t.value
            sign = -1
        end
        local coeff, base = extract_coefficient_and_base(t)
        coeff = coeff * sign
        local base_key = expr_hash(base)

        if groups[base_key] then
            groups[base_key].coeff = groups[base_key].coeff + coeff
        else
            groups[base_key] = {coeff = coeff, base = base}
        end
    end

    local result_terms = {}
    for _, group in pairs(groups) do
        if math.abs(group.coeff) > 1e-10 then -- Handle floating point errors
            if math.abs(group.coeff - 1) < 1e-10 and not expr_equal(group.base, num(1)) then
                -- Coefficient is 1, just use base
                table.insert(result_terms, group.base)
            elseif expr_equal(group.base, num(1)) then
                -- Base is 1, just use coefficient
                table.insert(result_terms, num(group.coeff))
            else
                -- Both matter
                table.insert(result_terms, {type = "mul", args = {num(group.coeff), group.base}})
            end
        end
    end

    if #result_terms == 0 then return num(0) end
    if #result_terms == 1 then return result_terms[1] end
    return {type = "add", args = result_terms}
end

-- ===== STEP 5: POWER SIMPLIFICATION =====

local function simplify_powers(expr)
    -- x^0 = 1
    if is_pow(expr) and is_num(expr.exp) and expr.exp.value == 0 then
        return num(1)
    end
    
    -- x^1 = x
    if is_pow(expr) and is_num(expr.exp) and expr.exp.value == 1 then
        return expr.base
    end
    
    -- (x^a)^b = x^(a*b)
    if is_pow(expr) and is_pow(expr.base) then
        local new_exp = {type = "mul", args = {expr.base.exp, expr.exp}}
        return {type = "pow", base = expr.base.base, exp = new_exp}
    end
    
    return expr
end

-- ===== STEP 6: COMBINE LIKE POWERS IN MULTIPLICATION =====

local function combine_powers(expr)
    if not (is_mul(expr) and expr.args) then return expr end

    local base_groups = {}
    local other_factors = {}

    for _, factor in ipairs(expr.args) do
        local base, exp
        if is_pow(factor) then
            base, exp = factor.base, factor.exp
        else
            base, exp = factor, num(1)
        end

        -- Guard: Skip exponent combination for tensors
        if base.type == "tensor" then
            table.insert(other_factors, factor)
        else
            local base_key = expr_hash(base)
            if base_groups[base_key] then
                -- Combine exponents: x^a * x^b = x^(a+b)
                base_groups[base_key].exponents = base_groups[base_key].exponents or {}
                table.insert(base_groups[base_key].exponents, exp)
            else
                base_groups[base_key] = {base = base, exponents = {exp}}
            end
        end
    end

    local result_factors = {}

    for _, group in pairs(base_groups) do
        if #group.exponents == 1 then
            if expr_equal(group.exponents[1], num(1)) then
                table.insert(result_factors, group.base)
            else
                table.insert(result_factors, {type = "pow", base = group.base, exp = group.exponents[1]})
            end
        else
            local combined_exp = {type = "add", args = group.exponents}
            table.insert(result_factors, {type = "pow", base = group.base, exp = combined_exp})
        end
    end

    -- Append the other factors (e.g., tensors) that were skipped for exponent combination
    for _, f in ipairs(other_factors) do
        table.insert(result_factors, f)
    end

    if #result_factors == 0 then return num(1) end
    if #result_factors == 1 then return result_factors[1] end
    return {type = "mul", args = result_factors}
end

-- ===== STEP 7: BASIC DISTRIBUTION =====

local function distribute_simple(expr)
    if not (is_mul(expr) and expr.args) then return expr end
    
    -- Look for a(b + c) pattern
    local additions = {}
    local other_factors = {}
    
    for _, factor in ipairs(expr.args) do
        if is_add(factor) and factor.args then
            table.insert(additions, factor)
        else
            table.insert(other_factors, factor)
        end
    end
    
    if #additions == 0 then return expr end
    
    -- Take first addition and distribute other factors into it
    local first_add = additions[1]
    local remaining_adds = {}
    for i = 2, #additions do
        table.insert(remaining_adds, additions[i])
    end
    
    local all_other_factors = {}
    for _, f in ipairs(other_factors) do
        table.insert(all_other_factors, f)
    end
    for _, f in ipairs(remaining_adds) do
        table.insert(all_other_factors, f)
    end
    
    local distributed_terms = {}
    for _, addend in ipairs(first_add.args) do
        local new_factors = {addend}
        for _, factor in ipairs(all_other_factors) do
            table.insert(new_factors, factor)
        end
        
        if #new_factors == 1 then
            table.insert(distributed_terms, new_factors[1])
        else
            table.insert(distributed_terms, {type = "mul", args = new_factors})
        end
    end
    
    return {type = "add", args = distributed_terms}
end

-- ===== STEP 8: SPECIAL EXPANSIONS =====

local function expand_special_cases(expr)
    -- (a + b)^2 = a^2 + 2ab + b^2
    if is_pow(expr) and is_num(expr.exp) and expr.exp.value == 2 then
        if is_add(expr.base) and expr.base.args and #expr.base.args == 2 then
            local a, b = expr.base.args[1], expr.base.args[2]
            return {
                type = "add",
                args = {
                    {type = "pow", base = a, exp = num(2)},
                    {type = "mul", args = {num(2), a, b}},
                    {type = "pow", base = b, exp = num(2)}
                }
            }
        end
    end
    
    return expr
end

-- ===== STEP 9: TRIGONOMETRIC IDENTITIES =====

local function apply_trig_identities(expr)
    -- sin^2(x) + cos^2(x) = 1
    if is_add(expr) and expr.args and #expr.args == 2 then
        local term1, term2 = expr.args[1], expr.args[2]
        
        -- Check if we have sin^2(x) and cos^2(x)
        if is_pow(term1) and is_pow(term2) and 
           is_num(term1.exp) and is_num(term2.exp) and
           term1.exp.value == 2 and term2.exp.value == 2 then
            
            if is_sin(term1.base) and is_cos(term2.base) and
               expr_equal(term1.base.arg, term2.base.arg) then
                return num(1)
            elseif is_cos(term1.base) and is_sin(term2.base) and
                   expr_equal(term1.base.arg, term2.base.arg) then
                return num(1)
            end
        end
    end
    
    return expr
end

-- ===== STEP 10: LOGARITHM IDENTITIES =====

local function apply_log_identities(expr)
    -- ln(e^x) = x
    if is_ln(expr) and is_exp(expr.arg) then
        return expr.arg.arg
    end
    
    -- e^(ln(x)) = x
    if is_exp(expr) and is_ln(expr.arg) then
        return expr.arg.arg
    end
    
    return expr
end

-- ===== MAIN SIMPLIFICATION ENGINE =====

-- Helper function to serialize AST nodes for debugging
local function ast_to_string(node, visited, depth)
    visited = visited or {}
    depth = depth or 0
    local indent = string.rep("  ", depth)
    if type(node) ~= "table" then
        return tostring(node)
    end
    if visited[node] then
        return indent .. "<cycle>"
    end
    visited[node] = true
    local parts = {}
    table.insert(parts, indent .. "{")
    for k, v in pairs(node) do
        local keystr = tostring(k)
        if type(v) == "table" then
            table.insert(parts, indent .. "  " .. keystr .. " = " .. ast_to_string(v, visited, depth + 1))
        else
            table.insert(parts, indent .. "  " .. keystr .. " = " .. tostring(v))
        end
    end
    table.insert(parts, indent .. "}")
    return table.concat(parts, "\n")
end


-- Save original simplify_step
local old_simplify_step = simplify.simplify_step or function(expr) return expr end

-- Override simplify_step to add tensor mul support
function simplify.simplify_step(expr)
    -- Tensor multiplication (dot/matrix product)
    if type(expr) == "table" and expr.type == "mul" and expr.args and #expr.args == 2 then
        local a, b = expr.args[1], expr.args[2]
        if a.type == "tensor" and b.type == "tensor" then
            local prod = tensor_multiply(a, b)
            if prod then
                if prod.type == "number" then
                    return prod
                end
                -- Recursively simplify the product result
                return simplify.simplify_step(prod)
            end
        end
    end

    -- Scalar-Tensor element-wise multiplication
    if type(expr) == "table" and expr.type == "mul" and expr.args and #expr.args == 2 then
        local a, b = expr.args[1], expr.args[2]
        if is_num(a) and b.type == "tensor" then
            local scaled = {}
            for i, e in ipairs(b.elements) do
                if e.type == "number" then
                    scaled[i] = { type = "number", value = a.value * e.value }
                else
                    return expr
                end
            end
            return { type = "tensor", elements = scaled }
        elseif a.type == "tensor" and is_num(b) then
            local scaled = {}
            for i, e in ipairs(a.elements) do
                if e.type == "number" then
                    scaled[i] = { type = "number", value = e.value * b.value }
                else
                    return expr
                end
            end
            return { type = "tensor", elements = scaled }
        end
    end

    -- Tensor addition or subtraction (element-wise for exactly two tensors)
    if type(expr) == "table" and expr.type == "add" and expr.args then
        local tensors = {}
        for _, arg in ipairs(expr.args) do
            if arg.type == "tensor" then
                table.insert(tensors, arg)
            else
                return expr -- Non-tensor terms present, skip
            end
        end
        if #tensors == 2 then
            local a, b = tensors[1], tensors[2]
            if #a.elements ~= #b.elements then return expr end
            local sum_elements = {}
            for i = 1, #a.elements do
                if a.elements[i].type == "number" and b.elements[i].type == "number" then
                    sum_elements[i] = { type = "number", value = a.elements[i].value + b.elements[i].value }
                else
                    return expr
                end
            end
            return { type = "tensor", elements = sum_elements }
        elseif #tensors > 2 then
            return expr -- Skip multi-term tensor sums for now
        end
    end

    -- Tensor subtraction with recursive simplification
    if type(expr) == "table" and expr.type == "sub" and expr.left and expr.right then
        local a = simplify.simplify_step(expr.left)
        local b = simplify.simplify_step(expr.right)
        if a.type == "tensor" and b.type == "tensor" then
            if #a.elements ~= #b.elements then return expr end
            local diff_elements = {}
            for i = 1, #a.elements do
                if a.elements[i].type == "number" and b.elements[i].type == "number" then
                    diff_elements[i] = { type = "number", value = a.elements[i].value - b.elements[i].value }
                else
                    return expr
                end
            end
            return { type = "tensor", elements = diff_elements }
        end
    end

    -- Tensor division: tensor / tensor reduces to scalar 1 if dot product nonzero
    if type(expr) == "table" and expr.type == "mul" and expr.args and #expr.args == 2 then
        local a, b = expr.args[1], expr.args[2]
        if is_pow(a) and a.base.type == "tensor" and is_num(a.exp) and a.exp.value == -1 and b.type == "tensor" then
            local prod = tensor_multiply(a.base, b)
            if prod and prod.type == "number" then
                if prod.value ~= 0 then
                    return { type = "number", value = 1 }
                else
                    return { type = "number", value = 0 }
                end
            end
        end
    end

    -- Tensor exponentiation: restrict to scalar exponents, handle positive integers
    if type(expr) == "table" and expr.type == "pow" and expr.base and expr.exp then
        if expr.base.type == "tensor" and is_num(expr.exp) then
            local k = expr.exp.value
            if k == -1 then
                return { type = "pow", base = expr.base, exp = { type = "number", value = -1 } }
            elseif k >= 1 and math.floor(k) == k then
                local result = expr.base
                for _ = 2, k do
                    result = tensor_multiply(result, expr.base) or expr
                end
                return result
            end
        end
    end

    ----------------------------------------------------------------------
    -- Automatic evaluation for numeric factorial
    if type(expr) == "table" and expr.type == "func" and expr.name == "factorial" and expr.args and #expr.args == 1 then
        local arg = simplify.simplify_step(expr.args[1])
        if arg.type == "number" and _G.evaluateFactorial then
            return { type = "number", value = _G.evaluateFactorial(arg.value) }
        end
        expr.args[1] = arg
        return expr
    end

    -- Automatic evaluation for integral (debug-enhanced version)
    if type(expr) == "table" and expr.type == "func" and expr.name == "int" and expr.args and #expr.args == 2 then
        print("Simplifying integral: ", simplify.pretty_print(expr))

        local inner = simplify.simplify_step(expr.args[1])
        local respect_to = simplify.simplify_step(expr.args[2])

        print("Inner after simplify: ", simplify.pretty_print(inner))
        print("Respect to after simplify: ", simplify.pretty_print(respect_to))

        if respect_to.type == "variable" and _G.integrate and _G.integrate.integrateAST then
            print("Calling _G.integrate.integrateAST with:")
            print("Inner: ", simplify.pretty_print(inner))
            print("Respect to: ", respect_to.name)
            local status, val = pcall(_G.integrate.integrateAST, inner, respect_to.name)
            print("Integration status: ", status)
            if status and type(val) == "table" then
                print("Integration result: ", simplify.pretty_print(val))
                return simplify.simplify_step(val)
            else
                print("Integration failed or returned non-table, val = ", val)
            end
        else
            print("Skipping integral: invalid respect_to or integrateAST missing")
        end

        expr.args[1] = inner
        expr.args[2] = respect_to
        return expr
    end
    ----------------------------------------------------------------------

    -- Fall back to original simplify_step
    return old_simplify_step(expr)
end

-- Original recursive simplify_step for internal use
local function simplify_step(expr)
    if type(expr) ~= "table" then return expr end
    if expr.type == "<unknown>" then
        print("Warning: encountered unknown AST node during simplification")
        return expr
    end
    -- Handle tensor AST node type (recursive for arbitrary depth)
    if expr.type == "tensor" and expr.elements then
        local function simplify_tensor_elements(elems)
            local simplified = {}
            for i, elem in ipairs(elems) do
                if type(elem) == "table" and elem.type == "tensor" and elem.elements then
                    simplified[i] = { type = "tensor", elements = simplify_tensor_elements(elem.elements) }
                else
                    simplified[i] = simplify_step(elem)
                end
            end
            return simplified
        end
        return { type = "tensor", elements = simplify_tensor_elements(expr.elements) }
    end

    -- Handle equation normalization: move right to left (left - right = 0)
    if expr.type == "equation" and expr.left and expr.right then
        local sub_expr = { type = "sub", left = expr.left, right = expr.right, _from_equation = true }
        return simplify_step(sub_expr)
    end

    -- Recursively simplify children first
    local new_expr = deepcopy(expr)

    -- Preserve subtraction by zero if part of an equation during solve
    if new_expr.type == "sub" and is_num(new_expr.right) and new_expr.right.value == 0 then
        if new_expr._from_equation then
            return new_expr
        else
            return simplify_step(new_expr.left)
        end
    end

    -- Only simplify known types; preserve unknown types
    local known_types = {
        number = true, variable = true, constant = true, pow = true, add = true, mul = true,
        sin = true, cos = true, ln = true, exp = true, integral = true, func = true, neg = true,
        series = true, sub = true, div = true
    }
    if not known_types[new_expr.type] then
        return new_expr
    end

    if new_expr.type == "pow" then
        new_expr.base = simplify_step(new_expr.base)
        new_expr.exp = simplify_step(new_expr.exp)
    elseif new_expr.type == "sin" or new_expr.type == "cos" or new_expr.type == "ln" or new_expr.type == "exp" then
        new_expr.arg = simplify_step(new_expr.arg)
    elseif (new_expr.type == "add" or new_expr.type == "mul") and new_expr.args then
        for i = 1, #new_expr.args do
            new_expr.args[i] = simplify_step(new_expr.args[i])
        end
    elseif new_expr.type == "neg" then
        local val_field = new_expr.arg or new_expr.value
        val_field = simplify_step(val_field)
        if val_field.type == "neg" then
            return simplify_step(val_field.arg or val_field.value)
        end
        new_expr.arg = val_field
        new_expr.value = nil
    elseif new_expr.type == "constant" then
        new_expr.value = simplify_step(new_expr.value)
        return new_expr.value
    end

    new_expr = flatten(new_expr)
    new_expr = sort_args(new_expr)
    new_expr = fold_constants_recursive(new_expr)
    new_expr = collect_like_terms(new_expr)
    new_expr = simplify_powers(new_expr)
    new_expr = combine_powers(new_expr)
    new_expr = distribute_simple(new_expr)
    new_expr = expand_special_cases(new_expr)
    new_expr = apply_trig_identities(new_expr)
    new_expr = apply_log_identities(new_expr)

    return new_expr
end

local function simplify_until_stable(expr, max_iterations)
    max_iterations = max_iterations or 20
    local iteration = 0
    local prev_hash = nil
    
    while iteration < max_iterations do
        expr = simplify_step(expr)
        local current_hash = expr_hash(expr)
        
        if current_hash == prev_hash then
            break -- Converged
        end
        
        prev_hash = current_hash
        iteration = iteration + 1
    end
    
    return expr
end

-- ===== PRETTY PRINTER =====

-- Improved precedence-aware parentheses logic
local function needs_parens(expr, parent_op, position)
    -- Precedence: higher number = binds tighter
    local precedence = {
        add = 1,
        sub = 1,
        mul = 2,
        div = 2,
        pow = 3,
        neg = 4,
        func = 5,
        sin = 5,
        cos = 5,
        ln = 5,
        exp = 5,
        sqrt = 5,
    }
    local expr_prec = precedence[expr.type] or 6
    local parent_prec = precedence[parent_op] or 0
    if not parent_op then return false end
    if expr_prec > parent_prec then return false end
    if expr_prec < parent_prec then return true end
    -- When precedence is equal, only pow is right-associative
    if parent_op == "pow" and position == "right" then return true end
    -- For subtraction and division, left and right children may need parens for clarity
    if (parent_op == "sub" or parent_op == "div") and position == "right" then return true end
    return false
end

-- Helper: should multiplication be shown as explicit * ?
local function should_show_multiplication(left, right)
    -- Omit * when: number followed by variable/power, variable by variable/power, power by variable/power, sqrt by variable/number/etc.
    local function is_sqrt(e)
        return e and (e.type == "sqrt" or (is_pow(e) and is_num(e.exp) and e.exp.value == 0.5))
    end
    if is_num(left) and (is_var(right) or is_pow(right) or is_sqrt(right)) then return false end
    if is_var(left) and (is_var(right) or is_pow(right) or is_sqrt(right)) then return false end
    if is_pow(left) and (is_var(right) or is_pow(right) or is_sqrt(right)) then return false end
    if is_sqrt(left) and (is_var(right) or is_num(right) or is_pow(right) or is_sqrt(right)) then return false end
    -- Omit * between closing paren and variable/number
    if left.type == "constant" and (is_var(right) or is_num(right)) then return false end
    return true
end

-- Helper: is a simple factor (number, variable, constant, or function call)
local function is_simple_factor(expr)
    return is_num(expr) or is_var(expr) or expr.type == "constant"
        or expr.type == "sin" or expr.type == "cos" or expr.type == "ln" or expr.type == "exp"
        or expr.type == "sqrt"
        or (expr.type == "func" and expr.name and expr.args)
end

local function pretty_print_internal(expr, parent_op, position)
    if not expr then return "<nil>" end

    if expr.type == "solutions" and expr.solutions then
        local parts = {}
        for i, sol in ipairs(expr.solutions) do
            local sol_str = pretty_print_internal(sol, nil, nil)
            table.insert(parts, "Solution " .. i .. ": " .. sol_str)
        end
        return table.concat(parts, "\n")
    end
    -- Numbers
    if is_num(expr) then
        if expr.value >= 0 then
            return tostring(expr.value)
        else
            return "(" .. tostring(expr.value) .. ")"
        end
    end
    -- Variable
    if is_var(expr) then
        return expr.name
    end
    -- Constants
    if expr.type == "constant" then
        return expr.name
    end
    -- Negation
    if expr.type == "neg" and expr.value then
        local inner = pretty_print_internal(expr.value, "neg", "right")
        if not is_simple_factor(expr.value) then
            inner = "(" .. inner .. ")"
        end
        return "-" .. inner
    end
    -- Power: x^y, also handle sqrt
    if is_pow(expr) then
        -- Square root pretty print
        if is_num(expr.exp) and expr.exp.value == 0.5 then
            local arg_str = pretty_print_internal(expr.base, "sqrt", "arg")
            -- Avoid excessive parentheses around simple factors or powers (like x^2)
            if not (is_simple_factor(expr.base) or is_pow(expr.base)) then
                arg_str = "(" .. arg_str .. ")"
            end
            return "√" .. arg_str
        end
        local base_str = pretty_print_internal(expr.base, "pow", "left")
        local exp_str = pretty_print_internal(expr.exp, "pow", "right")
        if needs_parens(expr.base, "pow", "left") then
            base_str = "(" .. base_str .. ")"
        end
        if needs_parens(expr.exp, "pow", "right") then
            exp_str = "(" .. exp_str .. ")"
        end
        return base_str .. "^" .. exp_str
    end
    -- Functions: sin, cos, ln, exp, sqrt, and custom
    if expr.type == "sin" or expr.type == "cos" or expr.type == "ln" or expr.type == "exp" then
        local fname = expr.type
        return fname .. "(" .. pretty_print_internal(expr.arg, nil, nil) .. ")"
    end
    if expr.type == "sqrt" then
        local arg_str = pretty_print_internal(expr.arg, "sqrt", "arg")
        -- Avoid excessive parentheses around simple factors or powers (like x^2)
        if not (is_simple_factor(expr.arg) or is_pow(expr.arg)) then
            arg_str = "(" .. arg_str .. ")"
        end
        return "√" .. arg_str
    end
    -- Pretty print for func("int", ...): display as integral
    if expr.type == "func" and expr.name == "int" and expr.args then
        local arg_str = pretty_print_internal(expr.args[1], nil, nil)
        local respect_to = "x"
        if expr.args[2] and expr.args[2].type == "variable" then
            respect_to = expr.args[2].name
        end
        return "∫" .. arg_str .. " d" .. respect_to
    end
    -- Pretty print for inverse trig: arcsin, arccos, arctan, etc.
    if expr.type == "func" and expr.name and expr.args and (
        expr.name == "arcsin" or expr.name == "arccos" or expr.name == "arctan" or expr.name == "arccot"
        or expr.name == "arccsc" or expr.name == "arcsec"
    ) then
        local arg_strs = {}
        for i, arg in ipairs(expr.args) do
            table.insert(arg_strs, pretty_print_internal(arg, nil, nil))
        end
        return expr.name .. "(" .. table.concat(arg_strs, ", ") .. ")"
    end
    -- Handle generic function nodes: func(name, args)
    if expr.type == "func" and expr.name and expr.args then
        local arg_strs = {}
        for i, arg in ipairs(expr.args) do
            table.insert(arg_strs, pretty_print_internal(arg, nil, nil))
        end
        return expr.name .. "(" .. table.concat(arg_strs, ", ") .. ")"
    end
    -- Addition with forced + C at the end
    if is_add(expr) and expr.args then
        local regular_terms = {}
        local constant_c = nil

        for _, arg in ipairs(expr.args) do
            if arg.type == "variable" and arg.name == "C" then
                constant_c = pretty_print_internal(arg, "add", "inner")
            else
                local s = pretty_print_internal(arg, "add", "inner")
                -- Parenthesize negative terms for clarity
                if is_num(arg) and arg.value < 0 then
                    s = "(" .. s .. ")"
                elseif arg.type == "neg" then
                    s = "(" .. s .. ")"
                end
                table.insert(regular_terms, s)
            end
        end

        local result = table.concat(regular_terms, " + ")
        if constant_c then
            if #regular_terms > 0 then
                result = result .. " + " .. constant_c
            else
                result = constant_c
            end
        end

        if needs_parens(expr, parent_op, position) then
            return "(" .. result .. ")"
        end
        return result
    end
    -- Multiplication (improved implicit multiplication logic, always print 2x not x*2)
    if is_mul(expr) and expr.args then
        local parts = {}
        local function is_simple_func(e)
            return e and (e.type == "sin" or e.type == "cos" or e.type == "ln" or e.type == "exp" or (e.type == "func"))
        end
        -- Sort: numbers first, then variables, then powers, then functions, then others
        local sorted_args = {}
        for i, arg in ipairs(expr.args) do sorted_args[i] = arg end
        table.sort(sorted_args, function(a, b)
            local function sort_key(e)
                if is_num(e) then return 1
                elseif is_var(e) then return 2
                elseif is_pow(e) then return 3
                elseif is_simple_func(e) then return 4
                else return 5 end
            end
            local ka, kb = sort_key(a), sort_key(b)
            if ka ~= kb then return ka < kb end
            -- If same type, keep original order for stability
            return false
        end)
        -- Suppress leading 1 * expr, unless it's the only argument
        if is_num(sorted_args[1]) and sorted_args[1].value == 1 and #sorted_args > 1 then
            table.remove(sorted_args, 1)
        end
        -- Now build pretty print from sorted_args
        for i, arg in ipairs(sorted_args) do
            local s = pretty_print_internal(arg, "mul", "inner")
            if i == 1 then
                table.insert(parts, s)
            else
                local prev = sorted_args[i-1]
                local prev_is_num = is_num(prev)
                local prev_is_var = is_var(prev)
                local prev_is_pow = is_pow(prev)
                local prev_is_func = is_simple_func(prev)
                local curr_is_num = is_num(arg)
                local curr_is_var = is_var(arg)
                local curr_is_pow = is_pow(arg)
                local curr_is_func = is_simple_func(arg)

                -- Implicit multiplication rules:
                -- 2x, 3sin(x), xy, x^2y, x^2sin(x), sin(x)y, etc.
                -- But: x*6, sin(x)*5, etc. should be explicit
                local implicit = false
                -- Number before variable/power/function: 2x, 3sin(x), 4x^2
                if prev_is_num and (curr_is_var or curr_is_pow or curr_is_func) then
                    implicit = true
                    table.insert(parts, s)
                -- Variable before variable/power/function: xy, xsin(x), x^2y, x^2sin(x)
                elseif prev_is_var and (curr_is_var or curr_is_pow or curr_is_func) then
                    -- Special: if variable before inverse trig function, add space
                    if curr_is_func and arg.type == "func"
                        and (arg.name == "arcsin" or arg.name == "arccos" or arg.name == "arctan"
                             or arg.name == "arccot" or arg.name == "arccsc" or arg.name == "arcsec")
                    then
                        implicit = true
                        table.insert(parts, " " .. s)
                    else
                        implicit = true
                        table.insert(parts, s)
                    end
                -- Power before variable/power/function: x^2y, x^2sin(x), (x^2)(y^3)
                elseif prev_is_pow and (curr_is_var or curr_is_pow or curr_is_func) then
                    implicit = true
                    table.insert(parts, s)
                -- Function before variable/power/function: sin(x)y, sin(x)x^2
                elseif prev_is_func and (curr_is_var or curr_is_pow) then
                    implicit = true
                    table.insert(parts, s)
                else
                    table.insert(parts, " * " .. s)
                end
            end
        end
        local result = table.concat(parts)
        if needs_parens(expr, parent_op, position) then
            return "(" .. result .. ")"
        end
        return result
    end
    -- Division
    if expr.type == "div" and expr.left and expr.right then
        -- If denominator is 1, just return numerator
        if is_num(expr.right) and expr.right.value == 1 then
            return pretty_print_internal(expr.left, parent_op, position)
        end
        local left_str = pretty_print_internal(expr.left, "div", "left")
        local right_str = pretty_print_internal(expr.right, "div", "right")
        if not is_simple_factor(expr.left) then
            left_str = "(" .. left_str .. ")"
        end
        if not is_simple_factor(expr.right) then
            right_str = "(" .. right_str .. ")"
        end
        return left_str .. "/" .. right_str
    end
    -- Subtraction
    if expr.type == "sub" and expr.left and expr.right then
        local left_str = pretty_print_internal(expr.left, "sub", "left")
        local right_str = pretty_print_internal(expr.right, "sub", "right")
        if not is_simple_factor(expr.left) then
            left_str = "(" .. left_str .. ")"
        end
        if not is_simple_factor(expr.right) then
            right_str = "(" .. right_str .. ")"
        end
        return left_str .. " - " .. right_str
    end
    -- Pretty print for integral nodes
    if expr.type == "integral" and expr.integrand and expr.respect_to then
        return "∫" .. pretty_print_internal(expr.integrand, nil, nil) .. " d" .. expr.respect_to
    end

    -- Pretty print for limit nodes
    if expr.type == "lim" and expr.expr and expr.var and expr.to then
        local expr_str = pretty_print_internal(expr.expr, nil, nil)
        local to_str = pretty_print_internal(expr.to, nil, nil)
        return "lim_(" .. expr.var .. "→" .. to_str .. ") " .. expr_str
    end
    -- Pretty print for series node
    if expr.type == "series" and expr.func and expr.var and expr.center and expr.order then
        local func_str = pretty_print_internal(expr.func, nil, nil)
        local varName_str = pretty_print_internal(expr.var, nil, nil)
        local center_str = pretty_print_internal(expr.center, nil, nil)
        local order_str = pretty_print_internal(expr.order, nil, nil)
        return "series(" .. func_str .. ", " .. varName_str .. ", " .. center_str .. ", " .. order_str .. ")"
    end

    -- Pretty print for plus-minus node ("pm")
    if expr.type == "pm" and expr.left and expr.right then
        local left_str = pretty_print_internal(expr.left, nil, nil)
        local right_str = pretty_print_internal(expr.right, nil, nil)
        return "(" .. left_str .. " ± " .. right_str .. ")"
    end

    -- Pretty print for tensor node (recursive for arbitrary depth)
    if expr.type == "tensor" and expr.elements then
        local function pretty_print_tensor_elements(elems)
            local strs = {}
            for i, elem in ipairs(elems) do
                if type(elem) == "table" and elem.type == "tensor" and elem.elements then
                    strs[i] = "[" .. table.concat(pretty_print_tensor_elements(elem.elements), ", ") .. "]"
                else
                    strs[i] = pretty_print_internal(elem, nil, nil)
                end
            end
            return strs
        end
        return "[" .. table.concat(pretty_print_tensor_elements(expr.elements), ", ") .. "]"
    end

    return "<unknown>"
end
-- Debug print full AST for any expression
function simplify.debug_print_ast(expr)
    print("DEBUG AST dump:\n" .. ast_to_string(expr))
end
-- Recursively round all number nodes (including those inside expressions like mul, add, etc.)
local function recursively_round_numbers(expr)
    if type(expr) ~= "table" then return expr end
    if expr.type == "number" and type(expr.value) == "number" then
        local p = get_precision()
        expr.value = round_to_precision(expr.value, p)
        return expr
    end
    local out = {}
    for k, v in pairs(expr) do
        if type(v) == "table" then
            out[k] = recursively_round_numbers(v)
        else
            out[k] = v
        end
    end
    setmetatable(out, getmetatable(expr))
    return out
end
-- ===== PUBLIC API =====

function simplify.simplify(expr)
    return simplify_until_stable(expr)
end

function simplify.pretty_print(expr)
    local display_expr = recursively_round_numbers(deepcopy(expr))
    return pretty_print_internal(display_expr, nil, nil)
end

function simplify.canonicalize(expr)
    -- Just normalize structure without aggressive simplification
    local normalized = deepcopy(expr)
    if (is_add(normalized) or is_mul(normalized)) and normalized.args then
        normalized = flatten(normalized)
        normalized = sort_args(normalized)
    end
    return normalized
end

function simplify.simplify_with_stats(expr)
    local max_iterations = 20
    local iteration = 0
    local prev_hash = nil
    
    while iteration < max_iterations do
        expr = simplify_step(expr)
        local current_hash = expr_hash(expr)
        
        if current_hash == prev_hash then
            break -- Converged
        end
        
        prev_hash = current_hash
        iteration = iteration + 1
    end
    
    return expr, {
        passes = iteration,
        converged = iteration < max_iterations
    }
end



-- Export to global if needed (keeping compatibility)
_G.simplify = simplify