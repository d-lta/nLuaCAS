--[[
  LuaCAS Symbolic Integration Module
  Expanded with more heuristic rules for elementary functions.
]]

-- Utility: Deep copy a table
local function copy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local t = {}
  for k,v in pairs(tbl) do t[k]=copy(v) end
  return t
end

-- AST Node Constructors
local function num(n) return {type='number', value=n} end
local function sym(s) return {type='symbol', name=s} end
-- Assuming binary operations use left/right as per existing utilities.
-- Variadic builders are for convenience; simplify might convert them.
local function mul_op(a, b) return {type='mul', left=a, right=b} end
local function add_op(a, b) return {type='add', left=a, right=b} end
-- Variadic builders (produce 'args' field)
local function mul(...)
  local args = {...}
  if type(args[1]) == "table" and #args == 1 and type(args[1][1]) ~= "nil" then args = args[1] end
  if #args == 0 then return num(1) end
  if #args == 1 then return args[1] end
  -- Build a chained binary structure for consistency with left/right expectations
  local res = args[1]
  for i = 2, #args do res = mul_op(res, args[i]) end
  return res
end
local function add(...)
  local args = {...}
  if type(args[1]) == "table" and #args == 1 and type(args[1][1]) ~= "nil" then args = args[1] end
  if #args == 0 then return num(0) end
  if #args == 1 then return args[1] end
  -- Build a chained binary structure
  local res = args[1]
  for i = 2, #args do res = add_op(res, args[i]) end
  return res
end

local function sub(a, b) return {type='sub', left=a, right=b} end
local function div(a, b) return {type='div', left=a, right=b} end
local function pow(a, b) return {type='pow', left=a, right=b} end
local function neg(u) return {type='neg', value=u} end
local function func(fname, arg) return {type='func', name=fname, arg=arg} end
local function raw(msg) return {type='raw', value=msg} end -- For unevaluated string messages
local function unevaluated_integral(expression_ast, var_symbol_ast)
    return {type = "integral", expr = expression_ast, var = var_symbol_ast}
end

-- Assume simplify and derivative modules are available as per the original context
local simplify_fn = _G.simplify or function(ast) return ast end -- Stub if not available
local derivative_module = _G.derivative or {}
local diffAST = diffAST or function(ast, var_name) return raw("d/d"..var_name.." "..tostring(ast)) end -- Stub

-- Utility: check if AST is a number
local function is_const(ast)
  return ast.type == "number"
end

-- Utility: check if AST is zero/one
local function is_zero(ast) return is_const(ast) and ast.value == 0 end
local function is_one(ast) return is_const(ast) and ast.value == 1 end

-- Utility: check if AST is a variable (symbol)
local function is_var(ast) -- Note: name "is_var" might be confusing, it means "is_symbol_type"
  return ast.type == "symbol"
end

-- Utility: check if AST is a specific symbol
local function is_symbol(ast, name_str)
  return ast.type == "symbol" and ast.name == name_str
end

-- Utility: check if AST contains variable var_name (string)
local function contains_var(node, var_name)
  if not node or type(node) ~= "table" then return false end
  if node.type == "symbol" then
    return node.name == var_name
  elseif node.type == "number" then
    return false
  elseif node.type == "neg" then
    return contains_var(node.value, var_name)
  elseif node.type == "add" or node.type == "sub" or node.type == "mul" or node.type == "div" or node.type == "pow" then
    return contains_var(node.left, var_name) or contains_var(node.right, var_name)
  elseif node.type == "func" then
    if node.arg then return contains_var(node.arg, var_name) end
  elseif node.type == "raw" or node.type == "integral" then -- Cannot look inside these easily
    return false -- Or conservatively true if they might contain it. For now, false.
  elseif node.args and type(node.args) == "table" then -- For variadic nodes
    for _, arg_node in ipairs(node.args) do
        if contains_var(arg_node, var_name) then return true end
    end
    return false
  end
  return false
end

