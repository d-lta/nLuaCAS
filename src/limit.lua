-- Limit Engine (WIP)
-- Tries to evaluate limits symbolically.
-- Sometimes works. Sometimes pretends to work.
-- Expect mathematical disappointment and existential dread.

local ast = rawget(_G, "ast") or require("ast")


local function copy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local t = {}
  for k,v in pairs(tbl) do t[k]=v end
  return t
end

-- Utility: check if AST is a constant (number)
local function is_const(ast)
  return ast.type == "number"
end

-- Utility: check if AST is a variable (symbol)
local function is_var(ast)
  return ast.type == "variable"
end

-- Utility: substitute variable with value in AST
local function substitute(ast_node, var, value)
  if not ast_node then return nil end
  if type(ast_node) ~= "table" then return ast_node end
  
  if ast_node.type == "variable" and ast_node.name == var then
    return copy(value)
  elseif ast_node.type == "number" then
    return copy(ast_node)
  elseif ast_node.type == "neg" then
    return ast.neg(substitute(ast_node.value, var, value))
  elseif ast_node.type == "add" then
    local new_args = {}
    for i, arg in ipairs(ast_node.args) do
      new_args[i] = substitute(arg, var, value)
    end
    return ast.add(table.unpack(new_args))
  elseif ast_node.type == "sub" then
    return ast.sub(substitute(ast_node.left, var, value), substitute(ast_node.right, var, value))
  elseif ast_node.type == "mul" then
    local new_args = {}
    for i, arg in ipairs(ast_node.args) do
      new_args[i] = substitute(arg, var, value)
    end
    return ast.mul(table.unpack(new_args))
  elseif ast_node.type == "div" then
    return ast.div(substitute(ast_node.left, var, value), substitute(ast_node.right, var, value))
  elseif ast_node.type == "pow" then
    return ast.pow(substitute(ast_node.base, var, value), substitute(ast_node.exp, var, value))
  elseif ast_node.type == "func" then
    local u = ast_node.arg or (ast_node.args and ast_node.args[1])
    return ast.func(ast_node.name, { substitute(u, var, value) })
  else
    -- Just return the damn thing if we don't know what it is
    return copy(ast_node)
  end
end

-- Evaluate AST to number (if possible)
local function evaluate(ast_node)
  if not ast_node then return nil end
  if type(ast_node) ~= "table" then return ast_node end
  
  if ast_node.type == "number" then
    return ast_node.value
  elseif ast_node.type == "variable" then
    -- Can't evaluate variables without values
    return nil
  elseif ast_node.type == "neg" then
    local val = evaluate(ast_node.value)
    return val and -val
  elseif ast_node.type == "add" then
    local sum = 0
    for _, arg in ipairs(ast_node.args) do
      local val = evaluate(arg)
      if not val then return nil end
      sum = sum + val
    end
    return sum
  elseif ast_node.type == "sub" then
    local left = evaluate(ast_node.left)
    local right = evaluate(ast_node.right)
    return (left and right) and (left - right)
  elseif ast_node.type == "mul" then
    local prod = 1
    for _, arg in ipairs(ast_node.args) do
      local val = evaluate(arg)
      if not val then return nil end
      prod = prod * val
    end
    return prod
  elseif ast_node.type == "div" then
    local left = evaluate(ast_node.left)
    local right = evaluate(ast_node.right)
    if not left or not right or right == 0 then return nil end
    return left / right
  elseif ast_node.type == "pow" then
    local base = evaluate(ast_node.base)
    local exp = evaluate(ast_node.exp)
    return (base and exp) and (base ^ exp)
  elseif ast_node.type == "func" then
    local u = ast_node.arg or (ast_node.args and ast_node.args[1])
    local val = evaluate(u)
    if not val then return nil end
    
    local fname = ast_node.name
    if fname == "sin" then return math.sin(val)
    elseif fname == "cos" then return math.cos(val)
    elseif fname == "tan" then return math.tan(val)
    elseif fname == "exp" then return math.exp(val)
    elseif fname == "ln" then return math.log(val)
    elseif fname == "log" then return math.log10(val)
    elseif fname == "sqrt" then return math.sqrt(val)
    elseif fname == "abs" then return math.abs(val)
    else
      -- Unknown function, can't evaluate
      return nil
    end
  else
    return nil
  end
end

