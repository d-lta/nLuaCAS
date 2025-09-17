local parser = {}
local init = rawget(_G, "init")
local errors = rawget(_G, "errors") or {
  invalid = function(fn, hint)
    return "parse(" .. (fn or "?") .. "): " .. (hint or "unknown error. also: _G.errors was nil.")
  end
}

--[[
  A utility function to print the Abstract Syntax Tree (AST) in a human-readable,
  indented format for debugging purposes.
  @param ast (table): The AST node to print.
  @param indent (string): The current indentation string.
]]
local function print_ast(ast, indent)
  indent = indent or ""
  if type(ast) ~= "table" then
    print(indent .. tostring(ast))
    return
  end
  if ast.type then
    local desc = ast.type
    if ast.name then desc = desc .. " (" .. tostring(ast.name) .. ")" end
    print(indent .. desc)
    if ast.value ~= nil then print(indent .. "  value: " .. tostring(ast.value)) end
    if ast.name ~= nil and ast.type ~= "variable" then print(indent .. "  name: " .. tostring(ast.name)) end
    if ast.args then
      print(indent .. "  args:")
      for i, arg in ipairs(ast.args) do
        print_ast(arg, indent .. "    ")
      end
    end
    if ast.rows then
      print(indent .. "  rows:")
      for i, row in ipairs(ast.rows) do
        print(indent .. "    row " .. i .. ":")
        for j, elem in ipairs(row) do
          print_ast(elem, indent .. "      ")
        end
      end
    end
    if ast.base then
      print(indent .. "  base:")
      print_ast(ast.base, indent .. "    ")
    end
    if ast.type == "lim" then
      print(indent .. "limit:")
      print(indent .. "  expr:")
      print_ast(ast.expr, indent .. "    ")
      print(indent .. "  var: " .. ast.var)
      print(indent .. "  to:")
      print_ast(ast.to, indent .. "    ")
      if ast.direction then
        print(indent .. "  direction: " .. ast.direction)
      end
      return
    end
    if ast.exp then
      print(indent .. "  exp:")
      print_ast(ast.exp, indent .. "    ")
    end
    if ast.left then
      print(indent .. "  left:")
      print_ast(ast.left, indent .. "    ")
    end
    if ast.right then
      print(indent .. "  right:")
      print_ast(ast.right, indent .. "    ")
    end
    -- NEW: Add print for integral-specific fields
    if ast.integrand then
        print(indent .. "  integrand:")
        print_ast(ast.integrand, indent .. "    ")
    end
    if ast.respect_to then
        print(indent .. "  respect_to:")
        print_ast(ast.respect_to, indent .. "    ")
    end
    if ast.lower_bound then
        print(indent .. "  lower_bound:")
        print_ast(ast.lower_bound, indent .. "    ")
    end
    if ast.upper_bound then
        print(indent .. "  upper_bound:")
        print_ast(ast.upper_bound, indent .. "    ")
    end
    -- END NEW
  else
    for k, v in pairs(ast) do
      print(indent .. tostring(k) .. ":")
      print_ast(v, indent .. "  ")
    end
  end
end
parser.print_ast = print_ast
_G.print_ast = print_ast

--[[
  A helper function for UTF-8 character handling.
  @param str (string): The input string.
  @param i (number): The starting byte index.
  @return (string, number): The character and its byte length, or nil.
]]
local function utf8char(str, i)
  local b1 = str:byte(i)
  if not b1 then return nil, 0 end
  if b1 < 0x80 then
    return str:sub(i, i), 1
  elseif b1 < 0xE0 and #str >= i + 1 then
    return str:sub(i, i + 1), 2
  elseif b1 < 0xF0 and #str >= i + 2 then
    return str:sub(i, i + 2), 3
  elseif b1 < 0xF8 and #str >= i + 3 then
    return str:sub(i, i + 3), 4
  else
    -- Invalid start byte or incomplete sequence, treat as one byte to avoid infinite loop
    return str:sub(i, i), 1
  end
end

--[[
  Checks if a character is a letter. Supports ASCII and common UTF-8 letters.
  @param c (string): The character to check.
  @return (boolean): True if the character is a letter, false otherwise.
]]
local function is_alpha(c)
  -- ASCII letters
  if c:match("^[%a_]$") then return true end
  -- Common Greek letters and others can be added here
  -- For demo, accept anything with byte length > 1 (non-ASCII)
  if #c > 1 then return true end
  return false
end

