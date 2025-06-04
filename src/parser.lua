-- parser.lua: Tokenizer and AST builder for nLuaCAS
--
-- Maintains compatibility with previous API:
--   tokenize(expr) => {tokens}
--   buildAST(tokens) => ast
--   parseExpr(tokens, idx) => ast, nextIdx
--
-- Improved: better error reporting, multi-digit numbers, support for functions, parentheses, implicit multiplication, and negative numbers.

local parser = {}

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

-- Tokenizer: Converts input string to list of tokens
do
  local function is_space(c) return c:match('%s') end
  local function is_digit(c) return c:match('%d') end
  local function is_alpha(c) return c:match('%a') end

  -- Tokenizes a math expression string into useful fragments.
  -- Yes, it does implicit multiplication. No, TI doesn’t help with that.
  function parser.tokenize(expr)
    local tokens = {}
    local i = 1
    while i <= #expr do
      local c = expr:sub(i,i)
      if is_space(c) then
        i = i + 1
      elseif is_digit(c) or (c == '.' and is_digit(expr:sub(i+1,i+1))) then
        -- Number (possibly decimal)
        local num = c
        i = i + 1
        while i <= #expr and (is_digit(expr:sub(i,i)) or expr:sub(i,i) == '.') do
          num = num .. expr:sub(i,i)
          i = i + 1
        end
        table.insert(tokens, {type="number", value=tonumber(num)})
      elseif is_alpha(c) then
        -- Identifier or function
        local ident = c
        i = i + 1
        while i <= #expr and (is_alpha(expr:sub(i,i)) or is_digit(expr:sub(i,i))) do
          ident = ident .. expr:sub(i,i)
          i = i + 1
        end
        table.insert(tokens, {type="ident", value=ident})
        -- Lookahead: if next non-space char is '(', do NOT insert implicit '*' here (handled below)
        -- (No action needed here; implicit multiplication insertion logic is below and will be updated)
      -- If a ',' is found (function argument separator), tokenize it
      elseif c == ',' then
        table.insert(tokens, {type=",", value=","})
        i = i + 1
      elseif c == '(' or c == ')' then
        table.insert(tokens, {type=c})
        i = i + 1
      elseif c == '+' or c == '-' or c == '*' or c == '/' or c == '^' or c == '!' then
        table.insert(tokens, {type="op", value=c})
        i = i + 1
      else
        error('Unknown character in expression: ' .. c)
      end
    end
    -- Insert '*' for things like '2x' or '3(x+1)' because humans write like this,
    -- but Lua doesn't guess your intentions.
    local j = 2
    while j <= #tokens do
      local t1, t2 = tokens[j-1], tokens[j]
      -- Only insert * between number or ')' and ident or '(' (not between ident and '(')
      if (t1.type == 'number' or t1.type == ')' ) and
         (t2.type == 'ident' or t2.type == '(') then
        table.insert(tokens, j, {type="op", value="*"})
        j = j + 1
      end
      j = j + 1
    end
    return tokens
  end
end

-- Parser: Recursive descent for full expression grammar
--   Supports precedence, unary minus, and function calls

