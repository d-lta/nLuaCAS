-- integrate.lua

local ast = rawget(_G, "ast") or require("ast")
local diffAST = rawget(_G, "diffAST") or error("diffAST: differentiation function required for integration by parts")
local trig = rawget(_G, "trig")
local simplify = rawget(_G, "simplify") or require("simplify")
local errors = _G.errors

-- Helper to format expressions nicely for steps
local function format_expr(ast_node)
  return (simplify and simplify.pretty_print(ast_node)) or ast.tostring(ast_node)
end

-- Expanded symbolic integral lookup
local known_integral_table = {
  arcsin = function(arg) 
    return ast.add(ast.mul(arg, ast.func("arcsin", {copy(arg)})), ast.func("sqrt", {ast.sub(ast.number(1), ast.pow(copy(arg), ast.number(2)))}))
  end,
  arccos = function(arg)
    return ast.sub(ast.mul(arg, ast.func("arccos", {copy(arg)})), ast.func("sqrt", {ast.sub(ast.number(1), ast.pow(copy(arg), ast.number(2)))}))
  end,
  arctan = function(arg)
    return ast.sub(ast.mul(arg, ast.func("arctan", {copy(arg)})), ast.div(ast.func("ln", {ast.add(ast.number(1), ast.pow(copy(arg), ast.number(2)))}), ast.number(2)))
  end,
  sinh = function(arg) return ast.func("cosh", {copy(arg)}) end,
  cosh = function(arg) return ast.func("sinh", {copy(arg)}) end,
  tanh = function(arg) return ast.func("ln", {ast.func("cosh", {copy(arg)})}) end,
  sqrt = function(arg)
    if is_symbol(arg, "x") then
      return ast.div(ast.mul(ast.number(2), ast.pow(arg, ast.div(ast.number(3), ast.number(2)))), ast.number(3))
    end
    return nil
  end
}

local enable_substitution = true  
local enable_advanced_symbolics = true
local enable_partial_fractions = true
local enable_definite_integrals = true

-- Utility functions
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

local function is_trivial(node, var)
  return (node.type == "number") or 
         (node.type == "variable" and node.name == var) or
         (node.type == "variable" and node.name ~= var)
end

-- Check if expression contains only polynomials
local function is_polynomial(node, var)
  if not node then return false end
  if node.type == "number" then return true end
  if node.type == "variable" then return node.name == var or true end
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

-- Partial fraction decomposition (simplified)
local function partial_fraction_decompose(numerator, denominator, var)
  if not denominator or denominator.type ~= "mul" then return nil end
  if not denominator.args or #denominator.args ~= 2 then return nil end
  
  local factors = {}
  for _, factor in ipairs(denominator.args) do
    if factor.type == "add" and factor.args and #factor.args == 2 then
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

-- pattern matching
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

-- Advanced substitution patterns
local function try_advanced_substitution(node, var)
  if not enable_advanced_symbolics then return nil end
  
  local sqrt_patterns = {
    {
      pattern = ast.func("sqrt", {ast.sub(ast.pow(ast.wildcard("a"), ast.number(2)), ast.pow(ast.variable(var), ast.number(2)))}),
      substitution = "trig_sin"
    },
    {
      pattern = ast.func("sqrt", {ast.add(ast.pow(ast.wildcard("a"), ast.number(2)), ast.pow(ast.variable(var), ast.number(2)))}),
      substitution = "trig_tan"
    },
    {
      pattern = ast.func("sqrt", {ast.sub(ast.pow(ast.variable(var), ast.number(2)), ast.pow(ast.wildcard("a"), ast.number(2)))}),
      substitution = "trig_sec"
    }
  }
  
  for _, sub_pattern in ipairs(sqrt_patterns) do
    local bindings = {}
    if pattern_match(node, sub_pattern.pattern, bindings) then
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


local function try_substitution(node, var)
  if not node or node.type ~= "mul" or not node.args then 
    return nil 
  end
  
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

