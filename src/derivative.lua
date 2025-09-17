-- Derivative Engine with Mathematical Solution Steps
-- Now shows actual mathematical work instead of rule explanations

local ast = rawget(_G, "ast") or require("ast")
local trig = rawget(_G, "trig")
local simplify = rawget(_G, "simplify")

--[[
  Creates a deep copy of a Lua table, including handling circular references.
  This is essential for operations that modify parts of an AST without affecting the original.
  @param obj (table): The table to copy.
  @return (table): The new, deeply-copied table.
]]
local function deep_copy(obj)
  if type(obj) ~= "table" then return obj end
  
  -- Guard against circular references
  if obj.__copy_visited then return obj end 
  obj.__copy_visited = true

  local new_table = {}
  for key, value in pairs(obj) do
      new_table[key] = deep_copy(value)
  end
  
  obj.__copy_visited = nil

  local mt = getmetatable(obj)
  if mt then
      setmetatable(new_table, mt)
  end
  return new_table
end

-- Utility functions

--[[
  Checks if an AST node is a number.
  @param ast_node (table): The node to check.
  @return (boolean): True if the node is a number, false otherwise.
]]
local function is_const(ast_node)
  return ast_node and ast_node.type == "number"
end

--[[
  Checks if an AST node is a variable.
  @param ast_node (table): The node to check.
  @return (boolean): True if the node is a variable, false otherwise.
]]
local function is_var(ast_node)
  return ast_node and ast_node.type == "variable"
end

--[[
  Checks if an AST node is a specific named variable.
  @param ast_node (table): The node to check.
  @param name (string): The name to compare against.
  @return (boolean): True if the node is a variable with the given name, false otherwise.
]]
local function is_symbol(ast_node, name)
  return ast_node and ast_node.type == "variable" and ast_node.name == name
end

--[[
  Creates a limit AST node for symbolic representation.
  @param expr (table): The expression to take the limit of.
  @param var (string): The variable approaching the limit.
  @param to (table): The value the variable is approaching.
  @return (table): The limit AST node.
]]
local function lim(expr, var, to)
  return { type = 'lim', expr = expr, var = var, to = to }
end

--[[
  Formats an AST node into a string representation for display in steps.
  @param ast_node (table): The node to format.
  @return (string): The formatted expression string.
]]
local function format_expr(ast_node)
  return (simplify and simplify.pretty_print(ast_node)) or ast.tostring(ast_node)
end