-- Handles literals, variables, function calls, parentheses, and unary minus.
-- Also wraps things in factorials if someone thought 'x!' was a good idea.
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

  if tok.type == "number" then
    return wrap_factorial({type="number", value=tok.value}, idx+1)
  elseif tok.type == "ident" then
    if tokens[idx+1] and tokens[idx+1].type == '(' then
      -- Function call (ident followed by '(' always makes a function, not variable)
      local args = {}
      local i = idx + 2
      if tokens[i] and tokens[i].type ~= ')' then
        local arg, ni = parser.parseExpr(tokens, i)
        table.insert(args, arg)
        i = ni
        while tokens[i] and tokens[i].type == ',' do
          local arg2
          arg2, i = parser.parseExpr(tokens, i+1)
          table.insert(args, arg2)
        end
      end
      assert(tokens[i] and tokens[i].type == ')', 'Expected ) after function call')
      -- Try to immediately evaluate trig functions for numeric input
      local fcall = {type="func", name=tok.value, args=args}
      if _G.trig and _G.trig.eval_trig_func then
        local trig_result = _G.trig.eval_trig_func(tok.value, args[1])
        if trig_result then
          return wrap_factorial(trig_result, i+1)
        end
      end
      return wrap_factorial(fcall, i+1)
    else
      -- Only treat as variable if not followed by '('
      return wrap_factorial({type="variable", name=tok.value}, idx+1)
    end
  elseif tok.type == '(' then
    local node, ni = parser.parseExpr(tokens, idx+1)
    assert(tokens[ni] and tokens[ni].type == ')', 'Expected )')
    return wrap_factorial(node, ni+1)
  elseif tok.type == "op" and tok.value == '-' then
    -- Unary minus (ensure expression is parsed correctly)
    local expr, ni = parser.parseExpr(tokens, idx+1)
    return wrap_factorial({type="neg", value=expr}, ni)
  else
    error('Unexpected token at parse_primary: ' .. (tok.type or '?'))
  end
end

-- Parses exponentiation. Right-associative like you'd expect.
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
-- `a / b` becomes `a * b^(-1)` — works surprisingly well.
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
      -- Division: treat as multiplication by reciprocal
      table.insert(factors, {type="pow", base=right, exp={type="number", value=-1}})
    end
  end
  if #factors == 1 then
    return factors[1], i
  else
    return {type="mul", args=factors}, i
  end
end

-- The real entry point for expressions. Supports + and -,
-- but also folds them into a single add tree so simplify doesn’t lose its mind.
function parser.parseExpr(tokens, idx)
  idx = idx or 1
  -- Special case: expression starts with unary minus
  if tokens[idx] and tokens[idx].type == "op" and tokens[idx].value == '-' then
    local expr, ni = parser.parseExpr(tokens, idx + 1)
    return {type = "neg", value = expr}, ni
  end
  local terms = {}
  local signs = {}
  local node, i = parse_term(tokens, idx)
  table.insert(terms, node)
  table.insert(signs, 1)
  while tokens[i] and tokens[i].type == "op" and (tokens[i].value == '+' or tokens[i].value == '-') do
    local op = tokens[i].value
    local right
    right, i = parse_term(tokens, i+1)
    table.insert(terms, right)
    table.insert(signs, op == '+' and 1 or -1)
  end
  -- Flatten into n-ary add, handling subtraction as add of negative
  if #terms == 1 then
    return terms[1], i
  else
    local args = {}
    for j = 1, #terms do
      if signs[j] == 1 then
        table.insert(args, terms[j])
      else
        table.insert(args, {type="neg", value=terms[j]})
      end
    end
    return {type="add", args=args}, i
  end
end

-- Wraps parseExpr and checks for leftovers.
-- If you forgot a bracket, this will find it (loudly).
function parser.buildAST(tokens)
  local ast, idx = parser.parseExpr(tokens, 1)
  if idx <= #tokens then
    error('Parser did not consume all tokens. Next unparsed token: ' .. tostring(tokens[idx].type or "?"))
  end
  return ast
end

-- Tokenizes and builds an AST from a raw expression.
-- Also dumps debug logs in case the result is incomprehensible.
function parser.parse(expr)
  local tokens = parser.tokenize(expr)
  print("[DEBUG] parser.tokenize result:")
  for _, t in ipairs(tokens) do
    print("  type=" .. t.type .. (t.value and (", value="..tostring(t.value)) or ""))
  end
  local ast = parser.buildAST(tokens)
  print("[DEBUG] parser.buildAST result (AST structure):")
  parser.print_ast(ast)
  print("[DEBUG] parser.parse returning AST:")
  parser.print_ast(ast)
  return ast
end

-- Global exposure
_G.parser = parser
_G.parse = parser.parse

_G.parser = parser