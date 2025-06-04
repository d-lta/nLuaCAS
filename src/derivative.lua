-- Derivative Engine (WIP)
-- Tries to symbolically differentiate expressions.
-- Some parts work. Some parts pretend to work.
-- Expect broken edge cases, unimplemented branches, and fallback logic.

local ast = rawget(_G, "ast") or require("ast")
local trig = rawget(_G, "trig")

-- Utility: shallow copy of a table
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

-- Utility: check if AST is a specific symbol
local function is_symbol(ast, name)
  return ast.type == "variable" and ast.name == name
end

-- Utility: limit AST node
local function lim(expr, var, to)
  return { type = 'lim', expr = expr, var = var, to = to }
end

-- Symbolic differentiation core. Tries to pretend it understands your math.
-- Falls back to limit definitions when it gives up.
local function diffAST(ast_node, var)
  if not ast_node then
    error("diffAST: invalid AST node passed in")
  end
  if type(ast_node) ~= "table" then
    error("diffAST: encountered non-AST node of type " .. type(ast_node))
  end
  var = var or "x"
  -- Numbers don't change. That's kind of the point.
  if ast_node.type == "number" then
    -- x → 1, everything else → 0. Classic.
    return ast.number(0)
  end
  -- x → 1, everything else → 0. Classic.
  if ast_node.type == "variable" then
    if ast_node.name == var then
      return ast.number(1)
    else
      return ast.number(0)
    end
  end
  -- Negation: signs flip, but rules stay the same.
  if ast_node.type == "neg" then
    return ast.neg(diffAST(ast_node.value, var))
  end
  -- Addition: term-wise differentiation. Nothing surprising.
  if ast_node.type == "add" then
    local deriv_args = {}
    for i, term in ipairs(ast_node.args) do
      deriv_args[i] = diffAST(term, var)
    end
    return ast.add(table.unpack(deriv_args))
  end
  -- Subtraction: just addition's grumpy cousin.
  if ast_node.type == "sub" then
    return ast.sub(diffAST(ast_node.left, var), diffAST(ast_node.right, var))
  end
  -- Multiplication: full product rule. Brace yourself.
  if ast_node.type == "mul" then
    local n = #ast_node.args
    local terms = {}
    for k = 1, n do
      local prod_args = {}
      for i = 1, n do
        if i == k then
          prod_args[i] = diffAST(ast_node.args[i], var)
        else
          prod_args[i] = copy(ast_node.args[i])
        end
      end
      terms[k] = ast.mul(table.unpack(prod_args))
    end
    return ast.add(table.unpack(terms))
  end
  -- Quotient rule. Surprisingly tidy, even here.
  if ast_node.type == "div" then
    local u = ast_node.left
    local v = ast_node.right
    local du = diffAST(u, var)
    local dv = diffAST(v, var)

    local numerator = ast.sub(
      ast.mul(du, copy(v)),
      ast.mul(copy(u), dv)
    )

    local denominator = ast.pow(copy(v), ast.number(2))

    return ast.div(numerator, denominator)
  end
  -- Powers: handles constants, variables, and full u^v chains.
  -- Tries to be clever with logs if needed.
  if ast_node.type == "pow" then
    local u, n = ast_node.base, ast_node.exp
    -- Case: u^c, c constant
    if is_const(n) then
      -- d/dx(u^c) = c*u^(c-1) * du/dx
      return ast.mul(
        ast.mul(copy(n), ast.pow(copy(u), ast.number(n.value - 1))),
        diffAST(u, var)
      )
    -- Case: c^v, c constant
    elseif is_const(u) then
      -- d/dx(c^v) = ln(c) * c^v * dv/dx
      return ast.mul(
        ast.mul(ast.func("ln", { copy(u) }), ast.pow(copy(u), copy(n))),
        diffAST(n, var)
      )
    else
      -- General case: d/dx(u^v) = u^v * (v' * ln(u) + v * u'/u)
      -- (by logarithmic differentiation)
      return ast.mul(
        ast.pow(copy(u), copy(n)),
        ast.add(
          ast.mul(diffAST(n, var), ast.func("ln", { copy(u) })),
          ast.mul(copy(n), ast.div(diffAST(u, var), copy(u)))
        )
      )
    end
  end
  -- Function differentiation: sin, exp, ln, etc.
  -- Tries trig.lua first. Falls back to hardcoded rules.
  -- Anything unknown? It gets the limit treatment.
  if ast_node.type == "func" then
    local fname = ast_node.name
    -- Support both .arg (single) and .args (list) notation
    local u = ast_node.arg or (ast_node.args and ast_node.args[1])
    local du = diffAST(u, var)
    -- Use trig.lua for trigonometric differentiation if available
    if trig and trig.diff_trig_func then
      local trig_result = trig.diff_trig_func(fname, copy(u), du)
      if trig_result then return trig_result end
    end
    if fname == "exp" then
      return ast.mul(ast.func("exp", { copy(u) }), du)
    elseif fname == "ln" then
      return ast.mul(ast.div(ast.number(1), copy(u)), du)
    elseif fname == "log" then
      -- log(x) = ln(x) / ln(10), so derivative is 1/(x ln(10))
      return ast.mul(ast.div(ast.number(1), ast.mul(copy(u), ast.func("ln", { ast.number(10) }))), du)
    elseif fname == "sqrt" then
      -- d/dx sqrt(u) = 1/(2*sqrt(u)) * du/dx
      return ast.mul(ast.div(ast.number(1), ast.mul(ast.number(2), ast.func("sqrt", { copy(u) }))), du)
    elseif fname == "asin" then
      -- d/dx asin(u) = 1/sqrt(1-u^2) * du/dx
      return ast.mul(ast.div(ast.number(1), ast.func("sqrt", { ast.sub(ast.number(1), ast.pow(copy(u), ast.number(2))) })), du)
    elseif fname == "acos" then
      -- d/dx acos(u) = -1/sqrt(1-u^2) * du/dx
      return ast.mul(ast.neg(ast.div(ast.number(1), ast.func("sqrt", { ast.sub(ast.number(1), ast.pow(copy(u), ast.number(2))) }))), du)
    elseif fname == "atan" then
      -- d/dx atan(u) = 1/(1+u^2) * du/dx
      return ast.mul(ast.div(ast.number(1), ast.add(ast.number(1), ast.pow(copy(u), ast.number(2)))), du)
    elseif fname == "sinh" then
      return ast.mul(ast.func("cosh", { copy(u) }), du)
    elseif fname == "cosh" then
      return ast.mul(ast.func("sinh", { copy(u) }), du)
    elseif fname == "tanh" then
      return ast.mul(ast.sub(ast.number(1), ast.pow(ast.func("tanh", { copy(u) }), ast.number(2))), du)
    elseif fname == "asinh" then
      return ast.mul(ast.div(ast.number(1), ast.func("sqrt", { ast.add(ast.pow(copy(u), ast.number(2)), ast.number(1)) })), du)
    elseif fname == "acosh" then
      return ast.mul(ast.div(ast.number(1), ast.func("sqrt", { ast.sub(ast.pow(copy(u), ast.number(2)), ast.number(1)) })), du)
    elseif fname == "atanh" then
      return ast.mul(ast.div(ast.number(1), ast.sub(ast.number(1), ast.pow(copy(u), ast.number(2)))), du)
    elseif fname == "log10" then
      return ast.mul(ast.div(ast.number(1), ast.mul(copy(u), ast.func("ln", { ast.number(10) }))), du)
    elseif fname == "log2" then
      return ast.mul(ast.div(ast.number(1), ast.mul(copy(u), ast.func("ln", { ast.number(2) }))), du)
    elseif fname == "abs" then
      return ast.mul(ast.div(copy(u), ast.func("abs", { copy(u) })), du)
    elseif fname == "sign" then
      return ast.number(0)
    elseif fname == "floor" or fname == "ceil" or fname == "round" then
      -- Derivative is zero except at discontinuity
      return ast.number(0)
    elseif fname == "erf" then
      -- d/dx erf(u) = 2/sqrt(pi) * exp(-u^2) * du/dx
      return ast.mul(ast.mul(ast.div(ast.number(2), ast.func("sqrt", { ast.number(math.pi) })), ast.func("exp", { ast.neg(ast.pow(copy(u), ast.number(2))) })), du)
    elseif fname == "gamma" then
      -- d/dx gamma(u) = gamma(u) * digamma(u) * du/dx (digamma not implemented, fallback)
      return { type = "unimplemented_derivative", func = fname, arg = copy(u) }
    elseif fname == "digamma" then
      -- d/dx digamma(u) = trigamma(u) * du/dx
      return ast.mul(ast.func("trigamma", { copy(u) }), du)
    elseif fname == "trigamma" then
      -- d/dx trigamma(u) = polygamma(2, u) * du/dx
      return ast.mul(ast.func("polygamma", { ast.number(2), copy(u) }), du)
    else
      -- Fallback: Use limit definition for unknown function
      -- f'(x) = lim_{h->0} [f(x+h)-f(x)]/h
      local h = ast.symbol("__h__")
      local u_ph = ast.add(copy(u), h)
      local fxh = ast.func(fname, { u_ph })
      local fx = ast.func(fname, { copy(u) })
      local nume = ast.sub(fxh, fx)
      local quot = ast.div(nume, h)
      return lim(quot, "__h__", ast.number(0))
    end
  end
  -- No clue what this is. Marked for manual inspection later.
  -- As a safety fallback, return an unknown node
  local result = { type = "unhandled_node", original = ast_node }
  if type(result) ~= "table" or not result.type then
    error("diffAST: returned invalid AST node structure")
  end
  return result
end


-- Public interface: takes string input, returns simplified derivative AST.
-- If it doesn't break, it probably worked.
local function derivative(expr, var)
  -- Load parser
  local parser = rawget(_G, "parser") or require("parser")
  -- Input validation and debug print
  if type(expr) ~= "string" then
    error("Invalid input to derivative(): expected string, got " .. type(expr))
  end
  print("DEBUG: input to parser.parse =", expr)
  -- Parse expr string to AST
  local tree = parser.parse(expr)
  if not tree then
    error("Parsing failed: input = " .. expr)
  end
  local result = diffAST(tree, var)
  if type(result) ~= "table" or not result.type then
    error("Invalid derivative AST structure")
  end
  return (rawget(_G, "simplify") or require("simplify")).simplify(result)
end
_G.derivative = derivative
_G.diffAST = diffAST