-- Integration by parts with steps
local function try_integration_by_parts(node, var, depth, steps)
  if not node or node.type ~= "mul" or not node.args or #node.args < 2 then 
    return nil 
  end
  
  local function get_integration_priority(expr)
    if expr.type == "func" then
      if expr.name == "ln" then return 1 end
      if expr.name:match("^arc") then return 2 end
      if expr.name:match("^a?sinh?$") or expr.name:match("^a?cosh?$") then return 2 end
      if expr.name == "sin" or expr.name == "cos" or expr.name == "tan" then return 4 end
      if expr.name == "exp" then return 5 end
    elseif expr.type == "pow" and is_symbol(expr.base, var) then
      return 3
    elseif is_symbol(expr, var) then
      return 3
    end
    return 6
  end
  
  local best_u, best_dv
  local best_priority = math.huge
  
  for i = 1, #node.args do
    local priority = get_integration_priority(node.args[i])
    if priority < best_priority then
      best_priority = priority
      best_u = node.args[i]
      local dv_args = {}
      for j = 1, #node.args do
        if i ~= j then table.insert(dv_args, node.args[j]) end
      end
      best_dv = #dv_args == 1 and dv_args[1] or ast.mul(table.unpack(dv_args))
    end
  end
  
  if not best_u or not best_dv then return nil end
  
  -- Add integration by parts step
  table.insert(steps, {
    description = "∫" .. format_expr(best_u) .. " · " .. format_expr(best_dv) .. " d" .. var .. 
                 " = " .. format_expr(best_u) .. " · ∫" .. format_expr(best_dv) .. " d" .. var .. 
                 " - ∫(d/d" .. var .. "(" .. format_expr(best_u) .. ") · ∫" .. format_expr(best_dv) .. " d" .. var .. ") d" .. var
  })
  
  local V, V_steps = integrateAST(best_dv, var, nil, depth + 1)
  if V_steps then
    for _, s in ipairs(V_steps) do table.insert(steps, s) end
  end
  
  local du = diffAST(best_u, var)
  
  if not V or not du or V.type == "unimplemented_integral" then
    return nil
  end
  
  table.insert(steps, {
    description = "u = " .. format_expr(best_u) .. ", du = " .. format_expr(du) .. " d" .. var .. 
                 ", v = " .. format_expr(V)
  })
  
  local second_integral, second_steps = integrateAST(ast.mul(V, du), var, nil, depth + 1)
  if second_steps then
    for _, s in ipairs(second_steps) do table.insert(steps, s) end
  end
  
  if simplify.expr_equal(second_integral, node) then
    return nil
  end
  if second_integral and second_integral.type ~= "unimplemented_integral" then
    local result = ast.sub(ast.mul(best_u, V), second_integral)
    table.insert(steps, {
      description = "= " .. format_expr(best_u) .. " · " .. format_expr(V) .. 
                   " - " .. format_expr(second_integral) .. " = " .. format_expr(result)
    })
    return result
  end
  
  return nil
end