--[[
  Performs symbolic differentiation on an AST node with respect to a given variable.
  It computes the derivative and generates a list of steps showing the application of
  differentiation rules.
  @param ast_node (table): The AST node of the expression to differentiate.
  @param var (string): The variable to differentiate with respect to (defaults to "x").
  @return (table, table): The AST node of the derivative and a list of steps.
]]
local function diffAST(ast_node, var)
  local steps = {}
  local result = nil

  -- Input validation
  if not ast_node then
    error(_G.errors.get("diff(unimplemented_node)") or "Input AST node is nil.")
  end
  if type(ast_node) ~= "table" then
    error(_G.errors.get("diff(just_no)") or "Input is not an AST table.")
  end
  if not ast_node.type then
    error(_G.errors.get("diff(no_type)") or "Input AST table missing 'type' field.")
  end

  var = var or "x"
  
  -- Helper to add a mathematical step to the list
  local function add_step(description)
      table.insert(steps, { description = description })
  end

  -- Checks if an expression is trivial (constant or a variable)
  local function is_trivial(node)
    return (node.type == "number") or 
           (node.type == "variable" and node.name == var) or
           (node.type == "variable" and node.name ~= var)
  end

  -- Constant Rule: d/dx(c) = 0
  if ast_node.type == "number" then
    result = ast.number(0)
    assert(result and result.type == "number", "Constant Rule failed.")
    -- Add step for clarity
    if format_expr(ast_node) ~= "1" and format_expr(ast_node) ~= "0" then
      add_step("d/d" .. var .. "(" .. format_expr(ast_node) .. ") = 0")
    end
  
  -- Variable Rule: d/dx(x) = 1, d/dx(y) = 0
  elseif ast_node.type == "variable" then
    if ast_node.name == var then
      result = ast.number(1)
      assert(result and result.type == "number", "Variable Rule (self) failed.")
    else
      result = ast.number(0)
      assert(result and result.type == "number", "Variable Rule (other) failed.")
    end
  
  -- Negation Rule: d/dx(-f(x)) = -d/dx(f(x))
  elseif ast_node.type == "neg" then
    local inner_arg = ast_node.arg or ast_node.value
    assert(inner_arg, "Negation node has no valid argument.")
    
    add_step("d/d" .. var .. "(-" .. format_expr(inner_arg) .. ") = -d/d" .. var .. "(" .. format_expr(inner_arg) .. ")")
    
    local inner_deriv, inner_steps = diffAST(inner_arg, var)
    assert(inner_deriv and inner_deriv.type, "diffAST failed for negation argument.")
    for _, s in ipairs(inner_steps) do table.insert(steps, s) end

    result = ast.neg(inner_deriv)
    assert(result and result.type == "neg", "Negation Rule failed.")
    add_step("= -(" .. format_expr(inner_deriv) .. ")")
  
  -- Sum Rule: d/dx(f(x) + g(x)) = f'(x) + g'(x)
  elseif ast_node.type == "add" then
    local expr_str = format_expr(ast_node)
    add_step("d/d" .. var .. "(" .. expr_str .. ") = " .. 
             table.concat(
               (function()
                 local parts = {}
                 for i, term in ipairs(ast_node.args) do
                   table.insert(parts, "d/d" .. var .. "(" .. format_expr(term) .. ")")
                 end
                 return parts
               end)(), " + "))
    
    local deriv_args = {}
    for i, term in ipairs(ast_node.args) do
      local d_term, d_term_steps = diffAST(term, var)
      assert(d_term and d_term.type, "diffAST failed for addition term.")
      for _, s in ipairs(d_term_steps) do table.insert(steps, s) end
      table.insert(deriv_args, d_term)
    end
    assert(#deriv_args > 0, "Sum rule resulted in no terms.")
    result = ast.add(table.unpack(deriv_args))
    assert(result and result.type == "add", "Sum Rule failed.")
    
    add_step("= " .. format_expr(result))
  
  -- Difference Rule: d/dx(f(x) - g(x)) = f'(x) - g'(x)
  elseif ast_node.type == "sub" then
    add_step("d/d" .. var .. "(" .. format_expr(ast_node) .. ") = d/d" .. var .. "(" .. 
             format_expr(ast_node.left) .. ") - d/d" .. var .. "(" .. format_expr(ast_node.right) .. ")")
    
    local left_deriv, left_steps = diffAST(ast_node.left, var)
    assert(left_deriv and left_deriv.type, "diffAST failed for subtraction left.")
    for _, s in ipairs(left_steps) do table.insert(steps, s) end

    local right_deriv, right_steps = diffAST(ast_node.right, var)
    assert(right_deriv and right_deriv.type, "diffAST failed for subtraction right.")
    for _, s in ipairs(right_steps) do table.insert(steps, s) end

    result = ast.sub(left_deriv, right_deriv)
    assert(result and result.type == "sub", "Difference Rule failed.")
    add_step("= " .. format_expr(left_deriv) .. " - " .. format_expr(right_deriv))
    add_step("= " .. format_expr(result))
  
  -- Product Rule: d/dx(u·v) = u'v + uv'
  elseif ast_node.type == "mul" then
    local n_factors = #ast_node.args
    
    if n_factors == 2 then
        local u, v = ast_node.args[1], ast_node.args[2]
        add_step("Applying the product rule: d/d" .. var .. "(" .. format_expr(u) .. " · " .. format_expr(v) .. 
                ") = d/d" .. var .. "(" .. format_expr(u) .. ") · " .. format_expr(v) .. 
                " + " .. format_expr(u) .. " · d/d" .. var .. "(" .. format_expr(v) .. ")")
        
        local du, du_steps = diffAST(u, var)
        assert(du and du.type, "diffAST failed for product u.")
        for _, s in ipairs(du_steps) do table.insert(steps, s) end

        local dv, dv_steps = diffAST(v, var)
        assert(dv and dv.type, "diffAST failed for product v.")
        for _, s in ipairs(dv_steps) do table.insert(steps, s) end
        
        local term1 = ast.mul(du, deep_copy(v))
        assert(term1 and term1.type == "mul", "Product Rule term1 failed.")
        local term2 = ast.mul(deep_copy(u), dv)
        assert(term2 and term2.type == "mul", "Product Rule term2 failed.")
        
        add_step("= " .. format_expr(du) .. " · " .. format_expr(v) .. 
                " + " .. format_expr(u) .. " · " .. format_expr(dv))
        
        result = ast.add(term1, term2)
        assert(result and result.type == "add", "Product Rule failed.")
        add_step("= " .. format_expr(result))
    else
        -- General Product Rule for n factors
        add_step("Using the general product rule for " .. n_factors .. " factors:")
        local terms = {}
        for k = 1, n_factors do
            local prod_args = {}
            local d_arg_k, d_arg_k_steps = diffAST(ast_node.args[k], var)
            assert(d_arg_k and d_arg_k.type, "diffAST failed for general product factor.")
            for _, s in ipairs(d_arg_k_steps) do table.insert(steps, s) end

            for i = 1, n_factors do
                if i == k then
                    prod_args[i] = d_arg_k
                else
                    prod_args[i] = deep_copy(ast_node.args[i])
                end
            end
            local term_k = ast.mul(table.unpack(prod_args))
            assert(term_k and term_k.type == "mul", "General Product Rule term failed.")
            table.insert(terms, term_k)
        end
        assert(#terms > 0, "General Product Rule resulted in no terms.")
        result = ast.add(table.unpack(terms))
        assert(result and result.type == "add", "General Product Rule failed.")
        add_step("= " .. format_expr(result))
    end
  
  -- Quotient Rule: d/dx(u/v) = (vu' - uv') / v^2
  elseif ast_node.type == "div" then
    local u = ast_node.left
    local v = ast_node.right
    
    add_step("Applying the quotient rule: d/d" .. var .. "(" .. format_expr(u) .. "/" .. format_expr(v) .. 
            ") = [" .. format_expr(v) .. " · d/d" .. var .. "(" .. format_expr(u) .. 
            ") - " .. format_expr(u) .. " · d/d" .. var .. "(" .. format_expr(v) .. 
            ")] / (" .. format_expr(v) .. ")²")
    
    local du, du_steps = diffAST(u, var)
    assert(du and du.type, "diffAST failed for quotient numerator.")
    for _, s in ipairs(du_steps) do table.insert(steps, s) end

    local dv, dv_steps = diffAST(v, var)
    assert(dv and dv.type, "diffAST failed for quotient denominator.")
    for _, s in ipairs(dv_steps) do table.insert(steps, s) end

    add_step("= [" .. format_expr(v) .. " · " .. format_expr(du) .. 
            " - " .. format_expr(u) .. " · " .. format_expr(dv) .. 
            "] / (" .. format_expr(v) .. ")²")

    local numerator = ast.sub(
      ast.mul(du, deep_copy(v)),
      ast.mul(deep_copy(u), dv)
    )
    assert(numerator and numerator.type == "sub", "Quotient Rule numerator failed.")

    local denominator = ast.pow(deep_copy(v), ast.number(2))
    assert(denominator and denominator.type == "pow", "Quotient Rule denominator failed.")

    result = ast.div(numerator, denominator)
    assert(result and result.type == "div", "Quotient Rule failed.")
    add_step("= " .. format_expr(result))
  
  -- Powers
  elseif ast_node.type == "pow" then
    local u, n = ast_node.base, ast_node.exp
    
    if is_const(n) then
      -- Power Rule: d/dx(u^n) = n·u^(n-1)·u'
      local du, du_steps = diffAST(u, var)
      assert(du and du.type, "diffAST failed for power base.")
      
      local n_val = n.value
      local n_minus_1 = ast.number(n_val - 1)
      assert(n_minus_1 and n_minus_1.type == "number", "Power Rule n-1 failed.")
      
      if is_var(u) and u.name == var and is_trivial(du) then
        add_step("Applying the power rule: d/d" .. var .. "(" .. format_expr(u) .. "^" .. format_expr(n) .. 
                ") = " .. format_expr(n) .. format_expr(u) .. "^(" .. 
                format_expr(n) .. "-1) = " .. format_expr(n) .. format_expr(u) .. "^" .. 
                format_expr(n_minus_1))
      else
        -- Chain rule application
        add_step("Applying the power rule with the chain rule: d/d" .. var .. "(" .. format_expr(u) .. "^" .. format_expr(n) .. 
                ") = " .. format_expr(n) .. "(" .. format_expr(u) .. ")^(" .. 
                format_expr(n) .. "-1) · d/d" .. var .. "(" .. format_expr(u) .. ")")
        
        if not is_trivial(u) then
          for _, s in ipairs(du_steps) do table.insert(steps, s) end
        end
        
        add_step("= " .. format_expr(n) .. "(" .. format_expr(u) .. ")^" .. 
                format_expr(n_minus_1) .. " · " .. format_expr(du))
      end
      
      local term1 = ast.mul(deep_copy(n), ast.pow(deep_copy(u), n_minus_1))
      assert(term1 and term1.type == "mul", "Power Rule term1 failed.")
      result = ast.mul(term1, du)
      assert(result and result.type == "mul", "Power Rule failed.")
      
      add_step("= " .. format_expr(result))
      
    elseif is_const(u) then
      -- Exponential Rule: d/dx(a^u) = ln(a)·a^u·u'
      add_step("Applying the exponential rule with the chain rule: d/d" .. var .. "(" .. format_expr(u) .. "^" .. format_expr(n) .. 
              ") = ln(" .. format_expr(u) .. ") · " .. format_expr(u) .. "^" .. 
              format_expr(n) .. " · d/d" .. var .. "(" .. format_expr(n) .. ")")
      
      local dv, dv_steps = diffAST(n, var)
      assert(dv and dv.type, "diffAST failed for exponential exponent.")
      for _, s in ipairs(dv_steps) do table.insert(steps, s) end
      
      local ln_u = ast.func("ln", { deep_copy(u) })
      assert(ln_u and ln_u.type == "func", "Exponential Rule ln(u) failed.")
      local u_pow_n = ast.pow(deep_copy(u), deep_copy(n))
      assert(u_pow_n and u_pow_n.type == "pow", "Exponential Rule a^u failed.")

      local term1 = ast.mul(ln_u, u_pow_n)
      assert(term1 and term1.type == "mul", "Exponential Rule term1 failed.")
      result = ast.mul(term1, dv)
      assert(result and result.type == "mul", "Exponential Rule failed.")
      
      add_step("= " .. format_expr(ln_u) .. " · " .. format_expr(u_pow_n) .. " · " .. format_expr(dv))
      add_step("= " .. format_expr(result))
    else
      -- General Power Rule: d/dx(u^v) = u^v·(v'ln(u) + v(u'/u))
      add_step("Applying the general power rule with logarithmic differentiation: d/d" .. var .. "(" .. format_expr(u) .. "^" .. format_expr(n) .. 
              ") = " .. format_expr(u) .. "^" .. format_expr(n) .. 
              " · [d/d" .. var .. "(" .. format_expr(n) .. ") · ln(" .. format_expr(u) .. 
              ") + " .. format_expr(n) .. " · d/d" .. var .. "(" .. format_expr(u) .. 
              ")/" .. format_expr(u) .. "]")
      
      local du, du_steps = diffAST(u, var)
      assert(du and du.type, "diffAST failed for general power base.")
      for _, s in ipairs(du_steps) do table.insert(steps, s) end
      local dv, dv_steps = diffAST(n, var)
      assert(dv and dv.type, "diffAST failed for general power exponent.")
      for _, s in ipairs(dv_steps) do table.insert(steps, s) end
      
      local copied_u_pow_n = ast.pow(deep_copy(u), deep_copy(n))
      assert(copied_u_pow_n and copied_u_pow_n.type == "pow", "General power u^v failed.")
      
      local ln_u = ast.func("ln", { deep_copy(u) })
      assert(ln_u and ln_u.type == "func", "General power ln(u) failed.")
      
      local div_u_prime_u = ast.div(du, deep_copy(u))
      assert(div_u_prime_u and div_u_prime_u.type == "div", "General power u'/u failed.")

      local term1_add = ast.mul(dv, ln_u)
      assert(term1_add and term1_add.type == "mul", "General power term1 failed.")
      
      local term2_add = ast.mul(deep_copy(n), div_u_prime_u)
      assert(term2_add and term2_add.type == "mul", "General power term2 failed.")

      local sum_terms = ast.add(term1_add, term2_add)
      assert(sum_terms and sum_terms.type == "add", "General power sum failed.")

      result = ast.mul(copied_u_pow_n, sum_terms)
      assert(result and result.type == "mul", "General power final failed.")
      
      add_step("= " .. format_expr(copied_u_pow_n) .. " · [" .. format_expr(dv) .. 
              " · " .. format_expr(ln_u) .. " + " .. format_expr(n) .. " · " .. 
              format_expr(div_u_prime_u) .. "]")
      add_step("= " .. format_expr(result))
    end
  
  -- Function differentiation with Chain Rule: d/dx(f(u)) = f'(u)·u'
  elseif ast_node.type == "func" then
    local fname = ast_node.name
    local u = ast_node.arg or (ast_node.args and ast_node.args[1])
    assert(u, "Function argument is nil for '" .. fname .. "'.")
    
    local du, du_steps = diffAST(u, var)
    assert(du and du.type, "diffAST failed for function argument.")
    
    -- Handle specific functions
    if fname == "sin" then
        local cos_u = ast.func("cos", { deep_copy(u) })
        result = ast.mul(cos_u, du)
        
        if is_var(u) and u.name == var then
          add_step("d/d" .. var .. "(sin(" .. format_expr(u) .. ")) = cos(" .. format_expr(u) .. ")")
        else
          add_step("d/d" .. var .. "(sin(" .. format_expr(u) .. ")) = cos(" .. format_expr(u) .. ") · d/d" .. var .. "(" .. format_expr(u) .. ")")
          if not is_trivial(u) then
            for _, s in ipairs(du_steps) do table.insert(steps, s) end
          end
          add_step("= cos(" .. format_expr(u) .. ") · " .. format_expr(du))
          add_step("= " .. format_expr(result))
        end
        
    elseif fname == "cos" then
        local sin_u = ast.func("sin", { deep_copy(u) })
        local neg_sin_u = ast.neg(sin_u)
        result = ast.mul(neg_sin_u, du)
        
        if is_var(u) and u.name == var then
          add_step("d/d" .. var .. "(cos(" .. format_expr(u) .. ")) = -sin(" .. format_expr(u) .. ")")
        else
          add_step("d/d" .. var .. "(cos(" .. format_expr(u) .. ")) = -sin(" .. format_expr(u) .. ") · d/d" .. var .. "(" .. format_expr(u) .. ")")
          if not is_trivial(u) then
            for _, s in ipairs(du_steps) do table.insert(steps, s) end
          end
          add_step("= -sin(" .. format_expr(u) .. ") · " .. format_expr(du))
          add_step("= " .. format_expr(result))
        end
        
    elseif fname == "tan" then
        local sec_u_sq = ast.pow(ast.func("sec", { deep_copy(u) }), ast.number(2))
        result = ast.mul(sec_u_sq, du)
        
        if is_var(u) and u.name == var then
          add_step("d/d" .. var .. "(tan(" .. format_expr(u) .. ")) = sec²(" .. format_expr(u) .. ")")
        else
          add_step("d/d" .. var .. "(tan(" .. format_expr(u) .. ")) = sec²(" .. format_expr(u) .. ") · d/d" .. var .. "(" .. format_expr(u) .. ")")
          if not is_trivial(u) then
            for _, s in ipairs(du_steps) do table.insert(steps, s) end
          end
          add_step("= sec²(" .. format_expr(u) .. ") · " .. format_expr(du))
          add_step("= " .. format_expr(result))
        end
        
    elseif fname == "exp" then
        local exp_u = ast.func("exp", { deep_copy(u) })
        result = ast.mul(exp_u, du)
        
        if is_var(u) and u.name == var then
          add_step("d/d" .. var .. "(e^" .. format_expr(u) .. ") = e^" .. format_expr(u))
        else
          add_step("d/d" .. var .. "(e^" .. format_expr(u) .. ") = e^" .. format_expr(u) .. " · d/d" .. var .. "(" .. format_expr(u) .. ")")
          if not is_trivial(u) then
            for _, s in ipairs(du_steps) do table.insert(steps, s) end
          end
          add_step("= e^" .. format_expr(u) .. " · " .. format_expr(du))
          add_step("= " .. format_expr(result))
        end
        
    elseif fname == "ln" then
        local one_div_u = ast.div(ast.number(1), deep_copy(u))
        result = ast.mul(one_div_u, du)
        
        if is_var(u) and u.name == var then
          add_step("d/d" .. var .. "(ln(" .. format_expr(u) .. ")) = 1/" .. format_expr(u))
        else
          add_step("d/d" .. var .. "(ln(" .. format_expr(u) .. ")) = (1/" .. format_expr(u) .. ") · d/d" .. var .. "(" .. format_expr(u) .. ")")
          if not is_trivial(u) then
            for _, s in ipairs(du_steps) do table.insert(steps, s) end
          end
          add_step("= (1/" .. format_expr(u) .. ") · " .. format_expr(du))
          add_step("= " .. format_expr(result))
        end
        
    elseif fname == "sqrt" then
        local two_sqrt_u = ast.mul(ast.number(2), ast.func("sqrt", { deep_copy(u) }))
        local one_div_two_sqrt_u = ast.div(ast.number(1), two_sqrt_u)
        result = ast.mul(one_div_two_sqrt_u, du)
        
        if is_var(u) and u.name == var then
          add_step("d/d" .. var .. "(√" .. format_expr(u) .. ") = 1/(2√" .. format_expr(u) .. ")")
        else
          add_step("d/d" .. var .. "(√" .. format_expr(u) .. ") = (1/(2√" .. format_expr(u) .. ")) · d/d" .. var .. "(" .. format_expr(u) .. ")")
          if not is_trivial(u) then
            for _, s in ipairs(du_steps) do table.insert(steps, s) end
          end
          add_step("= (1/(2√" .. format_expr(u) .. ")) · " .. format_expr(du))
          add_step("= " .. format_expr(result))
        end
        
    else
        -- For unsupported functions, represent the derivative symbolically
        local generic_deriv = ast.func(fname .. "'", { deep_copy(u) })
        result = ast.mul(generic_deriv, du)
        
        if is_var(u) and u.name == var then
          add_step("d/d" .. var .. "(" .. fname .. "(" .. format_expr(u) .. ")) = " .. fname .. "'(" .. format_expr(u) .. ")")
        else
          add_step("d/d" .. var .. "(" .. fname .. "(" .. format_expr(u) .. ")) = " .. fname .. "'(" .. format_expr(u) .. ") · d/d" .. var .. "(" .. format_expr(u) .. ")")
          if not is_trivial(u) then
            for _, s in ipairs(du_steps) do table.insert(steps, s) end
          end
          add_step("= " .. fname .. "'(" .. format_expr(u) .. ") · " .. format_expr(du))
          add_step("= " .. format_expr(result))
        end
    end
    
    assert(result and result.type, "Function differentiation failed.")
  
  else
    error(_G.errors.get("diff(unimplemented_node)") or "Unhandled node type '" .. tostring(ast_node.type) .. "'.")
  end
  
  -- Simplify final result
  assert(result and result.type, "Differentiation produced invalid result.")
  local simplified_result = (simplify and simplify.simplify(deep_copy(result))) or deep_copy(result)
  
  -- Show simplification step if it actually simplified
  if simplify and not ast.equal(simplified_result, result) then
      add_step("Simplified: " .. format_expr(simplified_result))
  end
  
  return simplified_result, steps
end

-- Public interface

--[[
  Computes the symbolic derivative of a mathematical expression.
  This is the main public function. It parses the input string, computes the
  derivative using diffAST, and returns the simplified result along with the
  step-by-step solution.
  @param expr (string): The mathematical expression to differentiate.
  @param var (string): The variable to differentiate with respect to.
  @return (table, table): The simplified AST of the derivative and a table of solution steps.
]]
local function derivative(expr, var)
  local parser = rawget(_G, "parser") or require("parser")
  
  if type(expr) ~= "string" then
    error(_G.errors.get("diff(where_is_the_var)") or "Input must be a string expression.")
  end
  
  local tree = parser.parse(expr)
  if not tree then
    error(_G.errors.get("parse(syntax)") or "Failed to parse expression.")
  end
  if type(tree) ~= "table" or not tree.type then
    error(_G.errors.get("parse(invalid_ast)") or "Invalid AST from parser.")
  end
  
  local result_ast, steps_list = diffAST(tree, var)
  
  if not result_ast or type(result_ast) ~= "table" or not result_ast.type then
    error(_G.errors.get("internal(my_brain_hurts)") or "Differentiation failed.")
  end
  
  return (simplify and simplify.simplify(deep_copy(result_ast))) or deep_copy(result_ast), steps_list
end

_G.derivative = derivative
_G.diffAST = diffAST