--[[
  Tokenizes a mathematical expression string.
  This function scans the input string and converts it into a sequence of tokens,
  handling numbers, identifiers, operators, and special syntax like matrices and derivatives.
  It also inserts implicit multiplication tokens where needed.
  @param expr (string): The mathematical expression string.
  @return (table): A list of token tables.
]]
function parser.tokenize(expr)
  local tokens = {}
  local i = 1
  local len = #expr
  while i <= len do
    local c, clen = utf8char(expr, i)
    if not c or clen == 0 then break end

    if c:match('%s') then
      -- whitespace
      i = i + clen
    -- Improved special handling for (d/dx) derivative pattern
    elseif expr:sub(i, i+4) == "(d/dx" and expr:sub(i+5, i+5) == ")" then
      table.insert(tokens, {type="derivative"})
      i = i + 6 -- skip full "(d/dx)"
    elseif c:match('%d') or (c == '.' and (i+clen <= len) and expr:sub(i+clen,i+clen):match('%d')) then
      -- number, read full numeric token
      local num = c
      i = i + clen
      while i <= len do
        local nc, nclen = utf8char(expr, i)
        if not nc or not (nc:match('%d') or nc == '.') then break end
        num = num .. nc
        i = i + nclen
      end
      table.insert(tokens, {type="number", value=tonumber(num)})
      print(string.format("Token: [number] %s", num))
    elseif c == '∫' then
      table.insert(tokens, {type="integral_symbol", value=c}) -- Changed type name to avoid conflict
      print(string.format("Token: [integral_symbol] %s", c))
      i = i + clen
    elseif is_alpha(c) then
      -- identifier/function
      local ident = c
      i = i + clen
      while i <= len do
        local nc, nclen = utf8char(expr, i)
        if not nc then break end
        if is_alpha(nc) or nc:match('%d') then
          ident = ident .. nc
          i = i + nclen
        else
          break
        end
      end
      table.insert(tokens, {type="ident", value=ident})
      print(string.format("Token: [ident] %s", ident))
    elseif c == '"' or c == "'" then
      -- string literal
      local quote = c
      local j = i + clen
      local str = ''
      while j <= len do
        local cc, cclen = utf8char(expr, j)
        if not cc then break end
        if cc == quote then break end
        str = str .. cc
        j = j + cclen
      end
      if j > len then
        error(_G.errors.get("parse(unmatched_paren)") or errors.invalid('tokenize', 'unterminated string literal'))
      end
      table.insert(tokens, {type='string', value=str})
      print(string.format("Token: [string] %s", str))
      i = j + clen -- skip closing quote
    elseif c == ')' then
      -- Special handling for closing parenthesis after (d/dx
      if #tokens > 0 and tokens[#tokens].type == "derivative_start" then
        tokens[#tokens].type = "derivative"
      else
        table.insert(tokens, {type=c, value=c})
      end
      i = i + clen
    elseif c == ',' or c == '(' or c == '[' or c == ']' or
           c == '+' or c == '-' or c == '*' or c == '/' or c == '^' or
           c == '!' or c == '=' or c == '∫' then
      local ttype
      if c == ',' then ttype = ','
      elseif c == '(' then ttype = c
      elseif c == '[' or c == ']' then ttype = c
      elseif c == '=' then ttype = "equals"
      elseif c == '∫' then ttype = "integral_symbol" -- Consistent type name
      elseif c == '+' or c == '-' or c == '*' or c == '/' or c == '^' or c == '!' then ttype = "op"
      else ttype = "unknown" end
      table.insert(tokens, {type=ttype, value=c})
      print(string.format("Token: [%s] %s", ttype, c))
      i = i + clen
    else
      error(_G.errors.get("parse(invalid_character)") or errors.invalid("tokenize", "unknown character: " .. c))
    end
  end

  -- Insert commas between adjacent tensor brackets like '][' to fix TI calculator formatting
  local j = 2
  while j <= #tokens do
    local t1, t2 = tokens[j-1], tokens[j]
    if t1.type == ']' and t2.type == '[' then
      table.insert(tokens, j, {type=",", value=","})
      j = j + 1
    end
    j = j + 1
  end

  -- Insert implicit multiplication tokens as before
  local j = 2
  while j <= #tokens do
    local t1, t2 = tokens[j-1], tokens[j]
    if (t1.type == 'number' or t1.type == ')' ) and
       (t2.type == 'ident' or t2.type == '(' or t2.type == '[' or t2.type == 'integral_symbol') then -- Added integral_symbol
      table.insert(tokens, j, {type="op", value="*"})
      j = j + 1
    end
    j = j + 1
  end

  print("Final token list:")
  for _, tok in ipairs(tokens) do
    print(string.format("  %s : %s", tok.type, tostring(tok.value)))
  end
  return tokens
end

--[[
  Parses a tensor (nested list of expressions) from a token stream.
  @param tokens (table): The token list.
  @param idx (number): The current index in the token list.
  @return (table, number): The tensor AST node and the next token index.
]]
local function parse_tensor(tokens, idx)
  -- Expect '[' to start tensor.
  if not (tokens[idx] and tokens[idx].type == '[') then
    error(_G.errors.get("parse(matrix_syntax)") or errors.invalid("parse_tensor", "expected '[' to start tensor"))
  end

  local function parse_elements(i)
    local elements = {}
    local first = true
    while true do
      if tokens[i] and tokens[i].type == '[' then
        -- Recursively parse a sub-tensor and always wrap as {type="tensor", elements=...}
        local sub_elems, ni = parse_elements(i + 1)
        table.insert(elements, {type = "tensor", elements = sub_elems})
        i = ni
      elseif tokens[i] and tokens[i].type ~= ']' then
        -- Parse a scalar element
        local elem, ni = parser.parseExpr(tokens, i)
        if type(elem) == "number" then
          table.insert(elements, { type = "number", value = elem })
        else
          table.insert(elements, elem)
        end
        i = ni
      end
      if tokens[i] and tokens[i].type == ',' then
        i = i + 1
        first = false
      elseif tokens[i] and tokens[i].type == ']' then
        return elements, i + 1
      else
        break
      end
    end
    error(_G.errors.get("parse(ragged_matrix)") or errors.invalid("parse_tensor", "expected ',' or ']' in tensor definition"))
  end

  local i = idx + 1
  if tokens[i] and tokens[i].type == ']' then
    return {type="tensor", elements={}}, i + 1
  end

  local elements, ni = parse_elements(i)
  return {type="tensor", elements=elements}, ni
end

--[[
  Parses an integral expression from a token stream.
  Supports both indefinite (e.g., ∫(f(x), x)) and definite (e.g., ∫(f(x), x, a, b)) integrals.
  @param tokens (table): The token list.
  @param idx (number): The current index in the token list.
  @return (table, number): The integral AST node and the next token index.
]]
local function parse_integral(tokens, idx)
  local tok = tokens[idx]
  if not (tok and tok.type == "integral_symbol") then
    _G.errors.throw("parse(integral)") -- Consistent error throw
  end

  if not (tokens[idx + 1] and tokens[idx + 1].type == "(") then
    _G.errors.throw("parse(function_missing_args)", "integral") -- Consistent error throw
  end

  local integrand_expr, i = parser.parseExpr(tokens, idx + 2)
  if not (tokens[i] and tokens[i].type == ",") then
    _G.errors.throw("parse(integral)", "missing_comma_after_integrand") -- Consistent error throw
  end

  local var_token = tokens[i + 1]
  if not (var_token and var_token.type == "ident") then
    _G.errors.throw("parse(invalid_variable_name)", "integral_variable") -- Consistent error throw
  end

  i = i + 2 -- Move past var_token and comma (now at either ')' or ',')

  local integral_node = {
    type = "integral",
    integrand = integrand_expr,
    respect_to = { type = "variable", name = var_token.value }
  }

  -- Check for definite integral bounds
  if tokens[i] and tokens[i].type == "," then
    local lower_bound, ni1 = parser.parseExpr(tokens, i + 1)
    if not (tokens[ni1] and tokens[ni1].type == ",") then
      _G.errors.throw("parse(integral_limits)", "missing_comma_after_lower_bound") -- Consistent error throw
    end
    local upper_bound, ni2 = parser.parseExpr(tokens, ni1 + 1)
    if not (tokens[ni2] and tokens[ni2].type == ")") then
      _G.errors.throw("parse(unmatched_paren)", "integral_bounds") -- Consistent error throw
    end

    integral_node.lower_bound = lower_bound
    integral_node.upper_bound = upper_bound
    i = ni2 + 1 -- Move past upper_bound and closing parenthesis
  else
    -- For indefinite integral, expect closing parenthesis
    if not (tokens[i] and tokens[i].type == ")") then
      _G.errors.throw("parse(unmatched_paren)", "integral") -- Consistent error throw
    end
    i = i + 1
  end

  return integral_node, i
end

--[[
  A utility function to create a variable AST node.
  @param x (string): The name of the variable.
  @return (table): A variable AST node.
]]
local function make_var(x) return {type="variable", name=x} end

--[[
  Parses primary expressions such as numbers, variables, function calls,
  parenthesized expressions, and unary minus.
  @param tokens (table): The token list.
  @param idx (number): The current index in the token list.
  @return (table, number): The primary expression AST node and the next token index.
]]
local function parse_primary(tokens, idx)
  local tok = tokens[idx]
  if not tok then return nil, idx end

  --[[
    Wraps a node in a factorial function node if a '!' token follows it.
    @param node (table): The AST node to wrap.
    @param i (number): The current index.
    @return (table, number): The new node (or original) and the next index.
  ]]
  local function wrap_factorial(node, i)
    if tokens[i] and tokens[i].type == "op" and tokens[i].value == "!" then
      return {
        type = "func",
        name = "factorial",
        args = { node }
      }, i + 1
    end
    return node, i
  end

  -- Derivative node: (d/dx)(expr) pattern
  if tok.type == "derivative" then
    local expr, ni = parser.parseExpr(tokens, idx + 1)
    return {type="derivative", respect_to="x", expr=expr}, ni
  end

  if tok.type == "integral_symbol" then -- Use the new token type
    return parse_integral(tokens, idx)
  elseif tok.type == "number" then
    return wrap_factorial({type="number", value=tok.value}, idx+1)
  elseif tok.type == "ident" then
    if tokens[idx + 1] and tokens[idx + 1].type == "(" then
      -- Special handling for series(func, var, center, order)
      if tok.value == "series" then
        local i = idx + 2
        local func_expr, ni = parser.parseExpr(tokens, i)
        if not (tokens[ni] and tokens[ni].type == ",") then
          _G.errors.throw("parse(series)", "missing_comma_after_func")
        end
        local var_node, ni2 = parser.parseExpr(tokens, ni + 1)
        if not (tokens[ni2] and tokens[ni2].type == ",") then
          _G.errors.throw("parse(series)", "missing_comma_after_var")
        end
        local center_node, ni3 = parser.parseExpr(tokens, ni2 + 1)
        if not (tokens[ni3] and tokens[ni3].type == ",") then
          _G.errors.throw("parse(series)", "missing_comma_after_center")
        end
        local order_node, ni4 = parser.parseExpr(tokens, ni3 + 1)
        if not (tokens[ni4] and tokens[ni4].type == ")") then
          _G.errors.throw("parse(function_too_many_args)", "series_missing_close_paren")
        end
        return {
          type = "series",
          func = func_expr,
          var = var_node,
          center = center_node,
          order = order_node
        }, ni4 + 1
      end
      
      -- Debug version of the limit parsing logic
      if tok.value == "lim" then
        -- Parse lim(expr, var, to, direction) format
        print("DEBUG: Starting lim parse")
        
        if not (tokens[idx + 1] and tokens[idx + 1].type == "(") then
          _G.errors.throw("parse(limit_syntax)", "expected '(' after lim")
        end
        
        local i = idx + 2
        print("DEBUG: About to parse expression starting at token " .. i)
        if tokens[i] then
          print("DEBUG: Token at " .. i .. " is: " .. tokens[i].type .. " = " .. tostring(tokens[i].value))
        end
        
        -- Parse the expression to take the limit of
        local expr, ni = parser.parseExpr(tokens, i)
        print("DEBUG: Parsed expression, now at token " .. ni)
        if tokens[ni] then
          print("DEBUG: Token at " .. ni .. " is: " .. tokens[ni].type .. " = " .. tostring(tokens[ni].value))
        else
          print("DEBUG: No token at " .. ni .. " (end of tokens?)")
        end
        
        if not (tokens[ni] and tokens[ni].type == ",") then
          _G.errors.throw("parse(limit_syntax)", "expected ',' after limit expression but got " .. 
               (tokens[ni] and tokens[ni].type or "nil"))
        end
        
        -- Parse the variable
        local var_token = tokens[ni + 1]
        print("DEBUG: Variable token: " .. (var_token and var_token.type or "nil") .. " = " .. 
              (var_token and tostring(var_token.value) or "nil"))
        if not (var_token and var_token.type == "ident") then
          _G.errors.throw("parse(function_missing_args)", "limit_expected_variable")
        end
        
        if not (tokens[ni + 2] and tokens[ni + 2].type == ",") then
          _G.errors.throw("parse(limit_syntax)", "expected ',' after variable")
        end
        
        -- Parse the value we're approaching
        local to_val, ni3 = parser.parseExpr(tokens, ni + 3)
        print("DEBUG: Parsed limit value, now at token " .. ni3)
        
        if not (tokens[ni3] and tokens[ni3].type == ")") then
          _G.errors.throw("parse(unmatched_paren)", "limit_missing_close_paren")
        end
        
        -- Actually compute the damn limit like we're supposed to
        local expr_str = ast_to_string(expr)
        local to_str = ast_to_string(to_val)
        
        print("DEBUG: expr_str = '" .. expr_str .. "'")
        print("DEBUG: var = '" .. var_token.value .. "'")
        print("DEBUG: to_str = '" .. to_str .. "'")
        
        -- Call the beautiful limit function
        local ok, result = pcall(_G.lim, expr_str, var_token.value, to_str, direction)
        if not ok then
          print("DEBUG: _G.lim failed with: " .. tostring(result))
          _G.errors.throw("eval(undefined_at_point)", "limit evaluation failed: " .. tostring(result))
        end
        
        print("DEBUG: _G.lim returned: " .. tostring(result))
        return result, ni3 + 1
      end
      
      -- NEW: Handle binomial_expand function call
      if tok.value == "binomial_expand" then
        local i = idx + 2
        local expr_to_expand, ni = parser.parseExpr(tokens, i) -- Parse the expression argument
        if not (tokens[ni] and tokens[ni].type == ")") then
          _G.errors.throw("parse(function_missing_args)", "binomial_expand_missing_close_paren")
        end
        -- Call the actual _G.binomial_expand function from fraction.lua
        -- Note: _G.binomial_expand expects an AST node for base and exp, not a string or the full AST of (base^exp).
        -- This means we need to ensure expr_to_expand is of type 'pow'.
        if expr_to_expand.type ~= "pow" then
            _G.errors.throw("parse(function_too_many_args)", "binomial_expand expects a power expression (e.g., (x+y)^n)")
        end
        -- Call _G.binomial_expand, which requires 'base' and 'exp' nodes
        local expanded_ast = _G.binomial_expand(expr_to_expand.base, expr_to_expand.exp)
        
        -- If expansion results in a new AST, use it. Otherwise, keep the original representation or error.
        if expanded_ast and expanded_ast.type ~= "binomial_expand_failed" then
            return expanded_ast, ni + 1
        else
            -- If binomial_expand failed, you can either return the unexpanded form
            -- or return a specific error node for later processing/display.
            -- For simplicity, we'll return the original power node for now,
            -- allowing further processing if desired (e.g., by _G.simplify.simplify_step).
            return expr_to_expand, ni + 1
        end
      -- NEW: Handle fraction_simplify function call
      elseif tok.value == "fraction_simplify" then
        local i = idx + 2
        local expr_to_simplify, ni = parser.parseExpr(tokens, i) -- Parse the expression argument
        if not (tokens[ni] and tokens[ni].type == ")") then
          _G.errors.throw("parse(function_missing_args)", "fraction_simplify_missing_close_paren")
        end
        -- Call the actual _G.simplify_fraction function from fraction.lua
        -- Note: _G.simplify_fraction expects an AST node, not a string
        local simplified_ast = _G.simplify_fraction(expr_to_simplify)
        return simplified_ast, ni + 1
      end
      
      local args = {}
      local i = idx + 2
      if tokens[i] and tokens[i].type ~= ")" then
        local arg_node
        arg_node, i = parser.parseExpr(tokens, i)
        table.insert(args, arg_node)
        while tokens[i] and tokens[i].type == "," do
          local next_arg
          next_arg, i = parser.parseExpr(tokens, i + 1)
          table.insert(args, next_arg)
        end
      end
      if not (tokens[i] and tokens[i].type == ")") then
        _G.errors.throw("parse(unmatched_paren)", "function_call_missing_close_paren")
      end
      return wrap_factorial({ type="func", name=tok.value, args=args }, i + 1)
    else
      local physics_constants = _G.physics and _G.physics.constants or nil
      if physics_constants and physics_constants[tok.value] then
        -- Use deepcopy to avoid shared state for constant value nodes
        local deepcopy = rawget(_G, "deepcopy") or function(tbl)
          if type(tbl) ~= "table" then return tbl end
          local t2 = {}
          for k, v in pairs(tbl) do
            t2[k] = type(v) == "table" and deepcopy(v) or v
          end
          return t2
        end
        local constant_entry = physics_constants[tok.value]
        local val_node = deepcopy(constant_entry.value)
        local node = {type="constant", name=tok.value, value=val_node}
        return wrap_factorial(node, idx + 1)
      else
        return wrap_factorial({type="variable", name=tok.value}, idx + 1)
      end
    end
  elseif tok.type == '(' then
    -- Detect general derivative notation (d)/(dx)(expr)
    if tokens[idx+1] and tokens[idx+1].type == 'ident' and tokens[idx+1].value == 'd' then
      if tokens[idx+2] and tokens[idx+2].type == ')' and
   tokens[idx+3] and tokens[idx+3].type == 'op' and tokens[idx+3].value == '/' and
   tokens[idx+4] and tokens[idx+4].type == '(' and
   tokens[idx+5] and tokens[idx+5].type == 'ident' and tokens[idx+5].value == 'dx' and
   tokens[idx+6] and tokens[idx+6].type == ')' then
        local expr, ni = parser.parseExpr(tokens, idx + 7)
        return {
            type = "derivative",
            respect_to = "x",
            expr = expr
        }, ni
      end
    end
    local node, ni = parser.parseExpr(tokens, idx+1)
    if not (tokens[ni] and tokens[ni].type == ')') then
      _G.errors.throw("parse(unmatched_paren)", "parenthesized_expression")
    end
    return wrap_factorial(node, ni+1)
  elseif tok.type == '[' then
    local tensor, ni = parse_tensor(tokens, idx)
    return wrap_factorial(tensor, ni)
  elseif tok.type == 'string' then
    return {type='string', value=tok.value}, idx + 1
  elseif tok.type == "op" and tok.value == '-' then
    local expr, ni = parser.parseExpr(tokens, idx+1)
    return wrap_factorial({type="neg", value=expr}, ni)
  else
    _G.errors.throw("parse(what_is_that)", tok.type or '?')
  end
end

--[[
  Parses exponentiation expressions, which are right-associative.
  @param tokens (table): The token list.
  @param idx (number): The current index in the token list.
  @return (table, number): The power AST node and the next token index.
]]
local function parse_power(tokens, idx)
  local left, i = parse_primary(tokens, idx)
  while tokens[i] and tokens[i].type == "op" and tokens[i].value == '^' do
    local right
    right, i = parse_primary(tokens, i+1)
    left = {type="pow", base=left, exp=right}
  end
  return left, i
end

--[[
  Parses multiplication and division expressions.
  Division is handled as multiplication by the reciprocal to simplify later processing.
  @param tokens (table): The token list.
  @param idx (number): The current index in the token list.
  @return (table, number): The term AST node and the next token index.
]]
local function parse_term(tokens, idx)
  -- Parse the first factor
  local factors = {}
  local i = idx
  local node, ni = parse_power(tokens, i)
  table.insert(factors, node)
  i = ni
  while tokens[i] and tokens[i].type == "op" and (tokens[i].value == '*' or tokens[i].value == '/') do
    local op = tokens[i].value
    local right
    right, i = parse_power(tokens, i+1)
    if op == '*' then
      table.insert(factors, right)
    else
      
      table.insert(factors, {type="pow", base=right, exp={type="number", value=-1}})
    end
  end
  if #factors == 1 then
    return factors[1], i
  else
    return {type="mul", args=factors}, i
  end
end

--[[
  Parses addition and subtraction expressions.
  This is the main entry point for parsing arithmetic expressions. It handles
  the lowest-precedence operators and equation definitions.
  @param tokens (table): The token list.
  @param idx (number): The current index in the token list.
  @return (table, number): The expression AST node and the next token index.
]]
function parser.parseExpr(tokens, idx)
  idx = idx or 1
  local terms = {}
  local signs = {}
  local node, i = parse_term(tokens, idx)
  table.insert(terms, node)
  table.insert(signs, 1)
  while tokens[i] and tokens[i].type == "op" and (tokens[i].value == '+' or tokens[i].value == '-') do
    local op = tokens[i].value
    local right
    right, i = parse_term(tokens, i+1)
    if op == '+' then
      table.insert(terms, right)
      table.insert(signs, 1)
    else
      -- Instead of wrapping just numbers in neg, wrap the whole right term
      table.insert(terms, right)
      table.insert(signs, -1)
    end
  end
  -- Flatten into n-ary add
  if #terms == 1 then
    if tokens[i] and tokens[i].type == "equals" then
      local rhs, next_i = parser.parseExpr(tokens, i + 1)
      return {type = "equation", left = node, right = rhs}, next_i -- Because equations make everything more complicated.
    end
    return node, i
  else
    local args = {}
    for j = 1, #terms do
      if signs[j] == 1 then
        table.insert(args, terms[j])
      else
        table.insert(args, {type="neg", value=terms[j]})
      end
    end
    local add_node = {type="add", args=args}
    if tokens[i] and tokens[i].type == "equals" then
      local rhs, next_i = parser.parseExpr(tokens, i + 1)
      return {type = "equation", left = add_node, right = rhs}, next_i -- Because why stop at arithmetic when you can do algebra?
    end
    return add_node, i
  end
end

--[[
  Builds the final AST from a token stream.
  This is the primary entry point for the parser. It calls parseExpr and
  verifies that the entire token stream was consumed.
  @param tokens (table): The token list.
  @return (table): The root AST node.
]]
function parser.buildAST(tokens)
  local ast, idx = parser.parseExpr(tokens, 1)
  if idx <= #tokens then
    _G.errors.throw("parse(unexpected_eof)", tokens[idx].type or '?')
  end
  return ast
end

--[[
  Parses a raw expression string into a simplified AST.
  This function orchestrates the entire process: tokenization, AST construction,
  and preliminary simplification/evaluation.
  @param expr (string): The mathematical expression string.
  @return (table): The root AST node after simplification.
]]
function parser.parse(expr)
  -- Get physics constants table and category from global
  local constants = _G.physics and _G.physics.constants or nil
  local constants_off = _G.var and _G.var.recall and _G.var.recall("constants_off")
  local current_category = _G.current_constant_category or "fundamental"

  -- Tokenize first, then replace identifier tokens with constants if appropriate
  local tokens = parser.tokenize(expr)

  -- Replace identifiers matching constant symbols after tokenizing
  if constants and not constants_off then
      for _, tok in ipairs(tokens) do
          if tok.type == "ident" and constants[tok.value] then
              if _G.physics.is_constant_enabled(tok.value) and
                 (not current_category or constants[tok.value].category == current_category or constants[tok.value].category == nil) then
                  -- Replace identifier with constant name if symbol matches
                  tok.type = "constant"
                  tok.name = tok.value
                  tok.value = nil
              end
          end
      end
  end

  -- Proceed with building AST etc...
  local ok, ast_or_err = pcall(parser.buildAST, tokens)
  if not ok then
    local err_msg = tostring(ast_or_err)
    if err_msg:find("parse%(series%)") then
      _G.errors.throw("parse(series)")
    elseif err_msg:find("parse%(integral%)") then -- Catches errors from parse_integral
      _G.errors.throw("parse(integral)")
    elseif err_msg:find("d/dx%(nothing%)") then -- Catches errors from derivative parse
      _G.errors.throw("d/dx(nothing)")
    elseif err_msg:find("parse%(matrix_syntax%)") then
      _G.errors.throw("parse(matrix_syntax)")
    elseif err_msg:find("parse%(limit_syntax%)") then
      _G.errors.throw("parse(limit_syntax)")
    elseif err_msg:find("parse%(function_missing_args%)") then
        local func = err_msg:match("function_missing_args%) Error: Function call missing arguments%. Did you forget to feed the function%?%s*(.+)") -- Attempt to extract func name
        _G.errors.throw("parse(function_missing_args)", func or "unknown_func")
    elseif err_msg:find("parse%(function_too_many_args%)") then
        _G.errors.throw("parse(function_too_many_args)")
    elseif err_msg:find("parse%(unmatched_paren%)") then
        _G.errors.throw("parse(unmatched_paren)")
    elseif err_msg:find("parse%(invalid_variable_name%)") then
        local hint = err_msg:match("invalid_variable_name%) Error: Invalid variable name%.%s*(.+)")
        _G.errors.throw("parse(invalid_variable_name)", hint or "generic")
    elseif err_msg:find("parse%(unexpected_token%)") then
        local token_type = err_msg:match("unexpected_token%) Error: Unexpected token%. It's like you're speaking in tongues, I can't parse that garbage%.%s*(.+)")
        _G.errors.throw("parse(unexpected_token)", token_type or "generic")
    elseif err_msg:find("parse%(invalid_character%)") then
        _G.errors.throw("parse(invalid_character)")
    elseif err_msg:find("parse%(malformed_power%)") then
        _G.errors.throw("parse(malformed_power)")
    elseif err_msg:find("parse%(ragged_matrix%)") then
        _G.errors.throw("parse(ragged_matrix)")
    elseif err_msg:find("parse%(what_is_that%)") then
        _G.errors.throw("parse(what_is_that)")
    elseif err_msg:find("parse%(syntax%)") then
      _G.errors.throw("parse(syntax)") -- Generic parse error if specific ones not found
    else
      -- Fallback for completely unmapped pcall errors
      _G.errors.throw("parse(gibberish)", err_msg)
    end
  end
  
  local ast_node = ast_or_err -- If pcall was successful, ast_or_err is the AST
  
  -- Automatically simplify after parsing if possible
  local simplified = rawget(_G, "simplify") and _G.simplify.simplify_step and _G.simplify.simplify_step(ast_node) or ast_node

  -- Evaluate factorial and integral nodes if possible (replace factorial(func(number)) with number node, and int(number, var) with number node)
  --[[
    Recursively evaluates certain nodes in the AST (e.g., numeric factorials).
    @param node (table): The AST node to evaluate.
    @return (table): The evaluated AST node.
  ]]
  local function evaluate_nodes(node)
      if type(node) ~= "table" then return node end

      -- Evaluate factorial for numeric args
      if node.type == "func" and node.name == "factorial" and node.args and #node.args == 1 then
          local arg = evaluate_nodes(node.args[1])
          if arg.type == "number" and _G.evaluateFactorial then
              return { type = "number", value = _G.evaluateFactorial(arg.value) }
          end
          node.args[1] = arg
          return node
      end

      -- Integral nodes are now handled by the integral function directly, not here
      -- This section might need adjustment if you want *numeric* integrals to resolve here.
      -- For symbolic, you want the 'integral' AST node to persist.
      if node.type == "integral" then
          -- If the integral contains only numeric parts and can be evaluated fully to a number,
          -- you might call _G.integrate.eval with bounds here.
          -- Otherwise, let it remain an AST node to be handled by the full integration logic.
          return node
      end

      -- Recurse for common node types with children
      if node.args then
          for i, arg in ipairs(node.args) do
              node.args[i] = evaluate_nodes(arg)
          end
      elseif node.left then
          node.left = evaluate_nodes(node.left)
          if node.right then node.right = evaluate_nodes(node.right) end
      elseif node.base then
          node.base = evaluate_nodes(node.base)
          if node.exp then node.exp = evaluate_nodes(node.exp) end
      elseif node.arg then
          node.arg = evaluate_nodes(node.arg)
      elseif node.value and type(node.value) == "table" then
          node.value = evaluate_nodes(node.value)
      end
      return node
  end

  local evaluated = evaluate_nodes(simplified)
  return evaluated
end

--[[
  A global table containing all parser functions.
]]
_G.parser = parser

--[[
  The main public parsing function, aliased to the parser's parse method.
  @param expr (string): The expression string to parse.
  @return (table): The simplified AST.
]]
_G.parse = parser.parse


-- Expose a direct solve_equation interface for global use
if _G.solve_equation then
  _G.solve = function(expr)
    local ast = parser.parse(expr)
    return _G.solve_equation(ast)
  end
end

-- Wraps two arguments in a 'sub' node.
function parser.make_sub(left, right)
  return {type = "sub", left = left, right = right}
end

-- Wraps two arguments in a 'div' node.
function parser.make_div(num, denom)
  return {type = "div", left = num, right = denom}
end


-- Greek letter aliases (UTF-8 mapped to standard names)
-- Greek letter aliases for physics constants (assumes Constants table exists)
if _G.Constants then
    -- Basic Greek alphabet
    Constants[utf8(945)] = Constants["alpha"] or Constants[utf8(945)]  -- α (fine structure already exists)
Constants[utf8(946)] = Constants["beta"]                           -- β  
Constants[utf8(947)] = Constants["gamma"]                          -- γ
Constants[utf8(948)] = Constants["delta"]                          -- δ
Constants[utf8(949)] = Constants["epsilon"] or Constants[utf8(949).."0"] -- ε (permittivity already exists)
Constants[utf8(950)] = Constants["zeta"]                           -- ζ
Constants[utf8(951)] = Constants["eta"]                            -- η
Constants[utf8(952)] = Constants["theta"]                          -- θ
Constants[utf8(953)] = Constants["iota"]                           -- ι
Constants[utf8(954)] = Constants["kappa"]                          -- κ
Constants[utf8(955)] = Constants["lambda"]                         -- λ
Constants[utf8(956)] = Constants["mu"] or Constants[utf8(956).."0"] -- μ (permeability already exists)
Constants[utf8(957)] = Constants["nu"]                             -- ν
Constants[utf8(958)] = Constants["xi"]                             -- ξ
Constants[utf8(959)] = Constants["omicron"]                        -- ο
Constants[utf8(960)] = Constants["pi"]                             -- π (already exists)
Constants[utf8(961)] = Constants["rho"]                            -- ρ
Constants[utf8(962)] = Constants["sigma_final"]                    -- ς (final sigma)
Constants[utf8(963)] = Constants["sigma"]                          -- σ
Constants[utf8(964)] = Constants["tau"]                            -- τ
Constants[utf8(965)] = Constants["upsilon"]                        -- υ
Constants[utf8(966)] = Constants["phi"]                            -- φ
Constants[utf8(967)] = Constants["chi"]                            -- χ
Constants[utf8(968)] = Constants["psi"]                            -- ψ
Constants[utf8(969)] = Constants["omega"]                          -- ω

-- Greek letters (uppercase)
Constants[utf8(913)] = Constants["Alpha"]                          -- Α
Constants[utf8(914)] = Constants["Beta"]                           -- Β
Constants[utf8(915)] = Constants["Gamma"]                          -- Γ
Constants[utf8(916)] = Constants["Delta"]                          -- Δ
Constants[utf8(917)] = Constants["Epsilon"]                        -- Ε
Constants[utf8(918)] = Constants["Zeta"]                           -- Ζ
Constants[utf8(919)] = Constants["Eta"]                            -- Η
Constants[utf8(920)] = Constants["Theta"]                          -- Θ
Constants[utf8(921)] = Constants["Iota"]                           -- Ι
Constants[utf8(922)] = Constants["Kappa"]                          -- Κ
Constants[utf8(923)] = Constants["Lambda"]                         -- Λ
Constants[utf8(924)] = Constants["Mu"]                             -- Μ
Constants[utf8(925)] = Constants["Nu"]                             -- Ν
Constants[utf8(926)] = Constants["Xi"]                             -- Ξ
Constants[utf8(927)] = Constants["Omicron"]                        -- Ο
Constants[utf8(928)] = Constants["Pi"]                             -- Π
Constants[utf8(929)] = Constants["Rho"]                            -- Ρ
Constants[utf8(931)] = Constants["Sigma"]                          -- Σ
Constants[utf8(932)] = Constants["Tau"]                            -- Τ
Constants[utf8(933)] = Constants["Upsilon"]                        -- Υ
Constants[utf8(934)] = Constants["Phi"]                            -- Φ
Constants[utf8(935)] = Constants["Chi"]                            -- Χ
Constants[utf8(936)] = Constants["Psi"]                            -- Ψ
Constants[utf8(937)] = Constants["Omega"]                          -- Ω

-- PHYSICS-SPECIFIC CONSTANTS AND ALIASES

-- Common physics symbols
Constants[utf8(8463)] = Constants["h"] or Constants["planck"]      -- ℏ (reduced Planck)
Constants["hbar"] = Constants[utf8(8463)]

-- Mass-energy relations
Constants[utf8(956).."e"] = Constants["me"]                        -- μe (electron mass)
Constants[utf8(956).."p"] = Constants["mp"]                        -- μp (proton mass) 
Constants[utf8(956).."n"] = Constants["mn"]                        -- μn (neutron mass)

-- Coupling constants
Constants[utf8(945).."s"] = Constants["strong_coupling"]           -- αs (strong coupling)
Constants[utf8(945).."em"] = Constants[utf8(945)]                  -- αem (electromagnetic, same as fine structure)

-- Particle physics masses (if you add them)
Constants[utf8(956).."_e"] = Constants["electron_mass"]            -- μ_e
Constants[utf8(956).."_"..utf8(956)] = Constants["muon_mass"]      -- μ_μ (muon)
Constants[utf8(956).."_"..utf8(964)] = Constants["tau_mass"]       -- μ_τ (tau)
Constants["m_W"] = Constants["w_boson_mass"]                       -- W boson
Constants["m_Z"] = Constants["z_boson_mass"]                       -- Z boson
Constants["m_H"] = Constants["higgs_mass"]                         -- Higgs
Constants["m_t"] = Constants["top_mass"]                          -- top quark
Constants["m_b"] = Constants["bottom_mass"]                       -- bottom quark
Constants["m_c"] = Constants["charm_mass"]                        -- charm quark
Constants["m_s"] = Constants["strange_mass"]                      -- strange quark
Constants["m_u"] = Constants["up_mass"]                           -- up quark
Constants["m_d"] = Constants["down_mass"]                         -- down quark

-- QCD scale
Constants[utf8(923).."_QCD"] = Constants["lambda_qcd"]            -- Λ_QCD
Constants[utf8(952).."_QCD"] = Constants["theta_qcd"]             -- θ_QCD

-- Weinberg angle
Constants[utf8(952).."_W"] = Constants["weinberg_angle"]          -- θ_W
Constants["sin2"..utf8(952).."_W"] = Constants["sin2_theta_w"]    -- sin²θ_W

-- Cosmological constants
Constants[utf8(923)] = Constants["cosmological_constant"]         -- Λ
Constants[utf8(937).."_m"] = Constants["matter_density"]          -- Ω_m
Constants[utf8(937).."_"..utf8(923)] = Constants["dark_energy"]  -- Ω_Λ
Constants[utf8(937).."_b"] = Constants["baryon_density"]          -- Ω_b
Constants["H_0"] = Constants["hubble_constant"]                   -- H₀

-- Thermodynamic
Constants[utf8(946)] = Constants["inverse_temperature"]           -- β = 1/(kT)
Constants[utf8(963).."_SB"] = Constants["stefan_boltzmann"]       -- σ_SB

-- CKM matrix elements (quark mixing)
Constants["V_ud"] = Constants["ckm_ud"]
Constants["V_us"] = Constants["ckm_us"] 
Constants["V_ub"] = Constants["ckm_ub"]
Constants["V_cd"] = Constants["ckm_cd"]
Constants["V_cs"] = Constants["ckm_cs"]
Constants["V_cb"] = Constants["ckm_cb"]
Constants["V_td"] = Constants["ckm_td"]
Constants["V_ts"] = Constants["ckm_ts"]
Constants["V_tb"] = Constants["ckm_tb"]

-- PMNS matrix elements (neutrino mixing)
Constants[utf8(952).."_12"] = Constants["solar_angle"]           -- θ₁₂
Constants[utf8(952).."_23"] = Constants["atmospheric_angle"]     -- θ₂₃  
Constants[utf8(952).."_13"] = Constants["reactor_angle"]         -- θ₁₃
Constants[utf8(948).."_CP"] = Constants["cp_phase"]              -- δ_CP

-- Neutrino mass differences
Constants[utf8(916).."m2_21"] = Constants["delta_m21_squared"]   -- Δm²₂₁
Constants[utf8(916).."m2_31"] = Constants["delta_m31_squared"]   -- Δm²₃₁

-- Running couplings (scale dependent)
Constants[utf8(945).."("..utf8(956)..")"] = Constants["running_alpha"]     -- α(μ)
Constants[utf8(945).."s("..utf8(956)..")"] = Constants["running_alphas"]   -- αs(μ)

-- Renormalization scales  
Constants[utf8(956).."_R"] = Constants["renormalization_scale"]  -- μ_R
Constants[utf8(956).."_F"] = Constants["factorization_scale"]    -- μ_F

-- Effective field theory cutoffs
Constants[utf8(923).."_UV"] = Constants["uv_cutoff"]             -- Λ_UV
Constants[utf8(923).."_IR"] = Constants["ir_cutoff"]             -- Λ_IR

-- Supersymmetry parameters
Constants["M_SUSY"] = Constants["susy_scale"]
Constants["tan"..utf8(946)] = Constants["tan_beta"]              -- tan β
Constants[utf8(956).."_SUSY"] = Constants["susy_mu"]             -- μ_SUSY

-- Axion physics
Constants["f_a"] = Constants["axion_decay_constant"]             -- f_a
Constants[utf8(952).."_strong"] = Constants["strong_cp_angle"]   -- θ_strong

-- Dark matter
Constants[utf8(963).."_SI"] = Constants["dm_si_cross_section"]   -- σ_SI
Constants[utf8(963).."_SD"] = Constants["dm_sd_cross_section"]   -- σ_SD
Constants["<"..utf8(963).."v>"] = Constants["dm_annihilation"]   -- ⟨σv⟩

-- Extra dimensions
Constants["M_D"] = Constants["extra_dim_scale"]
Constants["R_extra"] = Constants["extra_dim_radius"]

-- String theory scale
Constants["M_string"] = Constants["string_scale"]
Constants["M_Pl"] = Constants["planck_mass"]

-- AdS/CFT
Constants["L_AdS"] = Constants["ads_radius"]
Constants["c_central"] = Constants["central_charge"]

-- Instantons and topology
Constants[utf8(952)] = Constants["theta_angle"]                  -- θ
Constants["w"] = Constants["winding_number"]
end