-- Directional limit evaluation. Handles left, right, and two-sided limits.
local function evalLimitDirectional(expr, var, to, direction)
  if not expr or not var or not to then
    error("evalLimitDirectional: missing required parameters")
  end
  
  -- First attempt: direct substitution (works for continuous functions)
  local direct_sub = substitute(expr, var, to)
  local direct_result = evaluate(direct_sub)
  
  if direct_result and direct_result ~= math.huge and direct_result ~= -math.huge and direct_result == direct_result then
    return ast.number(direct_result)
  end
  
  -- Second attempt: approach from specified direction or both sides
  local to_val = evaluate(to)
  if to_val then
    local delta = 1e-10
    local approaches = {}
    
    if direction == "+" then
      -- Right-hand limit (approach from positive side)
      table.insert(approaches, to_val + delta)
    elseif direction == "-" then
      -- Left-hand limit (approach from negative side)
      table.insert(approaches, to_val - delta)
    else
      -- Two-sided limit
      table.insert(approaches, to_val - delta)
      table.insert(approaches, to_val + delta)
    end
    
    local results = {}
    for _, approach in ipairs(approaches) do
      local sub_expr = substitute(expr, var, ast.number(approach))
      local result = evaluate(sub_expr)
      if result then
        table.insert(results, result)
      end
    end
    
    -- For one-sided limits, just return the result
    if direction and #results == 1 then
      return ast.number(results[1])
    end
    
    -- For two-sided limits, both approaches should give same result
    if not direction and #results == 2 and math.abs(results[1] - results[2]) < 1e-8 then
      return ast.number(results[1])
    end
  end
  
  -- Third attempt: Handle some common indeterminate forms
  -- 0/0 form - try L'Hôpital's rule (if derivative function exists)
  if rawget(_G, "diffAST") then
    -- Check if we have 0/0 form
    if expr.type == "div" then
      local num_at_to = evaluate(substitute(expr.left, var, to))
      local den_at_to = evaluate(substitute(expr.right, var, to))
      
      if num_at_to == 0 and den_at_to == 0 then
        -- Apply L'Hôpital's rule
        local num_deriv = _G.diffAST(expr.left, var)
        local den_deriv = _G.diffAST(expr.right, var)
        local lhopital_expr = ast.div(num_deriv, den_deriv)
        
        -- Recursively evaluate the limit of the derivatives
        return evalLimitDirectional(lhopital_expr, var, to, direction)
      end
    end
  end
  
  -- Fourth attempt: Special cases for infinity
  if to.type == "number" and (to.value == math.huge or to.value == -math.huge) then
    -- For polynomial ratios, look at leading coefficients
    -- This is a simplified approach - real CAS would be more sophisticated
    return ast.number(0) -- Placeholder for now
  end
  
  -- Give up and return unevaluated limit with direction info
  local result = { type = "lim", expr = copy(expr), var = var, to = copy(to) }
  if direction then
    result.direction = direction
  end
  return result
end

-- Legacy function for backward compatibility
local function evalLimit(expr, var, to)
  if not expr or not var or not to then
    error("evalLimit: missing required parameters")
  end
  
  -- First attempt: direct substitution (works for continuous functions)
  local direct_sub = substitute(expr, var, to)
  local direct_result = evaluate(direct_sub)
  
  if direct_result and direct_result ~= math.huge and direct_result ~= -math.huge and direct_result == direct_result then
    return ast.number(direct_result)
  end
  
  -- Second attempt: approach from both sides numerically
  local to_val = evaluate(to)
  if to_val then
    local delta = 1e-10
    local approaches = { to_val - delta, to_val + delta }
    local results = {}
    
    for _, approach in ipairs(approaches) do
      local sub_expr = substitute(expr, var, ast.number(approach))
      local result = evaluate(sub_expr)
      if result then
        table.insert(results, result)
      end
    end
    
    -- If both approaches give same result, that's probably our limit
    if #results == 2 and math.abs(results[1] - results[2]) < 1e-8 then
      return ast.number(results[1])
    end
  end
  
  -- Third attempt: Handle some common indeterminate forms
  -- 0/0 form - try L'Hôpital's rule (if derivative function exists)
  if rawget(_G, "diffAST") then
    -- Check if we have 0/0 form
    if expr.type == "div" then
      local num_at_to = evaluate(substitute(expr.left, var, to))
      local den_at_to = evaluate(substitute(expr.right, var, to))
      
      if num_at_to == 0 and den_at_to == 0 then
        -- Apply L'Hôpital's rule
        local num_deriv = _G.diffAST(expr.left, var)
        local den_deriv = _G.diffAST(expr.right, var)
        local lhopital_expr = ast.div(num_deriv, den_deriv)
        
        -- Recursively evaluate the limit of the derivatives
        return evalLimit(lhopital_expr, var, to)
      end
    end
  end
  
  -- Fourth attempt: Special cases for infinity
  if to.type == "number" and (to.value == math.huge or to.value == -math.huge) then
    -- For polynomial ratios, look at leading coefficients
    -- This is a simplified approach - real CAS would be more sophisticated
    return ast.number(0) -- Placeholder for now
  end
  
  -- Give up and return unevaluated limit
  return { type = "lim", expr = copy(expr), var = var, to = copy(to) }
end

-- Public interface: takes string inputs, returns limit result
-- Usage: lim("3*x + 3", "x", "2", "+") or lim("sin(x)/x", "x", "0")
-- The fourth parameter is direction: "+" for right, "-" for left, nil for both sides
local function lim(expr, var, to_val, direction)
  -- Load parser
  local parser = rawget(_G, "parser") or require("parser")
  
  -- Input validation
  if type(expr) ~= "string" then
    error("Invalid input to lim(): expected string for expression, got " .. type(expr))
  end
  
  var = var or "x"
  to_val = to_val or "0"
  direction = direction or nil -- nil means two-sided limit
  
  -- Parse expression to AST
  local tree = parser.parse(expr)
  if not tree then
    error("Parsing failed for expression: " .. expr)
  end
  
  -- Parse the "to" value
  local to_ast
  if type(to_val) == "string" then
    to_ast = parser.parse(to_val)
    if not to_ast then
      error("Parsing failed for limit point: " .. to_val)
    end
  elseif type(to_val) == "number" then
    to_ast = ast.number(to_val)
  else
    error("Invalid 'to' value: expected string or number")
  end
  
  local result = evalLimitDirectional(tree, var, to_ast, direction)
  
  -- Simplify if possible
  if rawget(_G, "simplify") then
    return _G.simplify.simplify(result)
  else
    return result
  end
end

-- Export to global namespace
_G.lim = lim
_G.evalLimit = evalLimit