-- Utility: check if AST is constant with respect to var_name (string)
local function is_const_wrt_var(node, var_name)
    return not contains_var(node, var_name)
end

-- Utility: check if AST is a linear in var_name (string): a*var_name + b
local function is_linear(ast, var_name)
  if is_const_wrt_var(ast, var_name) then return true end -- a constant is linear (a=0)
  if ast.type == "add" then
    return (is_linear(ast.left, var_name) and is_const_wrt_var(ast.right, var_name)) or
           (is_const_wrt_var(ast.left, var_name) and is_linear(ast.right, var_name))
  elseif ast.type == "mul" then
    return (is_const_wrt_var(ast.left, var_name) and is_symbol(ast.right, var_name)) or
           (is_const_wrt_var(ast.right, var_name) and is_symbol(ast.left, var_name))
  elseif is_symbol(ast, var_name) then
    return true
  end
  return false
end

-- Utility: extract (a, b) ASTs from a*var_name + b (if possible)
-- Returns two ASTs: coefficient 'a' and constant term 'b'
local function extract_linear_coeffs_ast(ast, var_name)
  if is_symbol(ast, var_name) then
    return num(1), num(0)
  elseif is_const_wrt_var(ast, var_name) then
    return num(0), copy(ast)
  elseif ast.type == "mul" then
    if is_const_wrt_var(ast.left, var_name) and is_symbol(ast.right, var_name) then
      return copy(ast.left), num(0)
    elseif is_const_wrt_var(ast.right, var_name) and is_symbol(ast.left, var_name) then
      return copy(ast.right), num(0)
    end
  elseif ast.type == "add" then
    if is_linear(ast.left, var_name) and is_const_wrt_var(ast.right, var_name) then
      local a, b_left = extract_linear_coeffs_ast(ast.left, var_name)
      return a, add_op(b_left, copy(ast.right))
    elseif is_const_wrt_var(ast.left, var_name) and is_linear(ast.right, var_name) then
      local a, b_right = extract_linear_coeffs_ast(ast.right, var_name)
      return a, add_op(copy(ast.left), b_right)
    end
  end
  return nil, nil -- Not in a*var+b form that we can easily extract symbolically
end

-- Utility: version of extract_linear_coeffs that returns numeric values for a, b if possible.
local function extract_linear_coeffs_numeric(ast, var_name)
    local a_ast, b_ast = extract_linear_coeffs_ast(ast, var_name)
    if a_ast and b_ast and is_const(a_ast) and is_const(b_ast) then
        return a_ast.value, b_ast.value
    end
    if a_ast and is_const(a_ast) and is_zero(b_ast) then -- for ax case
        return a_ast.value, 0
    end
    -- Add more cases if b_ast is complex but evaluatable, or handle symbolic a, b later
    return nil, nil
end


-- Utility: Substitute occurrences of a symbol (var_to_replace_name) with an expression (replacement_expr_ast)
local function substitute_var(node_in, var_to_replace_name, replacement_expr_ast)
  local node = copy(node_in)
  if node.type == "symbol" and node.name == var_to_replace_name then
    return copy(replacement_expr_ast)
  elseif node.type == "neg" then
    node.value = substitute_var(node.value, var_to_replace_name, replacement_expr_ast)
    return node
  elseif node.type == "add" or node.type == "sub" or node.type == "mul" or node.type == "div" or node.type == "pow" then
    if node.left then node.left = substitute_var(node.left, var_to_replace_name, replacement_expr_ast) end
    if node.right then node.right = substitute_var(node.right, var_to_replace_name, replacement_expr_ast) end
    return node
  elseif node.type == "func" then
    if node.arg then node.arg = substitute_var(node.arg, var_to_replace_name, replacement_expr_ast) end
    return node
  elseif type(node.args) == "table" then
    for i, arg_node in ipairs(node.args) do
      node.args[i] = substitute_var(arg_node, var_to_replace_name, replacement_expr_ast)
    end
    return node
  else
    return node
  end
