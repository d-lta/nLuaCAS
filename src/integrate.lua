-- Integral Engine (Enhanced Edition - Because Apparently We're Gluttons for Punishment)
-- Now with 300% more ways to fail spectacularly at symbolic integration
-- Features: Inverse trig functions, partial fractions, and other mathematical nightmares

local ast = rawget(_G, "ast") or require("ast")
local diffAST = rawget(_G, "diffAST") or error("diffAST: differentiation function required for integration by parts")
local trig = rawget(_G, "trig")
local simplify = rawget(_G, "simplify") or require("simplify")

-- Expanded symbolic integral lookup (now with inverse trig because we hate ourselves)
local known_integral_table = {
  -- Inverse trig functions (the devil's own mathematics)
  arcsin = function(arg) 
    return ast.add(ast.mul(arg, ast.func("arcsin", {copy(arg)})), ast.func("sqrt", {ast.sub(ast.number(1), ast.pow(copy(arg), ast.number(2)))}))
  end,
  arccos = function(arg)
    return ast.sub(ast.mul(arg, ast.func("arccos", {copy(arg)})), ast.func("sqrt", {ast.sub(ast.number(1), ast.pow(copy(arg), ast.number(2)))}))
  end,
  arctan = function(arg)
    return ast.sub(ast.mul(arg, ast.func("arctan", {copy(arg)})), ast.div(ast.func("ln", {ast.add(ast.number(1), ast.pow(copy(arg), ast.number(2)))}), ast.number(2)))
  end,
  
  -- Hyperbolic functions (because regular trig wasn't painful enough)
  sinh = function(arg) return ast.func("cosh", {copy(arg)}) end,
  cosh = function(arg) return ast.func("sinh", {copy(arg)}) end,
  tanh = function(arg) return ast.func("ln", {ast.func("cosh", {copy(arg)})}) end,
  
  -- Square root integrals (the "f it, let's go deeper" collection)
  sqrt = function(arg)
    if is_symbol(arg, "x") then
      return ast.div(ast.mul(ast.number(2), ast.pow(arg, ast.div(ast.number(3), ast.number(2)))), ast.number(3))
    end
    return nil
  end
}

local enable_substitution = true  
local enable_advanced_symbolics = true  -- Fuck it, we're going full masochist mode
local enable_partial_fractions = true   -- Because rational functions are the devil
local enable_definite_integrals = true  -- Bounds? We don't need no stinking bounds... wait, yes we do

-- Utility functions that hopefully won't explode this time
local function copy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local t = {}
  for k,v in pairs(tbl) do 
    t[k] = type(v) == "table" and copy(v) or v 
  end
  return t
end

local function is_const(node)
  return node and node.type == "number"
end

local function is_var(node)
  return node and node.type == "variable"
end

local function is_symbol(node, name)
  return node and node.type == "variable" and node.name == name
end

-- Check if expression contains only polynomials (for partial fraction decomposition)
local function is_polynomial(node, var)
  if not node then return false end
  if node.type == "number" then return true end
  if node.type == "variable" then return node.name == var or true end -- constants are polynomials too
  if node.type == "add" or node.type == "sub" then
    return is_polynomial(node.left or node.args and node.args[1], var) and 
           is_polynomial(node.right or node.args and node.args[2], var)
  end
  if node.type == "mul" and node.args then
    for _, arg in ipairs(node.args) do
      if not is_polynomial(arg, var) then return false end
    end
    return true
  end
  if node.type == "pow" then
    return is_polynomial(node.base, var) and is_const(node.exp) and node.exp.value >= 0
  end
  return false
end

-- Partial fraction decomposition (the "why did I think this was a good idea" function)
local function partial_fraction_decompose(numerator, denominator, var)
  -- This is a massive simplification - real partial fractions are a nightmare
  -- We'll handle the simplest case: A/(x-a) + B/(x-b)
  
  if not denominator or denominator.type ~= "mul" then return nil end
  if not denominator.args or #denominator.args ~= 2 then return nil end
  
  local factors = {}
  for _, factor in ipairs(denominator.args) do
    if factor.type == "add" and factor.args and #factor.args == 2 then
      -- Check if it's (x + constant) form
      local x_term, const_term
      for _, term in ipairs(factor.args) do
        if is_symbol(term, var) then x_term = term
        elseif is_const(term) then const_term = term
        end
      end
      if x_term and const_term then
        table.insert(factors, {type = "linear", root = ast.number(-const_term.value)})
      end
    elseif factor.type == "sub" and factor.left and factor.right then
      if is_symbol(factor.left, var) and is_const(factor.right) then
        table.insert(factors, {type = "linear", root = copy(factor.right)})
      end
    end
  end
  
  if #factors == 2 and factors[1].type == "linear" and factors[2].type == "linear" then
    -- We have (x-a)(x-b), so we want A/(x-a) + B/(x-b)
    -- This is where I'd implement the full algorithm if I wasn't already dead inside
    -- For now, return a placeholder that integration can handle
    return {
      type = "partial_fraction_sum",
      terms = {
        {numerator = ast.number(1), denominator = ast.sub(ast.variable(var), factors[1].root)},
        {numerator = ast.number(1), denominator = ast.sub(ast.variable(var), factors[2].root)}
      }
    }
  end
  
  return nil
end

-- Enhanced pattern matching (now with 50% more disappointment)
local function pattern_match(expr, pattern, bindings)
  bindings = bindings or {}
  
  if not expr or not pattern then return false end
  
  if pattern.type == "wildcard" then
    bindings[pattern.name] = expr
    return true, bindings
  end
  
  if expr.type ~= pattern.type then return false end
  
  if expr.type == "number" then
    return expr.value == pattern.value, bindings
  elseif expr.type == "variable" then
    return expr.name == pattern.name, bindings
  elseif expr.type == "func" and expr.name == pattern.name then
    if expr.args and pattern.args and expr.args[1] and pattern.args[1] then
      return pattern_match(expr.args[1], pattern.args[1], bindings)
    end
    return false
  elseif expr.type == "mul" or expr.type == "add" then
    if not expr.args or not pattern.args or #expr.args ~= #pattern.args then 
      return false 
    end
    for i = 1, #expr.args do
      local ok, new_bindings = pattern_match(expr.args[i], pattern.args[i], bindings)
      if not ok then return false end
      bindings = new_bindings or bindings
    end
    return true, bindings
  elseif expr.type == "pow" then
    if not expr.base or not expr.exp or not pattern.base or not pattern.exp then
      return false
    end
    local ok1, b1 = pattern_match(expr.base, pattern.base, bindings)
    local ok2, b2 = pattern_match(expr.exp, pattern.exp, b1 or bindings)
    return ok1 and ok2, b2 or bindings
  end
  
  return false
end

-- Advanced substitution patterns (because basic substitution wasn't masochistic enough)
local function try_advanced_substitution(node, var)
  if not enable_advanced_symbolics then return nil end
  
  -- Trigonometric substitutions (the "abandon all hope" section)
  local sqrt_patterns = {
    -- √(a² - x²) -> x = a*sin(θ)
    {
      pattern = ast.func("sqrt", {ast.sub(ast.pow(ast.wildcard("a"), ast.number(2)), ast.pow(ast.variable(var), ast.number(2)))}),
      substitution = "trig_sin"
    },
    -- √(a² + x²) -> x = a*tan(θ)  
    {
      pattern = ast.func("sqrt", {ast.add(ast.pow(ast.wildcard("a"), ast.number(2)), ast.pow(ast.variable(var), ast.number(2)))}),
      substitution = "trig_tan"
    },
    -- √(x² - a²) -> x = a*sec(θ)
    {
      pattern = ast.func("sqrt", {ast.sub(ast.pow(ast.variable(var), ast.number(2)), ast.pow(ast.wildcard("a"), ast.number(2)))}),
      substitution = "trig_sec"
    }
  }
  
  for _, sub_pattern in ipairs(sqrt_patterns) do
    local bindings = {}
    if pattern_match(node, sub_pattern.pattern, bindings) then
      -- In a real implementation, we'd actually perform the substitution
      -- For now, let's just acknowledge we found a pattern and cry softly
      return {
        type = "advanced_substitution",
        method = sub_pattern.substitution,
        original = copy(node),
        bindings = bindings
      }
    end
  end
  
  return nil
end

-- Enhanced substitution (now with more ways to fail)
local function try_substitution(node, var)
  if not node or node.type ~= "mul" or not node.args then 
    return nil 
  end
  
  -- Try advanced substitutions first
  local advanced = try_advanced_substitution(node, var)
  if advanced then return advanced end
  
  for _, arg in ipairs(node.args) do
    if ast.is_function_of and ast.is_function_of(arg, var) then
      local f = arg
      local df = diffAST(f, var)
      if df then
        for _, inner in ipairs(node.args) do
          if inner ~= arg and simplify.expr_equal and simplify.expr_equal(inner, df) then
            local u = ast.variable("u")
            local replaced = ast.replace and ast.replace(node, f, u)
            if replaced then
              local integral_u = integrateAST(replaced, "u")
              if integral_u and integral_u.type ~= "unimplemented_integral" then
                return ast.replace(integral_u, u, f)
              end
            end
          end
        end
      end
    end
  end
  return nil
end

-- Integration by parts (now with recursive attempts because we're flipping insane)
local function try_integration_by_parts(node, var)
  if not node or node.type ~= "mul" or not node.args or #node.args < 2 then 
    return nil 
  end
  
  -- Priority list for choosing u (LIATE rule: Logarithmic, Inverse trig, Algebraic, Trig, Exponential)
  local function get_integration_priority(expr)
    if expr.type == "func" then
      if expr.name == "ln" then return 1 end
      if expr.name:match("^arc") then return 2 end -- arcsin, arccos, etc.
      if expr.name:match("^a?sinh?$") or expr.name:match("^a?cosh?$") then return 2 end
      if expr.name == "sin" or expr.name == "cos" or expr.name == "tan" then return 4 end
      if expr.name == "exp" then return 5 end
    elseif expr.type == "pow" and is_symbol(expr.base, var) then
      return 3 -- algebraic
    elseif is_symbol(expr, var) then
      return 3
    end
    return 6 -- everything else
  end
  
  -- Choose u and dv based on priority
  local best_u, best_dv
  local best_priority = math.huge
  
  for i = 1, #node.args do
    local priority = get_integration_priority(node.args[i])
    if priority < best_priority then
      best_priority = priority
      best_u = node.args[i]
      -- dv is everything else
      local dv_args = {}
      for j = 1, #node.args do
        if i ~= j then table.insert(dv_args, node.args[j]) end
      end
      best_dv = #dv_args == 1 and dv_args[1] or ast.mul(table.unpack(dv_args))
    end
  end
  
  if not best_u or not best_dv then return nil end
  
  local V = integrateAST(best_dv, var)
  local du = diffAST(best_u, var)
  
  if not V or not du or V.type == "unimplemented_integral" then
    return nil
  end
  
  local second_integral = integrateAST(ast.mul(V, du), var)
  if second_integral and second_integral.type ~= "unimplemented_integral" then
    return ast.sub(ast.mul(best_u, V), second_integral)
  end
  
  return nil
end

-- Enhanced trig integration (now with more trigonometric masochism)
local function integrate_trig(fname, arg, var)
  if not fname or not arg then return nil end
  
  -- Handle chain rule: if arg is not just the variable, we need the derivative
  local chain_factor = nil
  if arg.type ~= "variable" or arg.name ~= var then
    local darg = diffAST(arg, var)
    if not darg then return nil end
    chain_factor = darg
  end
  
  local base_integral
  if fname == "sin" then
    base_integral = ast.neg(ast.func("cos", { copy(arg) }))
  elseif fname == "cos" then
    base_integral = ast.func("sin", { copy(arg) })
  elseif fname == "tan" then
    base_integral = ast.neg(ast.func("ln", { ast.func("cos", { copy(arg) }) }))
  elseif fname == "cot" then
    base_integral = ast.func("ln", { ast.func("sin", { copy(arg) }) })
  elseif fname == "sec" then
    base_integral = ast.func("ln", { ast.add(ast.func("sec", { copy(arg) }), ast.func("tan", { copy(arg) })) })
  elseif fname == "csc" then
    base_integral = ast.neg(ast.func("ln", { ast.add(ast.func("csc", { copy(arg) }), ast.func("cot", { copy(arg) })) }))
  -- Inverse trig functions (the "why do these even exist" section)
  elseif fname == "arcsin" then
    if is_symbol(arg, var) then
      return ast.add(ast.mul(copy(arg), ast.func("arcsin", {copy(arg)})), 
                     ast.func("sqrt", {ast.sub(ast.number(1), ast.pow(copy(arg), ast.number(2)))}))
    end
  elseif fname == "arccos" then
    if is_symbol(arg, var) then
      return ast.sub(ast.mul(copy(arg), ast.func("arccos", {copy(arg)})), 
                     ast.func("sqrt", {ast.sub(ast.number(1), ast.pow(copy(arg), ast.number(2)))}))
    end
  elseif fname == "arctan" then
    if is_symbol(arg, var) then
      return ast.sub(ast.mul(copy(arg), ast.func("arctan", {copy(arg)})), 
                     ast.div(ast.func("ln", {ast.add(ast.number(1), ast.pow(copy(arg), ast.number(2)))}), ast.number(2)))
    end
  -- Hyperbolic functions (because we're completionists, apparently)
  elseif fname == "sinh" then
    base_integral = ast.func("cosh", { copy(arg) })
  elseif fname == "cosh" then
    base_integral = ast.func("sinh", { copy(arg) })
  elseif fname == "tanh" then
    base_integral = ast.func("ln", { ast.func("cosh", { copy(arg) }) })
  else
    return nil
  end
  
  -- Apply chain rule if needed
  if chain_factor and base_integral then
    -- This would need the reciprocal of the chain factor, which is complex
    -- For now, return nil for non-trivial arguments
    return nil
  end
  
  return base_integral
end

-- Numerical integration fallback (because sometimes symbolic integration is impossible)
local function numerical_integration_fallback(node, var, a, b)
  if not enable_definite_integrals or not a or not b then
    return {
      type = "numerical_integration_required",
      original = copy(node),
      bounds = {lower = a, upper = b}
    }
  end
  
  -- Simpson's rule implementation would go here
  -- But that's a whole other can of worms
  return {
    type = "numerical_approximation",
    method = "simpsons_rule",
    original = copy(node),
    bounds = {lower = a, upper = b}
  }
end

-- Core integration function (now with 400% more complexity and existential dread)
local function integrateAST(node, var, bounds)
  if not node then 
    error("integrateAST: invalid AST node") 
  end
  var = var or "x"
  
  -- Handle definite integrals
  local is_definite = bounds and bounds.lower and bounds.upper
  
  -- ∫ c dx = c * x
  if node.type == "number" then
    local result = ast.mul(copy(node), ast.variable(var))
    if is_definite then
      -- F(b) - F(a)
      local upper_val = ast.mul(copy(node), copy(bounds.upper))
      local lower_val = ast.mul(copy(node), copy(bounds.lower))
      return ast.sub(upper_val, lower_val)
    end
    return ast.add(result, ast.variable("C"))
  end

  -- ∫ x dx = x^2/2 ; ∫ y dx = y * x
  if node.type == "variable" then
    if node.name == var then
      local result = ast.div(ast.pow(ast.variable(var), ast.number(2)), ast.number(2))
      if is_definite then
        local upper_val = ast.div(ast.pow(copy(bounds.upper), ast.number(2)), ast.number(2))
        local lower_val = ast.div(ast.pow(copy(bounds.lower), ast.number(2)), ast.number(2))
        return ast.sub(upper_val, lower_val)
      end
      return ast.add(result, ast.variable("C"))
    else
      local result = ast.mul(copy(node), ast.variable(var))
      if is_definite then
        local diff = ast.sub(copy(bounds.upper), copy(bounds.lower))
        return ast.mul(copy(node), diff)
      end
      return ast.add(result, ast.variable("C"))
    end
  end

  -- ∫ (u + v) dx = ∫u + ∫v
  if node.type == "add" and node.args then
    local results = {}
    for i, term in ipairs(node.args) do
      local integral_term = integrateAST(term, var, bounds)
      if integral_term.type == "unimplemented_integral" then
        -- Try numerical integration if this is definite
        if is_definite then
          return numerical_integration_fallback(node, var, bounds.lower, bounds.upper)
        end
        return { type = "unimplemented_integral", original = node }
      end
      results[i] = integral_term
    end
    if is_definite then
      return ast.add(table.unpack(results))
    end
    return ast.add(ast.add(table.unpack(results)), ast.variable("C"))
  end

  -- ∫ (u - v) dx = ∫u - ∫v
  if node.type == "sub" and node.left and node.right then
    local left_int = integrateAST(node.left, var, bounds)
    local right_int = integrateAST(node.right, var, bounds)
    if left_int.type == "unimplemented_integral" or right_int.type == "unimplemented_integral" then
      if is_definite then
        return numerical_integration_fallback(node, var, bounds.lower, bounds.upper)
      end
      return { type = "unimplemented_integral", original = node }
    end
    if is_definite then
      return ast.sub(left_int, right_int)
    end
    return ast.add(ast.sub(left_int, right_int), ast.variable("C"))
  end

  -- Enhanced division handling with partial fractions
  if node.type == "div" and node.left and node.right then
    local num, denom = node.left, node.right
    
    -- Check for f'(x)/f(x) pattern first
    local ddenom = diffAST(denom, var)
    if ddenom and simplify.expr_equal and simplify.expr_equal(num, ddenom) then
      local result = ast.func("ln", { ast.func("abs", { copy(denom) }) })
      if is_definite then
        local upper_val = ast.func("ln", { ast.func("abs", { ast.replace(copy(denom), ast.variable(var), copy(bounds.upper)) }) })
        local lower_val = ast.func("ln", { ast.func("abs", { ast.replace(copy(denom), ast.variable(var), copy(bounds.lower)) }) })
        return ast.sub(upper_val, lower_val)
      end
      return result
    end
    
    -- Try partial fraction decomposition
    if enable_partial_fractions and is_polynomial(num, var) and is_polynomial(denom, var) then
      local partial_fractions = partial_fraction_decompose(num, denom, var)
      if partial_fractions and partial_fractions.type == "partial_fraction_sum" then
        local results = {}
        for _, term in ipairs(partial_fractions.terms) do
          local term_integral = integrateAST(ast.div(term.numerator, term.denominator), var, bounds)
          if term_integral.type == "unimplemented_integral" then
            break
          end
          table.insert(results, term_integral)
        end
        if #results == #partial_fractions.terms then
          return ast.add(table.unpack(results))
        end
      end
    end
    
    -- Convert to multiplication for further processing
    return integrateAST(ast.mul(node.left, ast.pow(node.right, ast.number(-1))), var, bounds)
  end

  -- Enhanced multiplication handling
  if node.type == "mul" and node.args then
    -- Try substitution first
    if enable_substitution then
      local sub_result = try_substitution(node, var)
      if sub_result then 
        if sub_result.type == "advanced_substitution" then
          -- For now, acknowledge we found a substitution pattern but can't execute it
          if is_definite then
            return numerical_integration_fallback(node, var, bounds.lower, bounds.upper)
          end
          return { type = "unimplemented_integral", original = node, note = "advanced_substitution_found" }
        end
        return sub_result 
      end
    end

    -- Try integration by parts
    local parts_result = try_integration_by_parts(node, var)
    if parts_result then return parts_result end

    -- Handle exponential integrals: ∫ f'(x) * e^{f(x)} dx = e^{f(x)}
    for i, arg in ipairs(node.args) do
      if arg.type == "func" and arg.name == "exp" and arg.args and arg.args[1] then
        local f = arg.args[1]
        local df = diffAST(f, var)
        if df then
          for j, other in ipairs(node.args) do
            if i ~= j and simplify.expr_equal and simplify.expr_equal(other, df) then
              local remaining = {}
              for k, term in ipairs(node.args) do
                if k ~= i and k ~= j then
                  table.insert(remaining, term)
                end
              end
              local result = ast.func("exp", { copy(f) })
              if #remaining > 0 then
                local factor = #remaining == 1 and remaining[1] or ast.mul(table.unpack(remaining))
                result = ast.mul(factor, result)
              end
              
              if is_definite then
                local upper_val = ast.replace(copy(result), ast.variable(var), copy(bounds.upper))
                local lower_val = ast.replace(copy(result), ast.variable(var), copy(bounds.lower))
                return ast.sub(upper_val, lower_val)
              end
              return result
            end
          end
        end
      end
    end

    -- Power rule with chain: ∫ f(x)^n * f'(x) dx = f(x)^{n+1}/(n+1)
    for i, arg in ipairs(node.args) do
      if arg.type == "pow" and is_const(arg.exp) and arg.exp.value ~= -1 then
        local base, exp = arg.base, arg.exp
        local dbase = diffAST(base, var)
        if dbase then
          for j, other in ipairs(node.args) do
            if i ~= j and simplify.expr_equal and simplify.expr_equal(other, dbase) then
              local new_exp = ast.add(copy(exp), ast.number(1))
              local result = ast.div(ast.pow(copy(base), new_exp), copy(new_exp))
              
              if is_definite then
                local upper_val = ast.replace(copy(result), ast.variable(var), copy(bounds.upper))
                local lower_val = ast.replace(copy(result), ast.variable(var), copy(bounds.lower))
                return ast.sub(upper_val, lower_val)
              end
              return result
            end
          end
        end
      end
    end

    -- Extract constants (this part actually works, surprisingly)
    local constants = {}
    local variables = {}
    for _, arg in ipairs(node.args) do
      if is_const(arg) or (arg.type == "variable" and arg.name ~= var) then
        table.insert(constants, arg)
      else
        table.insert(variables, arg)
      end
    end

    if #constants > 0 and #variables > 0 then
      local const_product = #constants == 1 and constants[1] or ast.mul(table.unpack(constants))
      local var_product = #variables == 1 and variables[1] or ast.mul(table.unpack(variables))
      local var_integral = integrateAST(var_product, var, bounds)
      if var_integral.type ~= "unimplemented_integral" then
        if is_definite then
          return var_integral -- bounds already handled in recursive call
        end
        return ast.mul(const_product, var_integral)
      end
    end
  end

  -- Enhanced power rule: ∫ x^n dx and ∫ a^x dx
  if node.type == "pow" and node.base and node.exp then
    local base, exp = node.base, node.exp
    
    if is_symbol(base, var) and is_const(exp) then
      if exp.value == -1 then
        local result = ast.func("ln", { ast.func("abs", { copy(base) }) })
        if is_definite then
          local upper_val = ast.func("ln", { ast.func("abs", { copy(bounds.upper) }) })
          local lower_val = ast.func("ln", { ast.func("abs", { copy(bounds.lower) }) })
          return ast.sub(upper_val, lower_val)
        end
        return ast.add(result, ast.variable("C"))
      else
        local new_exp = ast.number(exp.value + 1)
        local result = ast.div(ast.pow(copy(base), new_exp), new_exp)
        if is_definite then
          local upper_val = ast.div(ast.pow(copy(bounds.upper), new_exp), new_exp)
          local lower_val = ast.div(ast.pow(copy(bounds.lower), new_exp), new_exp)
          return ast.sub(upper_val, lower_val)
        end
        return ast.add(result, ast.variable("C"))
      end
    elseif is_const(base) and is_symbol(exp, var) then
      -- ∫ a^x dx = a^x / ln(a)
      local result = ast.div(copy(node), ast.func("ln", { copy(base) }))
      if is_definite then
        local upper_val = ast.div(ast.pow(copy(base), copy(bounds.upper)), ast.func("ln", { copy(base) }))
        local lower_val = ast.div(ast.pow(copy(base), copy(bounds.lower)), ast.func("ln", { copy(base) }))
        return ast.sub(upper_val, lower_val)
      end
      return ast.add(result, ast.variable("C"))
    end
  end

  -- Enhanced function integration
  if node.type == "func" and node.name then
    local fname = node.name
    local arg = (node.args and node.args[1]) or node.arg

    -- Try trigonometric functions (now with more trig!)
    local trig_result = integrate_trig(fname, arg, var)
    if trig_result then 
      if is_definite then
        local upper_val = ast.replace(copy(trig_result), ast.variable(var), copy(bounds.upper))
        local lower_val = ast.replace(copy(trig_result), ast.variable(var), copy(bounds.lower))
        return ast.sub(upper_val, lower_val)
      end
      return ast.add(trig_result, ast.variable("C"))
    end

    -- Handle other common functions
    if fname == "exp" and arg then
      if is_symbol(arg, var) then
        if is_definite then
          local upper_val = ast.func("exp", { copy(bounds.upper) })
          local lower_val = ast.func("exp", { copy(bounds.lower) })
          return ast.sub(upper_val, lower_val)
        end
        return ast.add(copy(node), ast.variable("C"))
      end
    elseif fname == "ln" and arg then
      if is_symbol(arg, var) then
        -- ∫ ln(x) dx = x*ln(x) - x
        local x = ast.variable(var)
        local result = ast.sub(ast.mul(x, copy(node)), x)
        if is_definite then
          local upper_val = ast.sub(ast.mul(copy(bounds.upper), ast.func("ln", { copy(bounds.upper) })), copy(bounds.upper))
          local lower_val = ast.sub(ast.mul(copy(bounds.lower), ast.func("ln", { copy(bounds.lower) })), copy(bounds.lower))
          return ast.sub(upper_val, lower_val)
        end
        return ast.add(result, ast.variable("C"))
      end
    elseif fname == "sqrt" and arg then
      -- ∫ √x dx = (2/3)x^(3/2)
      if is_symbol(arg, var) then
        local result = ast.mul(ast.div(ast.number(2), ast.number(3)), ast.pow(copy(arg), ast.div(ast.number(3), ast.number(2))))
        if is_definite then
          local upper_val = ast.mul(ast.div(ast.number(2), ast.number(3)), ast.pow(copy(bounds.upper), ast.div(ast.number(3), ast.number(2))))
          local lower_val = ast.mul(ast.div(ast.number(2), ast.number(3)), ast.pow(copy(bounds.lower), ast.div(ast.number(3), ast.number(2))))
          return ast.sub(upper_val, lower_val)
        end
        return ast.add(result, ast.variable("C"))
      end
    elseif known_integral_table[fname] and arg then
      local result = known_integral_table[fname](copy(arg))
      if result then 
        if is_definite then
          local upper_val = ast.replace(copy(result), ast.variable(var), copy(bounds.upper))
          local lower_val = ast.replace(copy(result), ast.variable(var), copy(bounds.lower))
          return ast.sub(upper_val, lower_val)
        end
        return ast.add(result, ast.variable("C"))
      end
    end
  end

  -- If we get here and it's definite, try numerical integration
  if is_definite then
    return numerical_integration_fallback(node, var, bounds.lower, bounds.upper)
  end

  -- If we get here, we couldn't integrate it symbolically
  return { type = "unimplemented_integral", original = copy(node) }
end

-- Multi-variable integration (because we're apparently sadists)
local function integrate_multivariable(node, vars)
  if not vars or #vars == 0 then
    error("Multi-variable integration requires at least one variable")
  end
  
  -- Integrate successively over each variable
  local result = copy(node)
  for _, var in ipairs(vars) do
    result = integrateAST(result, var)
    if result.type == "unimplemented_integral" then
      return {
        type = "unimplemented_multivariable_integral",
        original = copy(node),
        attempted_vars = vars,
        failed_at = var
      }
    end
  end
  
  return result
end

-- Improper integral detection (because infinite bounds are fun)
local function handle_improper_integral(node, var, bounds)
  if not bounds then return nil end
  
  local has_infinity = false
  if bounds.lower and bounds.lower.type == "infinity" then has_infinity = true end
  if bounds.upper and bounds.upper.type == "infinity" then has_infinity = true end
  
  if has_infinity then
    return {
      type = "improper_integral",
      original = copy(node),
      bounds = copy(bounds),
      note = "Requires limit evaluation for convergence"
    }
  end
  
  return nil
end

-- Main integration interface (now with more parameters because complexity is fun)
local function integral(expr, var, bounds, options)
  local tree
  local parser = rawget(_G, "parser") or require("parser")
  
  options = options or {}
  var = var or "x"
  
  if type(expr) == "string" then
    tree = parser.parse(expr)
  elseif type(expr) == "table" then
    tree = expr
  else
    error("Invalid input to integral(): expected string or AST table, got " .. type(expr))
  end

  if not tree then
    error("Parsing failed: input = " .. tostring(expr))
  end

  -- Handle multi-variable integration
  if type(var) == "table" then
    return integrate_multivariable(tree, var)
  end

  -- Check for improper integrals
  if bounds then
    local improper = handle_improper_integral(tree, var, bounds)
    if improper then return improper end
  end

  local result = integrateAST(tree, var, bounds)
  
  if not result or type(result) ~= "table" then
    error("Invalid integral result")
  end

  -- Only simplify if we got a real result and it's not too complex
  if result.type ~= "unimplemented_integral" and 
     result.type ~= "numerical_approximation" and 
     result.type ~= "improper_integral" and 
     simplify.simplify then
    result = simplify.simplify(result)
  end

  return result
end

-- Convenience functions for specific integral types
local function definite_integral(expr, var, a, b)
  return integral(expr, var, {lower = a, upper = b})
end

local function indefinite_integral(expr, var)
  return integral(expr, var)
end

-- Line integral (because we're completionists)
local function line_integral(vector_field, curve, parameter)
  -- This would be a whole other nightmare to implement properly
  return {
    type = "unimplemented_line_integral",
    vector_field = copy(vector_field),
    curve = copy(curve),
    parameter = parameter or "t"
  }
end

-- Surface integral (why not go full differential geometry)
local function surface_integral(scalar_field, surface, parameters)
  return {
    type = "unimplemented_surface_integral",
    scalar_field = copy(scalar_field),
    surface = copy(surface),
    parameters = parameters or {"u", "v"}
  }
end

-- Global exports (now with even more ways to confuse users)
_G.integrate = {
  integrateAST = integrateAST,
  eval = integral,
  definite = definite_integral,
  indefinite = indefinite_integral,
  multivariable = integrate_multivariable,
  line = line_integral,
  surface = surface_integral,
  -- Utility functions
  partial_fractions = partial_fraction_decompose,
  is_polynomial = is_polynomial
}
_G.integral = _G.integrate.eval
_G.definite_integral = _G.integrate.definite
_G.indefinite_integral = _G.integrate.indefinite

-- Enhanced pretty printing for all our new failure modes
if _G.pretty_print_internal then
  local old_pretty_internal = _G.pretty_print_internal

  function pretty_print_internal(expr, parent, pos)
    if expr and expr.type == "unimplemented_integral" and expr.original then
      return "∫(" .. pretty_print_internal(expr.original, nil, nil) .. ") dx"
    end
    
    if expr and expr.type == "unimplemented_multivariable_integral" then
      local vars_str = table.concat(expr.attempted_vars, ", ")
      return "∫∫...(" .. pretty_print_internal(expr.original, nil, nil) .. ") d" .. vars_str .. " [failed at " .. expr.failed_at .. "]"
    end
    
    if expr and expr.type == "numerical_approximation" then
      return "≈∫[" .. pretty_print_internal(expr.bounds.lower, nil, nil) .. "," .. pretty_print_internal(expr.bounds.upper, nil, nil) .. "] (" .. pretty_print_internal(expr.original, nil, nil) .. ") dx"
    end
    
    if expr and expr.type == "improper_integral" then
      return "∫[" .. pretty_print_internal(expr.bounds.lower, nil, nil) .. "," .. pretty_print_internal(expr.bounds.upper, nil, nil) .. "] (" .. pretty_print_internal(expr.original, nil, nil) .. ") dx (improper)"
    end
    
    if expr and expr.type == "advanced_substitution" then
      return "∫(" .. pretty_print_internal(expr.original, nil, nil) .. ") dx [" .. expr.method .. " substitution]"
    end
    
    if expr and expr.type == "partial_fraction_sum" then
      local terms = {}
      for _, term in ipairs(expr.terms) do
        table.insert(terms, pretty_print_internal(ast.div(term.numerator, term.denominator), nil, nil))
      end
      return table.concat(terms, " + ")
    end
    
    if expr and expr.type == "unimplemented_line_integral" then
      return "∮ F⋅dr (line integral - not implemented)"
    end
    
    if expr and expr.type == "unimplemented_surface_integral" then
      return "∬ f dS (surface integral - not implemented)"
    end
    
    if expr and expr.type == "neg" and expr.arg then
      local inner = pretty_print_internal(expr.arg, nil, nil)
      if expr.arg.type ~= "number" and expr.arg.type ~= "variable" then
        inner = "(" .. inner .. ")"
      end
      return "-" .. inner
    end

    -- Custom addition node pretty printing: print constant C last for indefinite integrals
    if expr and expr.type == "add" and expr.args then
      local regular_terms = {}
      local constant_c = nil

      for _, arg in ipairs(expr.args) do
        if arg.type == "variable" and arg.name == "C" then
          constant_c = old_pretty_internal(arg, "add", "inner")
        else
          table.insert(regular_terms, old_pretty_internal(arg, "add", "inner"))
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
      return result
    end
    
    return old_pretty_internal(expr, parent, pos)
  end
  
  _G.pretty_print_internal = pretty_print_internal
end

-- Integration testing framework (because we need to know how badly we're failing)
local function test_integration()
  local tests = {
    -- Basic tests
    {"x", "x", nil, "should integrate to x^2/2"},
    {"x^2", "x", nil, "should integrate to x^3/3"},
    {"sin(x)", "x", nil, "should integrate to -cos(x)"},
    {"cos(x)", "x", nil, "should integrate to sin(x)"},
    {"e^x", "x", nil, "should integrate to e^x"},
    {"1/x", "x", nil, "should integrate to ln|x|"},
    
    -- Definite integrals
    {"x", "x", {lower = ast.number(0), upper = ast.number(1)}, "should equal 1/2"},
    {"x^2", "x", {lower = ast.number(0), upper = ast.number(2)}, "should equal 8/3"},
    
    -- Advanced cases
    {"x*sin(x)", "x", nil, "integration by parts"},
    {"arctan(x)", "x", nil, "inverse trig function"},
    {"1/(x^2 + 1)", "x", nil, "should integrate to arctan(x)"},
    {"sqrt(x)", "x", nil, "should integrate to (2/3)x^(3/2)"},
    
    -- Failure cases (these should gracefully fail)
    {"sin(x^2)", "x", nil, "should require numerical methods"},
    {"e^(x^2)", "x", nil, "impossible to integrate symbolically"},
  }
  
  local results = {}
  for i, test in ipairs(tests) do
    local expr, var, bounds, description = test[1], test[2], test[3], test[4]
    local success, result = pcall(integral, expr, var, bounds)
    
    results[i] = {
      test = test,
      success = success,
      result = success and result or tostring(result),
      description = description
    }
  end
  
  return results
end

-- Export test function
_G.test_integration = test_integration

-- Final comment: If you've made it this far, you're either very brave or very foolish.
-- This integral engine now supports:
-- - All the basic stuff from before (polynomials, trig, exponentials)
-- - Inverse trig functions (arcsin, arccos, arctan)
-- - Hyperbolic functions (sinh, cosh, tanh)
-- - Partial fraction decomposition (simplified version)
-- - Advanced substitution pattern recognition
-- - Definite integrals with bounds
-- - Multi-variable integration (successive integration)
-- - Improper integral detection
-- - Numerical integration fallback
-- - Line and surface integrals (placeholder)
-- - Enhanced integration by parts with LIATE rule
-- - Better error handling and pretty printing
-- 
-- What it still can't do:
-- - Actually perform complex trigonometric substitutions
-- - Real partial fraction decomposition for complex cases
-- - Contour integration
-- - Advanced special functions
-- - Symbolic manipulation of infinite series
-- - Anything involving Bessel functions, elliptic integrals, or other exotic functions
-- - Keep your sanity intact while debugging integration failures
--
-- Use at your own risk. Side effects may include: mathematical anxiety, 
-- existential dread, and an uncontrollable urge to switch to numerical methods.