-- series.lua

local series = {}

--[[
  Creates an AST node for an exact integer.
  This function is a simple helper to create a consistent AST representation
  for a numeric value.
  @param n (number): The integer value.
  @return (table): The AST node representing the number.
]]
local function exact_integer(n)
  return { type = "number", value = n }
end

--[[
  Creates an AST node for an exact rational number.
  It represents the rational number as a division of two integers.
  @param num (number): The numerator.
  @param denom (number): The denominator.
  @return (table): The AST node for the rational number.
]]
local function exact_rational(num, denom)
  return {
    type = "div",
    left = exact_integer(num),
    right = exact_integer(denom)
  }
end

--[[
  Generates a factorial AST node.
  If the input `n` is a numeric AST node, the factorial is computed numerically.
  Otherwise, it generates a symbolic representation using the Gamma function,
  as Γ(n+1) = n!.
  @param n (table): An AST node representing the number for the factorial.
  @return (table): The AST node for the factorial result.
]]
local function factorial_ast(n)
  if n and n.type == "number" and type(n.value) == "number" then
    -- Resolve factorial numerically if possible, return exact integer node
    local result = 1
    for i = 2, n.value do
      result = result * i
    end
    return exact_integer(result)
  end

  -- Fallback to symbolic gamma if non-numeric
  return {
    type = "func",
    name = "gamma",
    args = {
      {
        type = "add",
        args = { n, exact_integer(1) }
      }
    }
  }
end

--[[
  Creates a power AST node.
  @param base (table): The AST node for the base.
  @param exp (table): The AST node for the exponent.
  @return (table): The AST node representing the power expression.
]]
local function pow(base, exp)
  return { type = "pow", base = base, exp = exp }
end

--[[
  Creates an n-ary multiplication AST node.
  @param args (table): A list of AST nodes to be multiplied.
  @return (table): The AST node representing the multiplication expression.
]]
local function mul(args)
  return { type = "mul", args = args }
end

--[[
  Creates a division AST node.
  @param num (table): The AST node for the numerator.
  @param denom (table): The AST node for the denominator.
  @return (table): The AST node representing the division expression.
]]
local function div(num, denom)
  return { type = "div", left = num, right = denom }
end

--[[
  Creates an n-ary addition AST node.
  @param args (table): A list of AST nodes to be added.
  @return (table): The AST node representing the addition expression.
]]
local function add(args)
  return { type = "add", args = args }
end

--[[
  Expands a supported function into its symbolic Taylor/Maclaurin series.
  The function currently supports `sin`, `cos`, `exp`, and `ln`.
  @param func_name (string): The name of the function to expand.
  @param var_node (table): The AST node for the variable of expansion (e.g., `{type="variable", name="x"}`).
  @param center (number): The point around which to expand the series.
  @param order (number): The maximum order (degree) of the series.
  @return (table): The AST node representing the series expansion.
]]
function series.expand(func_name, var_node, center, order)
  assert(var_node and var_node.type == "variable", "Second arg must be variable node")
  assert(type(center) == "number", "Third arg must be a number")
  assert(type(order) == "number" and order >= 0, "Fourth arg must be non-negative integer")

  local x = var_node
  local terms = {}

  for n = 0, order do
    local coeff, term
    local skip = false

    if func_name == "sin" then
      if n % 2 == 0 then skip = true end
      if not skip then
        local sign = ((n - 1) / 2) % 2 == 0 and 1 or -1
        local sign_node = exact_integer(sign)
        local denom = factorial_ast(exact_integer(n))
        coeff = div(sign_node, denom)
      end
    elseif func_name == "cos" then
      if n % 2 == 1 then skip = true end
      if not skip then
        local sign = (n / 2) % 2 == 0 and 1 or -1
        local sign_node = exact_integer(sign)
        local denom = factorial_ast(exact_integer(n))
        coeff = div(sign_node, denom)
      end
    elseif func_name == "exp" then
      local denom = factorial_ast(exact_integer(n))
      coeff = div(exact_integer(1), denom)
    elseif func_name == "ln" then
      if n == 0 then skip = true end
      if not skip then
        local sign = ((n + 1) % 2 == 0) and 1 or -1
        local sign_node = exact_integer(sign)
        coeff = div(sign_node, exact_integer(n))
      end
    else
      error("Unsupported series: " .. func_name)
    end

    if not skip then
      term = pow({ type = "add", args = { x, exact_integer(-center) } }, exact_integer(n))
      table.insert(terms, 1, mul({ coeff, term }))
    end
  end

  if #terms == 0 then return exact_integer(0) end
  return add(terms)
end

_G.series = series