end

-- Forward declaration for integrateAST
local integrateAST

-- Check if an AST node is an "unevaluated integral" or "raw" type
local function is_raw_or_integral(ast_node)
    return ast_node and (ast_node.type == "raw" or ast_node.type == "integral")
end

-- Integration by parts helper: ∫ u dv = u v - ∫ v du
local function integrate_by_parts(u_ast, dv_ast, var_name)
  local du = diffAST(u_ast, var_name)
  if is_raw_or_integral(du) then return nil end -- Derivative failed

  local v = integrateAST(dv_ast, var_name)
  if is_raw_or_integral(v) then return nil end -- Integration of dv failed or unevaluated

  local v_du_product = simplify_fn(mul_op(copy(v), copy(du)))
  if is_zero(v_du_product) then -- if v*du is 0, integral is 0
      return simplify_fn(mul_op(copy(u_ast), copy(v)))
  end
  
  local integral_v_du = integrateAST(v_du_product, var_name)
  if is_raw_or_integral(integral_v_du) then return nil end -- Integration of v*du failed

  return simplify_fn(sub(mul_op(copy(u_ast), copy(v)), integral_v_du))
end

-- Heuristic attempt for Integration by Parts
local function try_integration_by_parts(ast, var_name)
  if ast.type ~= "mul" then return nil end

  local term1, term2 = ast.left, ast.right
  if not term1 or not term2 then return nil end -- Ensure binary multiplication

  local function get_expr_type_for_ibp(expr, v_name)
    if not contains_var(expr, v_name) then return "const" end
    if expr.type == "func" and (expr.name == "log" or expr.name == "ln") then return "log" end
    -- TODO: Add inverse trig checks: "asin", "acos", "atan", "acot", "asec", "acsc"
    -- if expr.type == "func" and is_inv_trig(expr.name) then return "inv_trig" end
    
    -- Basic polynomial check (symbol, or symbol^const_power)
    if is_symbol(expr, v_name) then return "algebraic" end
    if expr.type == "pow" and is_symbol(expr.left, v_name) and is_const(expr.right) and expr.right.value >= 0 then return "algebraic" end
    -- A more robust is_polynomial check would be beneficial here.

    if expr.type == "func" and (expr.name == "sin" or expr.name == "cos" or expr.name == "tan" or expr.name == "sec" or expr.name == "csc" or expr.name == "cot") then return "trig" end
    if expr.type == "func" and expr.name == "exp" then return "exp" end
    return "unknown"
  end

  local type1 = get_expr_type_for_ibp(term1, var_name)
  local type2 = get_expr_type_for_ibp(term2, var_name)

  local u, dv
  local order = {log = 1, inv_trig = 2, algebraic = 3, trig = 4, exp = 5, unknown = 99, const = 100 }

  -- Decide u and dv based on LIATE (lower order value is preferred for u)
  if (order[type1] or 99) <= (order[type2] or 99) then
    u = term1; dv = term2
  else
    u = term2; dv = term1
  end
  
  -- Avoid trivial IBP like const * expr
  if get_expr_type_for_ibp(u, var_name) == "const" or get_expr_type_for_ibp(dv, var_name) == "const" then
      return nil
  end
  
  -- print("IBP Attempt: u="..parser.tostring(u).." ("..type1.."), dv="..parser.tostring(dv) .. " ("..type2..")")
  return integrate_by_parts(u, dv, var_name)
end