-- trig integration with steps
local function integrate_trig(fname, arg, var, steps)
  if not fname or not arg then return nil end
  
  local chain_factor = nil
  if arg.type ~= "variable" or arg.name ~= var then
    local darg = diffAST(arg, var)
    if not darg then return nil end
    chain_factor = darg
  end
  
  local base_integral
  if fname == "sin" then
    base_integral = ast.neg(ast.func("cos", { copy(arg) }))
    if is_symbol(arg, var) then
      table.insert(steps, { description = "∫sin(" .. format_expr(arg) .. ") d" .. var .. " = -cos(" .. format_expr(arg) .. ")" })
    end
  elseif fname == "cos" then
    base_integral = ast.func("sin", { copy(arg) })
    if is_symbol(arg, var) then
      table.insert(steps, { description = "∫cos(" .. format_expr(arg) .. ") d" .. var .. " = sin(" .. format_expr(arg) .. ")" })
    end
  elseif fname == "tan" then
    base_integral = ast.neg(ast.func("ln", { ast.func("cos", { copy(arg) }) }))
    if is_symbol(arg, var) then
      table.insert(steps, { description = "∫tan(" .. format_expr(arg) .. ") d" .. var .. " = -ln|cos(" .. format_expr(arg) .. ")|" })
    end
  elseif fname == "cot" then
    base_integral = ast.func("ln", { ast.func("sin", { copy(arg) }) })
    if is_symbol(arg, var) then
      table.insert(steps, { description = "∫cot(" .. format_expr(arg) .. ") d" .. var .. " = ln|sin(" .. format_expr(arg) .. ")|" })
    end
  elseif fname == "sec" then
    base_integral = ast.func("ln", { ast.add(ast.func("sec", { copy(arg) }), ast.func("tan", { copy(arg) })) })
    if is_symbol(arg, var) then
      table.insert(steps, { description = "∫sec(" .. format_expr(arg) .. ") d" .. var .. " = ln|sec(" .. format_expr(arg) .. ") + tan(" .. format_expr(arg) .. ")|" })
    end
  elseif fname == "csc" then
    base_integral = ast.neg(ast.func("ln", { ast.add(ast.func("csc", { copy(arg) }), ast.func("cot", { copy(arg) })) }))
    if is_symbol(arg, var) then
      table.insert(steps, { description = "∫csc(" .. format_expr(arg) .. ") d" .. var .. " = -ln|csc(" .. format_expr(arg) .. ") + cot(" .. format_expr(arg) .. ")|" })
    end
  elseif fname == "arcsin" then
    if is_symbol(arg, var) then
      base_integral = ast.add(ast.mul(copy(arg), ast.func("arcsin", {copy(arg)})), 
                     ast.func("sqrt", {ast.sub(ast.number(1), ast.pow(copy(arg), ast.number(2)))}))
      table.insert(steps, { description = "∫arcsin(" .. format_expr(arg) .. ") d" .. var .. " = " .. format_expr(arg) .. "·arcsin(" .. format_expr(arg) .. ") + √(1-" .. format_expr(arg) .. "²)" })
    end
  elseif fname == "arccos" then
    if is_symbol(arg, var) then
      base_integral = ast.sub(ast.mul(copy(arg), ast.func("arccos", {copy(arg)})), 
                     ast.func("sqrt", {ast.sub(ast.number(1), ast.pow(copy(arg), ast.number(2)))}))
      table.insert(steps, { description = "∫arccos(" .. format_expr(arg) .. ") d" .. var .. " = " .. format_expr(arg) .. "·arccos(" .. format_expr(arg) .. ") - √(1-" .. format_expr(arg) .. "²)" })
    end
  elseif fname == "arctan" then
    if is_symbol(arg, var) then
      base_integral = ast.sub(ast.mul(copy(arg), ast.func("arctan", {copy(arg)})), 
                     ast.div(ast.func("ln", {ast.add(ast.number(1), ast.pow(copy(arg), ast.number(2)))}), ast.number(2)))
      table.insert(steps, { description = "∫arctan(" .. format_expr(arg) .. ") d" .. var .. " = " .. format_expr(arg) .. "·arctan(" .. format_expr(arg) .. ") - ½ln(1+" .. format_expr(arg) .. "²)" })
    end
  elseif fname == "sinh" then
    base_integral = ast.func("cosh", { copy(arg) })
    if is_symbol(arg, var) then
      table.insert(steps, { description = "∫sinh(" .. format_expr(arg) .. ") d" .. var .. " = cosh(" .. format_expr(arg) .. ")" })
    end
  elseif fname == "cosh" then
    base_integral = ast.func("sinh", { copy(arg) })
    if is_symbol(arg, var) then
      table.insert(steps, { description = "∫cosh(" .. format_expr(arg) .. ") d" .. var .. " = sinh(" .. format_expr(arg) .. ")" })
    end
  elseif fname == "tanh" then
    base_integral = ast.func("ln", { ast.func("cosh", { copy(arg) }) })
    if is_symbol(arg, var) then
      table.insert(steps, { description = "∫tanh(" .. format_expr(arg) .. ") d" .. var .. " = ln|cosh(" .. format_expr(arg) .. ")|" })
    end
  else
    return nil
  end
  
  if chain_factor and base_integral then
    return nil
  end
  
  return base_integral
end

-- Numerical integration fallback
local function numerical_integration_fallback(node, var, a, b)
  if not enable_definite_integrals or not a or not b then
    return {
      type = "numerical_integration_required",
      original = copy(node),
      bounds = {lower = a, upper = b}
    }
  end
  
  return {
    type = "numerical_approximation",
    method = "simpsons_rule",
    original = copy(node),
    bounds = {lower = a, upper = b}
  }
end

