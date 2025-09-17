-- fraction.lua
-- Implements fraction simplification and binomial expansion for symbolic expressions.

local ast = rawget(_G, "ast") or require("ast")
local simplify = rawget(_G, "simplify") or require("simplify")

--[[
  A utility function for performing a shallow copy of a table.
  @param tbl (table): The table to copy.
  @return (table): A shallow copy of the input table.
]]
local function copy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local t = {}
  for k,v in pairs(tbl) do t[k]=v end
  return t
end

--[[
  Checks if an AST node is a number.
  @param ast_node (table): The AST node to check.
  @return (boolean): True if the node is a number, false otherwise.
]]
local function is_const(ast_node)
  return ast_node and ast_node.type == "number"
end

--[[
  Checks if an AST node is a variable.
  @param ast_node (table): The AST node to check.
  @return (boolean): True if the node is a variable, false otherwise.
]]
local function is_var(ast_node)
  return ast_node and ast_node.type == "variable"
end

-- Creates a factorial AST node.
-- Example: factorial(5) creates a node for '5!'.
local function factorial(n)
  return { type = "func", name = "factorial", args = { ast.number(n) } }
end

--[[
  Computes a symbolic binomial coefficient C(n, k) = n! / (k!(n-k)!).
  @param n (number): The 'n' in C(n, k).
  @param k (number): The 'k' in C(n, k).
  @return (table): A symbolic AST for the binomial coefficient.
]]
local function binomial(n, k)
  return ast.div(
    factorial(n),
    ast.mul(factorial(k), factorial(n - k))
  )
end

--[[
  Expands a binomial expression of the form (a + b)^n for integer n >= 0.
  @param base (table): The AST for the base (e.g., an 'add' node for a+b).
  @param exp (table): The AST for the exponent (must be a number node).
  @return (table): The expanded AST, or an error node if expansion fails.
]]
local function binomial_expand(base, exp)
  if not is_const(exp) or exp.value < 0 or math.floor(exp.value) ~= exp.value then
    return { type = "error", reason = "The exponent must be a non-negative integer." }
  end
  local n = exp.value

  -- The base must be a sum of exactly two terms.
  if base.type ~= "add" or #base.args ~= 2 then
    return { type = "error", reason = "The base must be a sum of two terms (e.g., (a + b))." }
  end
  local a, b = base.args[1], base.args[2]

  local terms = {}
  for k = 0, n do
    local coeff = binomial(n, k)
    local term = coeff
    
    -- Add the 'a' term, if its exponent is greater than 0.
    if n - k > 0 then term = ast.mul(term, ast.pow(copy(a), ast.number(n - k))) end
    
    -- Add the 'b' term, if its exponent is greater than 0.
    if k > 0 then term = ast.mul(term, ast.pow(copy(b), ast.number(k))) end
    
    table.insert(terms, term)
  end

  return ast.add(table.unpack(terms))
end

--[[
  Simplifies fractional expressions by canceling common factors.
  Example: (a * b) / b simplifies to a.
  @param expr (table): The AST for the expression.
  @return (table): The simplified AST.
]]
local function simplify_fraction(expr)
  if expr.type ~= "div" then return expr end

  local num, denom = expr.left, expr.right

  -- Check if the numerator is a product with a factor equal to the denominator.
  if num.type == "mul" then
    local remaining = {}
    local cancelled = false
    for _, arg in ipairs(num.args) do
      if not cancelled and simplify.equal(arg, denom) then
        cancelled = true -- Cancel a single instance of the factor.
      else
        table.insert(remaining, arg)
      end
    end
    if cancelled then
      -- If only one term remains, return it directly. Otherwise, return a product.
      if #remaining == 1 then
        return remaining[1]
      else
        return ast.mul(table.unpack(remaining))
      end
    end
  end

  return expr
end

--[[
  Symbolic interface for expanding binomial expressions.
  Parses a string, expands it, and simplifies the result.
  @param expr (string): The expression string to expand (e.g., "(x+1)^3").
  @return (table): The simplified AST of the expanded expression.
]]
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

--[[
  Symbolic interface for simplifying fractions.
  Parses a string, simplifies the fraction, and simplifies the result.
  @param expr (string): The expression string to simplify (e.g., "(a*b)/b").
  @return (table): The simplified AST of the fraction.
]]
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