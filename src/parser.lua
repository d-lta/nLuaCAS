-- parser.lua: Because writing your own parser is the best way to avoid happiness.
--
-- For those who care about "compatibility": yes, the API is still the same.
--   tokenize(expr) => {tokens} -- like anyone remembers the output.
--   buildAST(tokens) => ast    -- because trees are the only way to understand math.
--   parseExpr(tokens, idx) => ast, nextIdx -- because recursion is fun until it isn't.
--
-- Now with more "features" you didn't ask for: error nagging, big numbers, functions, brackets, sneaky multiplication, negative numbers, and, because why not, matrix parsing.

local parser = {}
local init = rawget(_G, "init")
local errors = rawget(_G, "errors") or {
  invalid = function(fn, hint)
    return "parse(" .. (fn or "?") .. "): " .. (hint or "unknown error. also: _G.errors was nil.")
  end
}

-- Because seeing your AST in tree form is the only joy you'll get today.
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
  else
    for k, v in pairs(ast) do
      print(indent .. tostring(k) .. ":")
      print_ast(v, indent .. "  ")
    end
  end
end
parser.print_ast = print_ast
_G.print_ast = print_ast

-- Tokenizer: Because parsing math without slicing it into tiny pieces would be too easy.

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

-- Adjust is_alpha to recognize ascii letters and greek utf8 letters (add more if needed)
local function is_alpha(c)
  -- ASCII letters
  if c:match("^[%a_]$") then return true end
  -- Common Greek letters and others can be added here
  -- For demo, accept anything with byte length > 1 (non-ASCII)
  if #c > 1 then return true end
  return false
end

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
      table.insert(tokens, {type="integral", value=c})
      print(string.format("Token: [integral] %s", c))
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
        error(errors.invalid('tokenize', 'unterminated string literal'))
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
      elseif c == '∫' then ttype = "integral"
      elseif c == '+' or c == '-' or c == '*' or c == '/' or c == '^' or c == '!' then ttype = "op"
      else ttype = "unknown" end
      table.insert(tokens, {type=ttype, value=c})
      print(string.format("Token: [%s] %s", ttype, c))
      i = i + clen
    else
      error(errors.invalid("tokenize", "unknown character: " .. c))
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
       (t2.type == 'ident' or t2.type == '(' or t2.type == '[') then
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

-- Parser: Because recursion is the only way to feel alive.
--   Now with precedence, unary minus, function calls, and, of course, matrices.


-- Tensor parsing: supports arbitrary rank tensors (nested lists of expressions).
local function parse_tensor(tokens, idx)
  -- Expect '[' to start tensor.
  assert(tokens[idx] and tokens[idx].type == '[',
         errors.invalid("parse_tensor", "expected '[' to start tensor (did you mean to type something else?)"))

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
    error(errors.invalid("parse_tensor", "expected ',' or ']' in tensor definition"))
  end

  local i = idx + 1
  if tokens[i] and tokens[i].type == ']' then
    return {type="tensor", elements={}}, i + 1
  end

  local elements, ni = parse_elements(i)
  return {type="tensor", elements=elements}, ni
end

-- Handles literals, variables, function calls, parentheses, matrices, and unary minus.
-- Also wraps things in factorials if someone thought 'x!' was a good idea. Because, why not.
local function make_var(x) return {type="variable", name=x} end -- Because variables need love too.

-- Integral parsing: parses ∫(expression, variable)
local function parse_integral(tokens, idx)
  -- ∫(expression, variable) format
  local tok = tokens[idx]
  assert(tok and tok.type == "integral", "expected ∫ symbol")

  assert(tokens[idx + 1] and tokens[idx + 1].type == "(", "expected '(' after ∫")

  local expr, i = parser.parseExpr(tokens, idx + 2)
  assert(tokens[i] and tokens[i].type == ",", "expected ',' after integral expression")

  local var_token = tokens[i + 1]
  assert(var_token and var_token.type == "ident", "expected variable name after ',' in integral")

  assert(tokens[i + 2] and tokens[i + 2].type == ")", "expected ')' to close integral")

  return {
    type = "func",
    name = "int",
    args = { expr, { type = "variable", name = var_token.value } }
  }, i + 3
end