-- Heuristic attempt for U-Substitution
local function try_u_substitution(ast, var_name)
  -- Pattern 1: ∫ f(g(x)) * k * g'(x) dx = k * F(g(x))
  if ast.type == "mul" then
    local factor1, factor2 = ast.left, ast.right
    if not factor1 or not factor2 then return nil end

    local function check_pair_for_u_sub(term_f_g_candidate, term_maybe_kg_prime, v_name)
        if term_f_g_candidate.type == "func" and term_f_g_candidate.arg then
            local g_ast = term_f_g_candidate.arg
            local g_prime_ast = diffAST(copy(g_ast), v_name)

            if is_raw_or_integral(g_prime_ast) or is_zero(g_prime_ast) then return nil end

            local k_ast = simplify_fn(div(copy(term_maybe_kg_prime), copy(g_prime_ast)))

            if is_const_wrt_var(k_ast, v_name) then
                local dummy_var_sym = sym("u_sub_dummy_") -- Unique dummy var
                local integral_f_of_u = integrateAST(func(term_f_g_candidate.name, dummy_var_sym), dummy_var_sym.name)

                if not is_raw_or_integral(integral_f_of_u) then
                    local result_in_g = substitute_var(integral_f_of_u, dummy_var_sym.name, g_ast)
                    return simplify_fn(mul_op(k_ast, result_in_g))
                end
            end
        end
        return nil
    end

    local res = check_pair_for_u_sub(factor1, factor2, var_name)
    if res then return res end
    res = check_pair_for_u_sub(factor2, factor1, var_name)
    if res then return res end
  end

  -- Pattern 2: ∫ k * g'(x) * g(x)^n dx = k * g(x)^(n+1)/(n+1)  (or k*ln|g(x)| if n=-1)
  -- This can appear as g'(x) * (g(x)^n) or (g(x)^n) * g'(x)
  -- Or g'(x) / (g(x)^-n)
  local function check_g_power_g_prime(term1, term2, v_name, is_division_form)
    local g_ast, n_ast, g_prime_multiplier_ast

    -- Identify g(x)^n part and the other part (potential k*g'(x))
    -- Case A: term1 is g(x)^n or g(x)
    if term1.type == "pow" then
        g_ast = term1.left; n_ast = term1.right; g_prime_multiplier_ast = term2;
    elseif not (term2.type == "pow") then -- term1 is g(x), term2 is k*g'(x)
        g_ast = term1; n_ast = num(1); g_prime_multiplier_ast = term2;
    end
    
    if g_ast and n_ast then
        if not is_const_wrt_var(n_ast,v_name) then return nil end -- n must be constant
        local n_val = (is_const(n_ast) and n_ast.value) or nil -- Get numeric n if possible
        if is_division_form then 
            if n_val then n_val = -n_val else n_ast = neg(n_ast) end
        end

        local g_prime_ast = diffAST(copy(g_ast), v_name)
        if is_raw_or_integral(g_prime_ast) or is_zero(g_prime_ast) then return nil end

        local k_ast = simplify_fn(div(copy(g_prime_multiplier_ast), copy(g_prime_ast)))

        if is_const_wrt_var(k_ast, v_name) then
            if n_val == -1 or (type(n_val) ~= "number" and simplify_fn(add_op(copy(n_ast), num(1))).type=="number" and simplify_fn(add_op(copy(n_ast), num(1))).value == 0) then -- n = -1 case (∫ k*g'/g)
                return simplify_fn(mul_op(k_ast, func("ln", func("abs", copy(g_ast)))))
            else -- n ≠ -1 case
                local n_plus_1_ast
                if n_val then n_plus_1_ast = num(n_val + 1) else n_plus_1_ast = simplify_fn(add_op(copy(n_ast),num(1))) end
                if is_zero(n_plus_1_ast) then return nil end -- Should have been caught by n=-1

                return simplify_fn(mul_op(k_ast, div(pow(copy(g_ast), n_plus_1_ast), n_plus_1_ast)))
            end
        end
    end
    return nil
  end

  if ast.type == "mul" then
    local res = check_g_power_g_prime(ast.left, ast.right, var_name, false)
    if res then return res end
    res = check_g_power_g_prime(ast.right, ast.left, var_name, false)
    if res then return res end
  elseif ast.type == "div" then
    -- g_prime_multiplier / g^n  is effectively g_prime_multiplier * g^(-n)
    local res = check_g_power_g_prime(ast.right, ast.left, var_name, true) -- term1=g^n (denominator), term2=g_prime_mult (numerator)
    if res then return res end
  end
  
  return nil
end


-- Risch-style: Rational Integration (focused rules)
local function tryIntegrateRational(ast, var_name)
  -- Assuming ast contains var_name, is not sum/sub/neg/const (handled by integrateAST main).
  if is_symbol(ast, var_name) then
    return div(pow(sym(var_name), num(2)), num(2)) -- ∫ x dx = x^2/2
  end

  if ast.type == "mul" then
    local left, right = ast.left, ast.right
    if is_const_wrt_var(left, var_name) then
      local integral_of_right = integrateAST(right, var_name)
      if not is_raw_or_integral(integral_of_right) then return mul_op(copy(left), integral_of_right) end
    elseif is_const_wrt_var(right, var_name) then
      local integral_of_left = integrateAST(left, var_name)
      if not is_raw_or_integral(integral_of_left) then return mul_op(copy(right), integral_of_left) end
    end
  end

  if ast.type == "div" then
    local numerator, denominator = ast.left, ast.right
    if is_const_wrt_var(denominator, var_name) and not is_zero(denominator) then
      local integral_of_numerator = integrateAST(numerator, var_name)
      if not is_raw_or_integral(integral_of_numerator) then return div(integral_of_numerator, copy(denominator)) end
    end

    -- ∫ c / var^n dx (c can be const expr wrt var_name)
    if is_const_wrt_var(numerator, var_name) and denominator.type == "pow" and
       is_symbol(denominator.left, var_name) and is_const(denominator.right) then
      local c_ast = numerator
      local n_val = denominator.right.value
      if n_val == 1 then
        return mul_op(copy(c_ast), func("ln", func("abs", sym(var_name))))
      else
        return div(mul_op(copy(c_ast), pow(sym(var_name), num(1-n_val))), num(1-n_val))
      end
    end
     -- ∫ c / var dx (denominator is just var, not var^1)
    if is_const_wrt_var(numerator, var_name) and is_symbol(denominator, var_name) then
        return mul_op(copy(numerator), func("ln", func("abs", sym(var_name))))
    end

    -- Rule: ∫ k*f'(x) / f(x) dx = k*ln|f(x)| (f'(x)/f(x) is covered by u-sub g'/g)
    -- This can be seen as a specific u-substitution case but often useful to have directly.
    local deriv_denominator = diffAST(copy(denominator), var_name)
    if not is_raw_or_integral(deriv_denominator) and not is_zero(deriv_denominator) then
        local k_ast = simplify_fn(div(copy(numerator), deriv_denominator))
        if is_const_wrt_var(k_ast, var_name) then
            return mul_op(k_ast, func("ln", func("abs",copy(denominator))))
        end
    end
  end

  if ast.type == "pow" then
    local base, exponent_ast = ast.left, ast.right
    -- ∫ var^n dx, n is const_wrt_var
    if is_symbol(base, var_name) and is_const_wrt_var(exponent_ast, var_name) then
      if is_const(exponent_ast) then -- Numeric exponent
          local n_val = exponent_ast.value
          if n_val == -1 then
            return func("ln", func("abs", sym(var_name)))
          else
            return div(pow(sym(var_name), num(n_val+1)), num(n_val+1))
          end
      else -- Symbolic exponent 'a' constant wrt var_name: ∫ var^a d(var)
          local exp_plus_one = simplify_fn(add_op(copy(exponent_ast), num(1)))
          -- We need a way to check if exp_plus_one is symbolically zero.
          -- Crude check: if simplify makes it num(0).
          if is_const(exp_plus_one) and exp_plus_one.value == 0 then -- exponent_ast was symbolically -1
              return func("ln", func("abs", sym(var_name)))
          else
              return div(pow(sym(var_name), exp_plus_one), exp_plus_one)
          end
      end
    end

    -- ∫ c^var d(var), c is const_wrt_var
    if is_const_wrt_var(base, var_name) and is_symbol(exponent_ast, var_name) then
      if is_const(base) and base.value <= 0 then return nil end -- Avoid issues with log of non-positive
      if is_const(base) and base.value == 1 then return sym(var_name) end -- ∫ 1^var d(var) = ∫ 1 d(var) = var

      local ln_base = func("ln", copy(base))
      -- if simplify(ln_base) is zero, base was 1 (handled above)
      return div(pow(copy(base), sym(var_name)), ln_base)
    end
  end
  return nil
end

-- Risch-style: Trigonometric Integration
local function tryIntegrateTrig(ast, var_name)
  if ast.type == "func" then
    local fname = ast.name
    local u_ast = ast.arg
    
    -- Linear change of variable: f(ax+b)
    if is_linear(u_ast, var_name) then
      local a_num, b_num = extract_linear_coeffs_numeric(u_ast, var_name)
      if a_num ~= nil and a_num ~= 0 then
        local reciprocal_a = num(1 / a_num)
        if fname == "sin" then return mul_op(neg(reciprocal_a), func("cos", copy(u_ast))) end
        if fname == "cos" then return mul_op(reciprocal_a, func("sin", copy(u_ast))) end
        if fname == "tan" then return mul_op(neg(reciprocal_a), func("ln", func("abs", func("cos", copy(u_ast))))) end
        if fname == "cot" then return mul_op(reciprocal_a, func("ln", func("abs", func("sin", copy(u_ast))))) end
        if fname == "sec" then return mul_op(reciprocal_a, func("ln", func("abs", add_op(func("sec", copy(u_ast)), func("tan", copy(u_ast)))))) end
        if fname == "csc" then return mul_op(neg(reciprocal_a), func("ln", func("abs", add_op(func("csc", copy(u_ast)), func("cot", copy(u_ast)))))) end
      elseif a_num ~= nil and a_num == 0 then -- Argument is constant, e.g. sin(5)
        return mul_op(copy(ast), sym(var_name)) -- This is handled by integrateAST's const rule
      end
    end
    
    -- General chain rule f(u(x)) where u'(x) is a non-zero constant (e.g. sin(2x^2+1) integrated wrt x^2)
    -- This is largely covered by u-substitution now.
    -- However, if u' is a simple number, it's a quick win.
    local du_ast = diffAST(copy(u_ast), var_name)
    if is_const(du_ast) and not is_zero(du_ast) then
      local inv_du_val = num(1 / du_ast.value)
      if fname == "sin" then return mul_op(neg(inv_du_val), func("cos", copy(u_ast))) end
      if fname == "cos" then return mul_op(inv_du_val, func("sin", copy(u_ast))) end
      -- tan, cot, sec, csc with const u' follow similarly.
    end
  end

  -- Powers of trig functions like sin^2(u), cos^2(u), tan^2(u), sec^2(u) for linear u = ax+b
  if ast.type == "pow" and is_const(ast.right) then
    local power_val = ast.right.value
    local base_func_ast = ast.left
    if base_func_ast.type == "func" and base_func_ast.arg and is_linear(base_func_ast.arg, var_name) then
        local u_inner_ast = base_func_ast.arg
        local a_num, _ = extract_linear_coeffs_numeric(u_inner_ast, var_name)

        if a_num ~= nil and a_num ~= 0 then
            local inv_a_ast = num(1/a_num)
            local func_name = base_func_ast.name
            
            if power_val == 2 then -- Squares
                if func_name == "sin" then -- ∫sin^2(u)du = (1/a)[u/2 - sin(2u)/4]
                    local term_u_half = div(copy(u_inner_ast), num(2))
                    local term_sin_2u_quarter = div(func("sin", mul_op(num(2), copy(u_inner_ast))), num(4))
                    return mul_op(inv_a_ast, sub(term_u_half, term_sin_2u_quarter))
                elseif func_name == "cos" then -- ∫cos^2(u)du = (1/a)[u/2 + sin(2u)/4]
                    local term_u_half = div(copy(u_inner_ast), num(2))
                    local term_sin_2u_quarter = div(func("sin", mul_op(num(2), copy(u_inner_ast))), num(4))
                    return mul_op(inv_a_ast, add_op(term_u_half, term_sin_2u_quarter))
                elseif func_name == "tan" then -- ∫tan^2(u)du = (1/a)[tan(u) - u]
                    return mul_op(inv_a_ast, sub(func("tan", copy(u_inner_ast)), copy(u_inner_ast)))
                elseif func_name == "cot" then -- ∫cot^2(u)du = (1/a)[-cot(u) - u]
                    return mul_op(inv_a_ast, sub(neg(func("cot", copy(u_inner_ast))), copy(u_inner_ast)))
                elseif func_name == "sec" then -- ∫sec^2(u)du = (1/a)tan(u)
                    return mul_op(inv_a_ast, func("tan", copy(u_inner_ast)))
                elseif func_name == "csc" then -- ∫csc^2(u)du = (1/a)(-cot(u))
                    return mul_op(neg(inv_a_ast), func("cot", copy(u_inner_ast)))
                end
            end
        end
    end
  end

  return nil
end

-- Risch-style: Exponential Integration
local function tryIntegrateExp(ast, var_name)
    if ast.type == "func" and ast.name == "exp" then
        local u_ast = ast.arg
        -- Case: ∫ e^(ax+b) dx = (1/a)e^(ax+b)
        if is_linear(u_ast, var_name) then
            local a_num, b_num = extract_linear_coeffs_numeric(u_ast, var_name)
            if a_num ~= nil and a_num ~= 0 then
                return mul_op(num(1/a_num), func("exp", copy(u_ast)))
            end
        end
        -- Case: ∫ e^(u(x)) u'(x) dx (u-sub) -- already handled by try_u_substitution for f(g(x)) * g'(x)
    end
    -- Case: ∫ a^(bx+c) dx
    if ast.type == "pow" and is_const_wrt_var(ast.left, var_name) and is_linear(ast.right, var_name) then
        local base_ast = ast.left
        local exponent_ast = ast.right
        local a_num, b_num = extract_linear_coeffs_numeric(exponent_ast, var_name)
        if a_num ~= nil and a_num ~= 0 then
            -- ∫ c^(kx+m) dx = c^(kx+m) / (k * ln(c))
            local k_ln_c_ast = mul_op(num(a_num), func("ln", copy(base_ast)))
            if is_zero(k_ln_c_ast) then return nil end -- Avoid division by zero if base is 1

            return div(copy(ast), k_ln_c_ast)
        end
    end
    return nil
end

-- Risch-style: Logarithmic Integration (e.g. ∫ ln(ax+b) dx)
local function tryIntegrateLog(ast, var_name)
    if ast.type == "func" and (ast.name == "ln" or ast.name == "log") then
        local u_ast = ast.arg
        -- Using integration by parts: ∫ ln(u) du = u ln(u) - u
        -- If we have ∫ ln(ax+b) dx, let u = ax+b, dv = dx. Then du = a dx, v = x.
        -- This is better handled via the general IBP and u-substitution rules together.
        -- Example: ∫ ln(x) dx.  Let u = ln(x), dv = dx. Then du = 1/x dx, v = x.
        -- ∫ ln(x) dx = x ln(x) - ∫ x * (1/x) dx = x ln(x) - ∫ 1 dx = x ln(x) - x.
        -- We try IBP if it's just a log function.
        if is_linear(u_ast, var_name) and is_symbol(u_ast, var_name) then -- handles simple ln(x)
            local u = copy(ast) -- ln(x)
            local dv = sym(var_name) -- dx implicitly
            -- Integrate by parts for ln(x) and log(x)
            local integral_result = integrate_by_parts(u, num(1), var_name) -- ∫ 1 * ln(x) dx, treating 1 as dv'
            if not is_raw_or_integral(integral_result) then
                return integral_result
            end
        end
    end
    return nil
end


-- Main integration function
integrateAST = function(ast_node, var)
  if not ast_node then
    error("integrateAST: invalid AST node passed in")
  end
  if type(ast_node) ~= "table" then
    error("integrateAST: encountered non-AST node of type " .. type(ast_node))
  end
  var = var or "x" -- Default variable of integration

  -- Rule 1: Constant: ∫ c dx = c*x
  if is_const_wrt_var(ast_node, var) then
    return simplify_fn(mul_op(copy(ast_node), sym(var)))
  end

  -- Rule 2: Sum/Difference: ∫ (u ± v) dx = ∫ u dx ± ∫ v dx (n-ary add)
  if ast_node.type == "add" then
    local integrated_args = {}
    for i, term in ipairs(ast_node.args) do
      integrated_args[i] = integrateAST(term, var)
      if is_raw_or_integral(integrated_args[i]) then
        return unevaluated_integral(copy(ast_node), sym(var)) -- If any term fails, return unevaluated
      end
    end
    return simplify_fn(add(table.unpack(integrated_args)))
  end
  if ast_node.type == "sub" then
    local left_int = integrateAST(ast_node.left, var)
    local right_int = integrateAST(ast_node.right, var)
    if is_raw_or_integral(left_int) or is_raw_or_integral(right_int) then
      return unevaluated_integral(copy(ast_node), sym(var))
    end
    return simplify_fn(sub(left_int, right_int))
  end

  -- Rule 3: Negation: ∫ -u dx = -∫ u dx
  if ast_node.type == "neg" then
    local integrated_value = integrateAST(ast_node.value, var)
    if is_raw_or_integral(integrated_value) then
      return unevaluated_integral(copy(ast_node), sym(var))
    end
    return simplify_fn(neg(integrated_value))
  end

  -- Heuristics Order:
  -- 1. U-Substitution (often simplifies complex expressions into basic forms)
  -- 2. Rational Function Rules (Power Rule, 1/x rule, etc.)
  -- 3. Trigonometric Rules
  -- 4. Exponential Rules
  -- 5. Logarithmic Rules
  -- 6. Integration by Parts (can transform products)
  -- 7. Fallback to unevaluated.

  local result

  -- Try U-Substitution first
  result = try_u_substitution(ast_node, var)
  if result then return simplify_fn(result) end

  -- Try Rational Integration (handles x^n, 1/x, c/f(x) etc.)
  result = tryIntegrateRational(ast_node, var)
  if result then return simplify_fn(result) end

  -- Try Trigonometric Integration
  result = tryIntegrateTrig(ast_node, var)
  if result then return simplify_fn(result) end

  -- Try Exponential Integration
  result = tryIntegrateExp(ast_node, var)
  if result then return simplify_fn(result) end

  -- Try Logarithmic Integration (especially for simple ln(x))
  result = tryIntegrateLog(ast_node, var)
  if result then return simplify_fn(result) end

  -- Try Integration by Parts (should be after simpler forms, as it's often more complex)
  result = try_integration_by_parts(ast_node, var)
  if result then return simplify_fn(result) end


  -- Fallback: If no rule applies, return an unevaluated integral node
  return unevaluated_integral(copy(ast_node), sym(var))
end

-- Wrapper function for external calls
local function integrate(expr_str, var_str)
  local parser = rawget(_G, "parser") or require("parser")
  if type(expr_str) ~= "string" then
    error("Invalid input to integrate(): expected string, got " .. type(expr_str))
  end
  local parsed_ast = parser.parse(expr_str)
  if not parsed_ast then
    error("Parsing failed for expression: " .. expr_str)
  end
  local result_ast = integrateAST(parsed_ast, var_str or "x")
  return simplify_fn(result_ast) -- Always try to simplify the final result
end

_G.integrate = integrate
_G.integrateAST = integrateAST