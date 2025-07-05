-- series.lua: Because infinite sums make us feel clever.

local series = {}

local function exact_integer(n)
  return { type = "number", value = n }
end

local function exact_rational(num, denom)
  return {
    type = "div",
    left = exact_integer(num),
    right = exact_integer(denom)
  }
end

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

local function pow(base, exp)
  return { type = "pow", base = base, exp = exp }
end

local function mul(args)
  return { type = "mul", args = args }
end

local function div(num, denom)
  return { type = "div", left = num, right = denom }
end

local function add(args)
  return { type = "add", args = args }
end

-- Symbolic Taylor/Maclaurin Series
-- func_name: string like "sin", "cos", "exp", "ln"
-- var_node: {type="variable", name="x"}
-- center: number for expansion point
-- order: integer max order
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