local function parse_primary(tokens, idx)
  local tok = tokens[idx]
  if not tok then return nil, idx end

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

  if tok.type == "integral" then
    return parse_integral(tokens, idx)
  elseif tok.type == "number" then
    return wrap_factorial({type="number", value=tok.value}, idx+1)
  elseif tok.type == "ident" then
    if tokens[idx + 1] and tokens[idx + 1].type == "(" then
      -- Special handling for series(func, var, center, order)
      if tok.value == "series" then
        local i = idx + 2
        local func_expr, ni = parser.parseExpr(tokens, i)
        if not (tokens[ni] and tokens[ni].type == ",") then error("Error: Failed to parse the series expression. Did you use correct syntax?") end
        local var_node, ni2 = parser.parseExpr(tokens, ni + 1)
        if not (tokens[ni2] and tokens[ni2].type == ",") then error("Error: Failed to parse the series expression. Did you use correct syntax?") end
        local center_node, ni3 = parser.parseExpr(tokens, ni2 + 1)
        if not (tokens[ni3] and tokens[ni3].type == ",") then error("Error: Failed to parse the series expression. Did you use correct syntax?") end
        local order_node, ni4 = parser.parseExpr(tokens, ni3 + 1)
        if not (tokens[ni4] and tokens[ni4].type == ")") then error("Error: Failed to parse the series expression. Did you use correct syntax?") end
        return {
          type = "series",
          func = func_expr,
          var = var_node,
          center = center_node,
          order = order_node
        }, ni4 + 1
      end
      -- Function call detected (non-series)
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
      assert(tokens[i] and tokens[i].type == ")", "expected ')' after function arguments")
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
    assert(tokens[ni] and tokens[ni].type == ')', "expected ')'")
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
    error("unexpected token at parse_primary: " .. (tok.type or '?'))
  end
end

-- Parses exponentiation. Right-associative, because math teachers said so.
local function parse_power(tokens, idx)
  local left, i = parse_primary(tokens, idx)
  while tokens[i] and tokens[i].type == "op" and tokens[i].value == '^' do
    local right
    right, i = parse_primary(tokens, i+1)
    left = {type="pow", base=left, exp=right}
  end
  return left, i
end

-- Handles multiplication, division, and reciprocal logic.
-- Because a/b is really just a*1/b, right? (Sure, let's pretend.)
local function parse_term(tokens, idx)
  -- Parse the first factor, because you have to start somewhere.
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
      -- Division: because why not multiply by the reciprocal and confuse everyone.
      table.insert(factors, {type="pow", base=right, exp={type="number", value=-1}})
    end
  end
  if #factors == 1 then
    return factors[1], i
  else
    return {type="mul", args=factors}, i
  end
end

-- The real entry point for expressions. Supports + and -, but mostly supports your suffering.
-- Folds everything into a single add tree so simplify() doesn't go on strike.
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
  -- Flatten into n-ary add, handling subtraction as add of negative (because why not make it harder?)
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

-- Wraps parseExpr and checks for leftovers.
-- If you forgot a bracket, this will find it and yell at you.
function parser.buildAST(tokens)
  local ast, idx = parser.parseExpr(tokens, 1)
  if idx <= #tokens then
    error(errors.invalid("parse", "unexpected " .. tostring(tokens[idx].type or "?") .. " (you left something behind)"))
  end
  return ast
end

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
    if err_msg:match("parse%(series%)") then
      error(errors.invalid("parse(series)", err_msg))
    elseif err_msg:match("parse%(integral%)") then
      error(errors.invalid("parse(integral)", err_msg))
    elseif err_msg:match("parse%(derivative%)") then
      error(errors.invalid("parse(derivative)", err_msg))
    elseif err_msg:match("parse%(matrix%)") then
      error(errors.invalid("parse(matrix)", err_msg))
    else
      error(errors.invalid("parse", err_msg))
    end
  end
  -- Automatically simplify after parsing if possible
  local simplified = rawget(_G, "simplify") and _G.simplify.simplify_step and _G.simplify.simplify_step(ast_or_err) or ast_or_err

  -- Evaluate factorial and integral nodes if possible (replace factorial(func(number)) with number node, and int(number, var) with number node)
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

      -- Evaluate integral if expr is numeric
      if node.type == "func" and node.name == "int" and node.args and #node.args == 2 then
          local expr = evaluate_nodes(node.args[1])
          local var = evaluate_nodes(node.args[2])
          if expr.type == "number" and var.type == "variable" and _G.evaluateIntegral then
              return { type = "number", value = _G.evaluateIntegral(expr.value, var.name) }
          end
          node.args[1] = expr
          node.args[2] = var
          return node
      end

      -- Recurse
      if node.args then
          for i, arg in ipairs(node.args) do
              node.args[i] = evaluate_nodes(arg)
          end
      elseif node.value then
          node.value = evaluate_nodes(node.value)
      end
      return node
  end

  local evaluated = evaluate_nodes(simplified)
  return evaluated
end

_G.parser = parser
_G.parse = parser.parse

_G.parser = parser

-- Expose a direct solve_equation interface for global use, because everyone wants to solve everything.
if _G.solve_equation then
  _G.solve = function(expr)
    local ast = parser.parse(expr)
    return _G.solve_equation(ast)
  end
end

-- Wraps two arguments in a 'sub' node, because subtraction isn't just minus.
function parser.make_sub(left, right)
  return {type = "sub", left = left, right = right}
end

-- Wraps two arguments in a 'div' node, because division is just misunderstood multiplication.
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
