local simplify = {}
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

local function fold_constants(expr)
    if is_num(expr) then return expr end
    
    if is_add(expr) and expr.args then
        local sum = 0
        local non_numbers = {}
        
        for _, arg in ipairs(expr.args) do
            if is_num(arg) then
                sum = sum + arg.value
            else
                table.insert(non_numbers, arg)
            end
        end
        
        local result_args = {}
        if sum ~= 0 then
            table.insert(result_args, num(sum))
        end
        for _, arg in ipairs(non_numbers) do
            table.insert(result_args, arg)
        end
        
        if #result_args == 0 then return num(0) end
        if #result_args == 1 then return result_args[1] end
        return {type = "add", args = result_args}
    end
    
    if is_mul(expr) and expr.args then
        local product = 1
        local non_numbers = {}

        for _, arg in ipairs(expr.args) do
            if is_num(arg) then
                product = product * arg.value
            else
                table.insert(non_numbers, arg)
            end
        end

        -- Zero kills everything
        if product == 0 then return num(0) end

        -- Remove any numeric factor 1 from non_numbers, unless it is the only factor
        local filtered_non_numbers = {}
        for _, arg in ipairs(non_numbers) do
            if not (is_num(arg) and arg.value == 1 and #non_numbers > 1) then
                table.insert(filtered_non_numbers, arg)
            end
        end
        non_numbers = filtered_non_numbers

        local result_args = {}
        -- Only include the 1 if there are no non-numeric factors
        if product ~= 1 or #non_numbers == 0 then
            table.insert(result_args, num(product))
        end
        for _, arg in ipairs(non_numbers) do
            table.insert(result_args, arg)
        end

        if #result_args == 0 then return num(1) end
        if #result_args == 1 then return result_args[1] end
        return {type = "mul", args = result_args}
    end
    
    if is_pow(expr) then
        if is_num(expr.base) and is_num(expr.exp) then
            return num(expr.base.value ^ expr.exp.value)
        end
    end

    -- Gamma function constant folding using _G.evaluateGamma if available
    if expr.type == "func" and expr.name == "gamma" and expr.args and #expr.args == 1 then
        local arg = expr.args[1]
        if is_num(arg) and _G.evaluateGamma then
            return num(_G.evaluateGamma(arg.value))
        end
    end

    -- Factorial constant folding using _G.evaluateFactorial if available, else fallback to transform
    if expr.type == "func" and expr.name == "factorial" and expr.args and #expr.args == 1 then
        local arg = expr.args[1]
        if is_num(arg) and _G.evaluateFactorial then
            return num(_G.evaluateFactorial(arg.value))
        else
            local transformed = _G.transformFactorial(expr)
            return transformed
        end
    end
    
    return expr
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
        local coeff, base = extract_coefficient_and_base(term)
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
        
        local base_key = expr_hash(base)
        if base_groups[base_key] then
            -- Combine exponents: x^a * x^b = x^(a+b)
            base_groups[base_key].exponents = base_groups[base_key].exponents or {}
            table.insert(base_groups[base_key].exponents, exp)
        else
            base_groups[base_key] = {base = base, exponents = {exp}}
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

local function simplify_step(expr)
    if type(expr) ~= "table" then return expr end

    -- Recursively simplify children first
    local new_expr = deepcopy(expr)

    -- Debug print for all nodes at entry (full AST node)
    print("DEBUG: AST node received by simplify_step:\n" .. ast_to_string(new_expr))

    -- Only simplify known types; preserve unknown types (e.g. unimplemented_integral)
    local known_types = {
        number = true, variable = true, constant = true, pow = true, add = true, mul = true,
        sin = true, cos = true, ln = true, exp = true, integral = true, func = true, neg = true,
        series = true
    }
    if not known_types[new_expr.type] then
        return new_expr -- Preserve unknown node types like unimplemented_integral
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
    elseif new_expr.type == "neg" and new_expr.arg then
        new_expr.arg = simplify_step(new_expr.arg)
        -- Double negation elimination: -(-expr) => expr
        if new_expr.arg and new_expr.arg.type == "neg" then
            return simplify_step(new_expr.arg.arg)
        end
    elseif new_expr.type == "constant" then
        -- Recursively simplify the value of the constant
        new_expr.value = simplify_step(new_expr.value)
        return new_expr.value
    end

    -- Integration logic using the integration engine
    if new_expr.type == "integral" then
        local integrand = simplify_step(new_expr.integrand)
        local respect_to = new_expr.respect_to

        if _G.integrate and _G.integrate.integrateAST then
            local integrated = _G.integrate.integrateAST(integrand, respect_to)
            if integrated then
                return simplify_step(integrated)
            end
        end

        -- Fallback symbolic node if integration fails
        return { type = "integral", integrand = integrand, respect_to = respect_to }
    end

    -- Handle func("int", {expr, var}) as symbolic integral, with debug tracing
    if new_expr.type == "func" and new_expr.name == "int" and new_expr.args then
        local integrand = simplify_step(new_expr.args[1])
        local respect_to = "x"
        if new_expr.args[2] and new_expr.args[2].type == "variable" then
            respect_to = new_expr.args[2].name
        end

        print("Integrating func int with integrand:", simplify.pretty_print(integrand), "respect_to:", respect_to)

        local integrated = nil
        if _G.integrate and _G.integrate.integrateAST then
            integrated = _G.integrate.integrateAST(integrand, respect_to)
        else
            print("Warning: _G.integrate.integrateAST missing")
        end

        print("Integration result:", integrated and simplify.pretty_print(integrated) or "nil")

        if integrated then
            return simplify_step(integrated)
        else
            print("Integration failed, returning symbolic int node")
            return {
                type = "func",
                name = "int",
                args = { integrand, { type = "variable", name = respect_to } }
            }
        end
    end

    -- Debug: print each stage
    print("Original:", simplify.pretty_print(new_expr))

    new_expr = flatten(new_expr)
    print("After flatten:", simplify.pretty_print(new_expr))

    new_expr = sort_args(new_expr)
    print("After sort_args:", simplify.pretty_print(new_expr))

    new_expr = fold_constants(new_expr)
    print("After fold_constants:", simplify.pretty_print(new_expr))

    new_expr = collect_like_terms(new_expr)
    print("After collect_like_terms:", simplify.pretty_print(new_expr))

    new_expr = simplify_powers(new_expr)
    print("After simplify_powers:", simplify.pretty_print(new_expr))

    new_expr = combine_powers(new_expr)
    print("After combine_powers:", simplify.pretty_print(new_expr))

    new_expr = distribute_simple(new_expr)
    print("After distribute_simple:", simplify.pretty_print(new_expr))

    new_expr = expand_special_cases(new_expr)
    print("After expand_special_cases:", simplify.pretty_print(new_expr))

    new_expr = apply_trig_identities(new_expr)
    print("After apply_trig_identities:", simplify.pretty_print(new_expr))

    new_expr = apply_log_identities(new_expr)
    print("After apply_log_identities:", simplify.pretty_print(new_expr))

    -- Series expansion handling
    if new_expr.type == "series" and _G.series and _G.series.expand then
        local func = simplify_step(new_expr.func)
        local var = simplify_step(new_expr.var)
        local center = simplify_step(new_expr.center)
        local order = simplify_step(new_expr.order)

        assert(var.type == "variable", "series var must be a variable")

        -- Expand the series using the series module
        local expanded = _G.series.expand(func.name, var, center.value, order.value)

        -- Fully simplify the expanded series recursively
        local simplified_expanded = simplify_step(expanded)

        -- Fold constants to clean up factorial/gamma evaluations
        simplified_expanded = fold_constants(simplified_expanded)

        -- Collect like terms and simplify powers for neatness
        simplified_expanded = collect_like_terms(simplified_expanded)
        simplified_expanded = simplify_powers(simplified_expanded)
        simplified_expanded = combine_powers(simplified_expanded)
        simplified_expanded = fold_constants(simplified_expanded) -- again fold any new constants

        return simplified_expanded
    end

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
    if expr.type == "neg" and expr.arg then
        local inner = pretty_print_internal(expr.arg, "neg", "right")
        if not is_simple_factor(expr.arg) then
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
    local var_str = pretty_print_internal(expr.var, nil, nil)
    local center_str = pretty_print_internal(expr.center, nil, nil)
    local order_str = pretty_print_internal(expr.order, nil, nil)
    return "series(" .. func_str .. ", " .. var_str .. ", " .. center_str .. ", " .. order_str .. ")"
end
    return "<unknown>"
end

-- ===== PUBLIC API =====

function simplify.simplify(expr)
    return simplify_until_stable(expr)
end

function simplify.pretty_print(expr)
    return pretty_print_internal(expr, nil, nil)
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

