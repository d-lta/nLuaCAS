-- fraction.lua
-- Fraction & binomial expansion support for symbolic math engine

local ast = rawget(_G, "ast") or require("ast")
local simplify = rawget(_G, "simplify") or require("simplify")

-- Utility: shallow copy
local function copy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local t = {}
  for k,v in pairs(tbl) do t[k]=v end
  return t
end

-- Check if AST is number
local function is_const(ast_node)
  return ast_node and ast_node.type == "number"
end

-- Check if AST is a variable
local function is_var(ast_node)
  return ast_node and ast_node.type == "variable"
end

-- Create factorial node
local function factorial(n)
  return { type = "func", name = "factorial", args = { ast.number(n) } }
end

-- Compute binomial coefficient symbolically: C(n, k) = n! / (k!(n-k)!)
local function binomial(n, k)
  return ast.div(
    factorial(n),
    ast.mul(factorial(k), factorial(n - k))
  )
end

-- Expand (a + b)^n for integer n ≥ 0
local function binomial_expand(base, exp)
  if not is_const(exp) or exp.value < 0 or math.floor(exp.value) ~= exp.value then
    return { type = "binomial_expand_failed", base = base, exp = exp }
  end
  local n = exp.value

  -- Handle (a + b)^n expansion
  if base.type ~= "add" or #base.args ~= 2 then
    return { type = "binomial_expand_failed", reason = "non-binary add" }
  end
  local a, b = base.args[1], base.args[2]

  local terms = {}
  for k = 0, n do
    local coeff = binomial(n, k)
    local term = coeff
    if n - k > 0 then term = ast.mul(term, ast.pow(copy(a), ast.number(n - k))) end
    if k > 0     then term = ast.mul(term, ast.pow(copy(b), ast.number(k))) end
    table.insert(terms, term)
  end

  return ast.add(table.unpack(terms))
end

-- Simplify fractional expressions like (a*b)/b → a
local function simplify_fraction(expr)
  if expr.type ~= "div" then return expr end

  local num, denom = expr.left, expr.right

  -- (a*b)/b → a
  if num.type == "mul" then
    local remaining = {}
    local cancelled = false
    for _, arg in ipairs(num.args) do
      if not cancelled and simplify.equal(arg, denom) then
        cancelled = true -- cancel one instance
      else
        table.insert(remaining, arg)
      end
    end
    if cancelled then
      if #remaining == 1 then
        return remaining[1]
      else
        return ast.mul(table.unpack(remaining))
      end
    end
  end

  return expr
end

-- Symbolic interface: expand binomial expressions like (x+1)^3
local function expand(expr)
  local tree = (rawget(_G, "parser") or require("parser")).parse(expr)
  if not tree then error("Invalid expression: " .. expr) end

  local result = tree

  if tree.type == "pow" then
    result = binomial_expand(tree.base, tree.exp)
  end

  result = simplify.simplify(result)
  return result
end

-- Symbolic interface: simplify fractions (a*b)/b → a
local function fraction_simplify(expr)
  local tree = (rawget(_G, "parser") or require("parser")).parse(expr)
  if not tree then error("Invalid expression: " .. expr) end

  local result = simplify_fraction(tree)
  result = simplify.simplify(result)
  return result
end

-- Public API
_G.fraction_expand = expand
_G.fraction_simplify = fraction_simplify
_G.binomial_expand = binomial_expand
_G.simplify_fraction = simplify_fraction