-- Core integration function with mathematical solution steps
local function integrateAST(node, var, bounds, depth)
  depth = depth or 0
  local steps = {}
  local MAX_INTEGRAL_RECURSION_DEPTH = 100

  if depth > MAX_INTEGRAL_RECURSION_DEPTH then
    _G.errors.throw("system(recursion_depth_exceeded)")
  end

  if not node then 
    _G.errors.throw("int(unimplemented_node)", "nil_node")
  end
  
  var = var or "x"
  
  local function add_step(description)
    table.insert(steps, { description = description })
  end

  -- Handle definite integral nodes
  if node.type == "integral" then
      local integrand = node.integrand
      local integrate_var = node.respect_to.name
      local lower_bound_ast = node.lower_bound
      local upper_bound_ast = node.upper_bound

      add_step("∫[" .. format_expr(lower_bound_ast) .. " to " .. format_expr(upper_bound_ast) .. "] " .. 
               format_expr(integrand) .. " d" .. integrate_var)

      local antiderivative, antiderivative_steps = integrateAST(integrand, integrate_var, nil, depth + 1)
      if antiderivative_steps then
        for _, s in ipairs(antiderivative_steps) do table.insert(steps, s) end
      end

      if antiderivative.type == "unimplemented_integral" then
          _G.errors.throw("int(unimplemented_func)", simplify.pretty_print(integrand))
      end

      if antiderivative.type == "number" then
          return antiderivative, steps
      end

      add_step("F(" .. integrate_var .. ") = " .. format_expr(antiderivative))

      local upper_val_status, upper_val_raw = pcall(ast.eval_numeric, ast.substitute(copy(antiderivative), ast.variable(integrate_var), copy(upper_bound_ast)), {})
      local lower_val_status, lower_val_raw = pcall(ast.eval_numeric, ast.substitute(copy(antiderivative), ast.variable(integrate_var), copy(lower_bound_ast)), {})

      if not upper_val_status or not lower_val_status then
          if upper_val_raw and tostring(upper_val_raw):find("Unbound variable") then
              _G.errors.throw("eval(unbound_variable)", tostring(upper_val_raw):match("Unbound variable: (.+)"))
          elseif lower_val_raw and tostring(lower_val_raw):find("Unbound variable") then
              _G.errors.throw("eval(unbound_variable)", tostring(lower_val_raw):match("Unbound variable: (.+)"))
          else
              _G.errors.throw("int(definite_bounds_undefined)", "evaluation failed")
          end
      end
      
      local upper_val = upper_val_raw
      local lower_val = lower_val_raw

      if upper_val ~= upper_val or lower_val ~= lower_val then
        _G.errors.throw("int(definite_bounds_nan)", simplify.pretty_print(integrand))
      end
      if upper_val == math.huge or upper_val == -math.huge or lower_val == math.huge or lower_val == -math.huge then
        _G.errors.throw("int(improper_integral_unresolved)", simplify.pretty_print(integrand))
      end

      add_step("= F(" .. format_expr(upper_bound_ast) .. ") - F(" .. format_expr(lower_bound_ast) .. ")")
      add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))

      return ast.number(upper_val - lower_val), steps
  end

  local is_definite = bounds and bounds.lower and bounds.upper
  
  -- Constants: ∫c dx = cx
  if node.type == "number" then
    local result = ast.mul(copy(node), ast.variable(var))
    if is_trivial(node, var) and node.value ~= 1 and node.value ~= 0 then
      add_step("∫" .. format_expr(node) .. " d" .. var .. " = " .. format_expr(node) .. var)
    end
    
    if is_definite then
      local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
      local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
      add_step("= [" .. format_expr(node) .. var .. "]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
      add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
      return ast.number(upper_val - lower_val), steps
    end
    return ast.add(result, ast.variable("C")), steps
  end

  -- Variables: ∫x dx = x²/2, ∫y dx = yx
  if node.type == "variable" then
    if node.name == var then
      local result = ast.div(ast.pow(ast.variable(var), ast.number(2)), ast.number(2))
      add_step("∫" .. var .. " d" .. var .. " = " .. var .. "²/2")
      
      if is_definite then
        local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
        local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
        add_step("= [" .. var .. "²/2]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
        add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
        return ast.number(upper_val - lower_val), steps
      end
      return ast.add(result, ast.variable("C")), steps
    else
      local result = ast.mul(copy(node), ast.variable(var))
      add_step("∫" .. node.name .. " d" .. var .. " = " .. node.name .. var)
      
      if is_definite then
        local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
        local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
        add_step("= [" .. node.name .. var .. "]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
        add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
        return ast.number(upper_val - lower_val), steps
      end
      return ast.add(result, ast.variable("C")), steps
    end
  end

  -- Addition: ∫(u + v) dx = ∫u dx + ∫v dx
  if node.type == "add" and node.args then
    add_step("∫(" .. format_expr(node) .. ") d" .. var .. " = " .. 
             table.concat((function()
               local parts = {}
               for i, term in ipairs(node.args) do
                 table.insert(parts, "∫" .. format_expr(term) .. " d" .. var)
               end
               return parts
             end)(), " + "))
    
    local results = {}
    for i, term in ipairs(node.args) do
      local integral_term, term_steps = integrateAST(term, var, bounds, depth + 1)
      if term_steps then
        for _, s in ipairs(term_steps) do table.insert(steps, s) end
      end
      if integral_term.type == "unimplemented_integral" then
        if is_definite then
          return numerical_integration_fallback(node, var, bounds.lower, bounds.upper), steps
        end
        return { type = "unimplemented_integral", original = node }, steps
      end
      table.insert(results, integral_term)
    end
    
    if is_definite then
      local sum = 0
      for _, res_node in ipairs(results) do
          if res_node.type == "number" then
              sum = sum + res_node.value
          else
              _G.errors.throw("int(definite_bounds_undefined)", "sum of non-numeric definite terms")
          end
      end
      add_step("= " .. sum)
      return ast.number(sum), steps
    end
    
    local result = ast.add(table.unpack(results))
    add_step("= " .. format_expr(result) .. " + C")
    return ast.add(result, ast.variable("C")), steps
  end

  -- Subtraction: ∫(u - v) dx = ∫u dx - ∫v dx  
  if node.type == "sub" and node.left and node.right then
    add_step("∫(" .. format_expr(node.left) .. " - " .. format_expr(node.right) .. ") d" .. var .. 
             " = ∫" .. format_expr(node.left) .. " d" .. var .. " - ∫" .. format_expr(node.right) .. " d" .. var)
    
    local left_int, left_steps = integrateAST(node.left, var, bounds, depth + 1)
    if left_steps then
      for _, s in ipairs(left_steps) do table.insert(steps, s) end
    end
    local right_int, right_steps = integrateAST(node.right, var, bounds, depth + 1)
    if right_steps then
      for _, s in ipairs(right_steps) do table.insert(steps, s) end
    end
    
    if left_int.type == "unimplemented_integral" or right_int.type == "unimplemented_integral" then
      if is_definite then
        return numerical_integration_fallback(node, var, bounds.lower, bounds.upper), steps
      end
      return { type = "unimplemented_integral", original = node }, steps
    end
    
    if is_definite then
      local diff_val = 0
      if left_int.type == "number" and right_int.type == "number" then
          diff_val = left_int.value - right_int.value
      else
          _G.errors.throw("int(definite_bounds_undefined)", "difference of non-numeric definite terms")
      end
      add_step("= " .. diff_val)
      return ast.number(diff_val), steps
    end
    
    local result = ast.sub(left_int, right_int)
    add_step("= " .. format_expr(result) .. " + C")
    return ast.add(result, ast.variable("C")), steps
  end

  -- Division: Handle f'(x)/f(x) and partial fractions
  if node.type == "div" and node.left and node.right then
    local num, denom = node.left, node.right
    
    -- Check for f'(x)/f(x) pattern
    local ddenom = diffAST(denom, var)
    if ddenom and simplify.expr_equal and simplify.expr_equal(num, ddenom) then
      local result = ast.func("ln", { ast.func("abs", { copy(denom) }) })
      add_step("∫(" .. format_expr(num) .. ")/(" .. format_expr(denom) .. ") d" .. var .. 
               " = ln|" .. format_expr(denom) .. "| (since numerator is derivative of denominator)")
      
      if is_definite then
        local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
        local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
        add_step("= [ln|" .. format_expr(denom) .. "|]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
        add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
        return ast.number(upper_val - lower_val), steps
      end
      return result, steps
    end
    
    -- Try partial fraction decomposition
    if enable_partial_fractions and is_polynomial(num, var) and is_polynomial(denom, var) then
      local partial_fractions = partial_fraction_decompose(num, denom, var)
      if partial_fractions and partial_fractions.type == "partial_fraction_sum" then
        add_step("Using partial fraction decomposition:")
        local results = {}
        for _, term in ipairs(partial_fractions.terms) do
          local term_integral, term_steps = integrateAST(ast.div(term.numerator, term.denominator), var, bounds, depth + 1)
          if term_steps then
            for _, s in ipairs(term_steps) do table.insert(steps, s) end
          end
          if term_integral.type == "unimplemented_integral" then
            break
          end
          table.insert(results, term_integral)
        end
        if #results == #partial_fractions.terms then
          if is_definite then
              local sum = 0
              for _, res_node in ipairs(results) do
                  if res_node.type == "number" then
                      sum = sum + res_node.value
                  else
                      _G.errors.throw("int(definite_bounds_undefined)", "partial_fraction_sum_non_numeric")
                  end
              end
              add_step("= " .. sum)
              return ast.number(sum), steps
          end
          local result = ast.add(table.unpack(results))
          add_step("= " .. format_expr(result))
          return result, steps
        end
      end
    end
    
    -- Convert to multiplication
    return integrateAST(ast.mul(node.left, ast.pow(node.right, ast.number(-1))), var, bounds, depth + 1)
  end

  -- Enhanced multiplication handling
  if node.type == "mul" and node.args then
    -- Try substitution first
    if enable_substitution then
      local sub_result = try_substitution(node, var)
      if sub_result then 
        if sub_result.type == "advanced_substitution" then
          add_step("Advanced substitution pattern detected: " .. sub_result.method)
          if is_definite then
            return numerical_integration_fallback(node, var, bounds.lower, bounds.upper), steps
          end
          return { type = "unimplemented_integral", original = node, note = "advanced_substitution_found" }, steps
        end
        return sub_result, steps
      end
    end

    -- Try integration by parts
    local parts_result = try_integration_by_parts(node, var, depth + 1, steps)
    if parts_result then return parts_result, steps end

    -- Handle exponential integrals: ∫f'(x)·e^{f(x)} dx = e^{f(x)}
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
              local result = ast.func("exp", {copy(f)})
              if #remaining > 0 then
                local factor = #remaining == 1 and remaining[1] or ast.mul(table.unpack(remaining))
                result = ast.mul(factor, result)
              end
              
              add_step("∫" .. format_expr(other) .. "·e^(" .. format_expr(f) .. ") d" .. var .. 
                      " = e^(" .. format_expr(f) .. ") (exponential chain rule)")
              
              if is_definite then
                local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
                local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
                add_step("= [e^(" .. format_expr(f) .. ")]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
                add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
                return ast.number(upper_val - lower_val), steps
              end
              return result, steps
            end
          end
        end
      end
    end

    -- Power rule with chain: ∫f(x)^n·f'(x) dx = f(x)^{n+1}/(n+1)
    for i, arg in ipairs(node.args) do
      if arg.type == "pow" and is_const(arg.exp) and arg.exp.value ~= -1 then
        local base, exp = arg.base, arg.exp
        local dbase = diffAST(base, var)
        if dbase then
          for j, other in ipairs(node.args) do
            if i ~= j and simplify.expr_equal and simplify.expr_equal(other, dbase) then
              local new_exp = ast.add(copy(exp), ast.number(1))
              local result = ast.div(ast.pow(copy(base), new_exp), copy(new_exp))
              
              add_step("∫(" .. format_expr(base) .. ")^" .. format_expr(exp) .. "·" .. format_expr(other) .. " d" .. var .. 
                      " = (" .. format_expr(base) .. ")^(" .. format_expr(exp) .. "+1)/(" .. format_expr(exp) .. "+1)")
              add_step("= " .. format_expr(result))
              
              if is_definite then
                local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
                local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
                add_step("= [" .. format_expr(result) .. "]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
                add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
                return ast.number(upper_val - lower_val), steps
              end
              return result, steps
            end
          end
        end
      end
    end

    -- Extract constants
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
      
      if simplify.expr_equal(var_product, node) then
        return { type = "unimplemented_integral", original = node }, steps
      end
      
      add_step("∫" .. format_expr(const_product) .. "·(" .. format_expr(var_product) .. ") d" .. var .. 
               " = " .. format_expr(const_product) .. "·∫" .. format_expr(var_product) .. " d" .. var)
      
      local var_integral, var_steps = integrateAST(var_product, var, bounds, depth + 1)
      if var_steps then
        for _, s in ipairs(var_steps) do table.insert(steps, s) end
      end
      
      if var_integral.type ~= "unimplemented_integral" then
        if is_definite then
            local result_val = 0
            if const_product.type == "number" and var_integral.type == "number" then
                result_val = const_product.value * var_integral.value
            else
                _G.errors.throw("int(definite_bounds_undefined)", "constant_product_non_numeric")
            end
            add_step("= " .. result_val)
            return ast.number(result_val), steps
        end
        local result = ast.mul(const_product, var_integral)
        add_step("= " .. format_expr(result))
        return result, steps
      end
    end
  end

  -- Enhanced power rule: ∫x^n dx and ∫a^x dx
  if node.type == "pow" and node.base and node.exp then
    local base, exp = node.base, node.exp
    
    if is_symbol(base, var) and is_const(exp) then
      if exp.value == -1 then
        local result = ast.func("ln", { ast.func("abs", { copy(base) }) })
        add_step("∫" .. format_expr(base) .. "^(-1) d" .. var .. " = ln|" .. format_expr(base) .. "|")
        
        if is_definite then
          local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
          local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
          add_step("= [ln|" .. format_expr(base) .. "|]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
          add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
          return ast.number(upper_val - lower_val), steps
        end
        return ast.add(result, ast.variable("C")), steps
      else
        local new_exp = ast.number(exp.value + 1)
        local result = ast.div(ast.pow(copy(base), new_exp), new_exp)
        add_step("∫" .. format_expr(base) .. "^" .. format_expr(exp) .. " d" .. var .. 
                " = " .. format_expr(base) .. "^(" .. format_expr(exp) .. "+1)/(" .. format_expr(exp) .. "+1)")
        add_step("= " .. format_expr(result))
        
        if is_definite then
          local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
          local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
          add_step("= [" .. format_expr(result) .. "]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
          add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
          return ast.number(upper_val - lower_val), steps
        end
        return ast.add(result, ast.variable("C")), steps
      end
    elseif is_const(base) and is_symbol(exp, var) then
      local result = ast.div(copy(node), ast.func("ln", { copy(base) }))
      add_step("∫" .. format_expr(base) .. "^" .. format_expr(exp) .. " d" .. var .. 
              " = " .. format_expr(base) .. "^" .. format_expr(exp) .. "/ln(" .. format_expr(base) .. ")")
      
      if is_definite then
        local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
        local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
        add_step("= [" .. format_expr(result) .. "]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
        add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
        return ast.number(upper_val - lower_val), steps
      end
      return ast.add(result, ast.variable("C")), steps
    end
  end

  -- Enhanced function integration
  if node.type == "func" and node.name then
    local fname = node.name
    local arg = (node.args and node.args[1]) or node.arg

    -- Try trigonometric functions
    local trig_result = integrate_trig(fname, arg, var, steps)
    if trig_result then 
      if is_definite then
        local upper_val = ast.eval_numeric(ast.substitute(copy(trig_result), ast.variable(var), copy(bounds.upper)), {})
        local lower_val = ast.eval_numeric(ast.substitute(copy(trig_result), ast.variable(var), copy(bounds.lower)), {})
        add_step("= [" .. format_expr(trig_result) .. "]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
        add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
        return ast.number(upper_val - lower_val), steps
      end
      return ast.add(trig_result, ast.variable("C")), steps
    end

    -- Handle other common functions
    if fname == "exp" and arg then
      if is_symbol(arg, var) then
        add_step("∫e^" .. format_expr(arg) .. " d" .. var .. " = e^" .. format_expr(arg))
        if is_definite then
          local upper_val = ast.eval_numeric(ast.substitute(copy(node), ast.variable(var), copy(bounds.upper)), {})
          local lower_val = ast.eval_numeric(ast.substitute(copy(node), ast.variable(var), copy(bounds.lower)), {})
          add_step("= [e^" .. format_expr(arg) .. "]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
          add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
          return ast.number(upper_val - lower_val), steps
        end
        return ast.add(copy(node), ast.variable("C")), steps
      end
    elseif fname == "ln" and arg then
      if is_symbol(arg, var) then
        local x = ast.variable(var)
        local result = ast.sub(ast.mul(x, copy(node)), x)
        add_step("∫ln(" .. format_expr(arg) .. ") d" .. var .. " = " .. format_expr(arg) .. "·ln(" .. format_expr(arg) .. ") - " .. format_expr(arg))
        add_step("= " .. format_expr(result))
        
        if is_definite then
          local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
          local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
          add_step("= [" .. format_expr(result) .. "]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
          add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
          return ast.number(upper_val - lower_val), steps
        end
        return ast.add(result, ast.variable("C")), steps
      end
    elseif fname == "sqrt" and arg then
      if is_symbol(arg, var) then
        local result = ast.mul(ast.div(ast.number(2), ast.number(3)), ast.pow(copy(arg), ast.div(ast.number(3), ast.number(2))))
        add_step("∫√" .. format_expr(arg) .. " d" .. var .. " = (2/3)" .. format_expr(arg) .. "^(3/2)")
        add_step("= " .. format_expr(result))
        
        if is_definite then
          local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
          local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
          add_step("= [" .. format_expr(result) .. "]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
          add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
          return ast.number(upper_val - lower_val), steps
        end
        return ast.add(result, ast.variable("C")), steps
      end
    elseif known_integral_table[fname] and arg then
      local result = known_integral_table[fname](copy(arg))
      if result then 
        add_step("∫" .. fname .. "(" .. format_expr(arg) .. ") d" .. var .. " = " .. format_expr(result))
        if is_definite then
          local upper_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.upper)), {})
          local lower_val = ast.eval_numeric(ast.substitute(copy(result), ast.variable(var), copy(bounds.lower)), {})
          add_step("= [" .. format_expr(result) .. "]|" .. format_expr(bounds.lower) .. "^" .. format_expr(bounds.upper))
          add_step("= " .. upper_val .. " - " .. lower_val .. " = " .. (upper_val - lower_val))
          return ast.number(upper_val - lower_val), steps
        end
        return ast.add(result, ast.variable("C")), steps
      end
    end
  end

  -- If we get here and it's definite, try numerical integration
  if is_definite then
    add_step("Cannot integrate symbolically - using numerical methods")
    return numerical_integration_fallback(node, var, bounds.lower, bounds.upper), steps
  end

  add_step("Cannot integrate ∫" .. format_expr(node) .. " d" .. var .. " symbolically")
  return { type = "unimplemented_integral", original = copy(node) }, steps
end

-- Multi-variable integration
local function integrate_multivariable(node, vars)
  if not vars or #vars == 0 then
    _G.errors.throw("int(invalid_args)", "multi-variable integration requires at least one variable")
  end
  
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

-- Improper integral detection
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

-- Main integration interface with steps
local function integral(expr, var, bounds, options)
  local tree
  local parser = rawget(_G, "parser") or require("parser")
  
  options = options or {}
  
  if type(expr) == "string" then
    tree = parser.parse(expr)
  elseif type(expr) == "table" then
    tree = expr
  else
    _G.errors.throw("int(invalid_input_type)", type(expr))
  end

  if not tree then
    _G.errors.throw("parse(syntax)", "integral_input_parse_fail")
  end

  if tree.type == "integral" then
      var = tree.respect_to.name
      bounds = { lower = tree.lower_bound, upper = tree.upper_bound }
      expr = tree.integrand
  else
      var = var or "x"
  end

  if type(var) == "table" then
    return integrate_multivariable(tree, var)
  end

  if bounds and (bounds.lower or bounds.upper) then
    local improper = handle_improper_integral(tree, var, bounds)
    if improper then return improper end
  end

  local result, steps = integrateAST(expr, var, bounds)
  
  if not result or type(result) ~= "table" then
    _G.errors.throw("internal(invalid_state)", "integral_result_type")
  end

  if result.type ~= "unimplemented_integral" and 
     result.type ~= "numerical_approximation" and 
     result.type ~= "improper_integral" and 
     simplify.simplify then
    result = simplify.simplify(result)
  end

  return result, steps
end

-- Convenience functions
local function definite_integral(expr, var, a, b)
  return integral(expr, var, {lower = a, upper = b})
end

local function indefinite_integral(expr, var)
  return integral(expr, var, nil)
end

local function line_integral(vector_field, curve, parameter)
  return {
    type = "unimplemented_line_integral",
    vector_field = copy(vector_field),
    curve = copy(curve),
    parameter = parameter or "t"
  }
end

local function surface_integral(scalar_field, surface, parameters)
  return {
    type = "unimplemented_surface_integral",
    scalar_field = copy(scalar_field),
    surface = copy(surface),
    parameters = parameters or {"u", "v"}
  }
end

-- Global exports
_G.integrate = {
  integrateAST = integrateAST,
  eval = integral,
  definite = definite_integral,
  indefinite = indefinite_integral,
  multivariable = integrate_multivariable,
  line = line_integral,
  surface = surface_integral,
  partial_fractions = partial_fraction_decompose,
  is_polynomial = is_polynomial
}
_G.integral = _G.integrate.eval
_G.definite_integral = _G.integrate.definite
_G.indefinite_integral = _G.integrate.indefinite

-- Enhanced pretty printing for integration results
if _G.pretty_print_internal then
  local old_pretty_internal = _G.pretty_print_internal

  function pretty_print_internal(expr, parent, pos)
    if expr and expr.type == "integral" and expr.integrand and expr.respect_to then
        local integrand_str = pretty_print_internal(expr.integrand, nil, nil)
        local var_str = pretty_print_internal(expr.respect_to, nil, nil)
        local bounds_str = ""
        if expr.lower_bound and expr.upper_bound then
            local lower_str = pretty_print_internal(expr.lower_bound, nil, nil)
            local upper_str = pretty_print_internal(expr.upper_bound, nil, nil)
            bounds_str = "_" .. lower_str .. "^" .. upper_str
        end
        return "∫" .. bounds_str .. integrand_str .. " d" .. var_str
    end

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


_G.evaluateIntegral = _G.integral
_G.integrateAST = integrateAST