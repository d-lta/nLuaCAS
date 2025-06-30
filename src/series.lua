-- series.lua: Because infinite sums make us feel clever.

local series = {}

local function factorial_ast(n)
  if n and n.type == "number" and type(n.value) == "number" then
    -- Resolve factorial numerically if possible
    local result = 1
    for i = 2, n.value do
      result = result * i
    end
    return { type = "number", value = result }
  end

  -- Fallback to symbolic gamma if non-numeric
  return {
    type = "func",
    name = "gamma",
    args = {
      {
        type = "add",
        args = { n, { type = "number", value = 1 } }
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
      coeff = div({ type = "number", value = ((-1) ^ ((n - 1) / 2)) }, factorial_ast({ type = "number", value = n }))
    elseif func_name == "cos" then
      if n % 2 == 1 then skip = true end
      coeff = div({ type = "number", value = ((-1) ^ (n / 2)) }, factorial_ast({ type = "number", value = n }))
    elseif func_name == "exp" then
      coeff = div({ type = "number", value = 1 }, factorial_ast({ type = "number", value = n }))
    elseif func_name == "ln" then
      if n == 0 then skip = true end
      coeff = div({ type = "number", value = ((-1) ^ (n + 1)) }, { type = "number", value = n })
    else
      error("Unsupported series: " .. func_name)
    end

    if not skip then
      term = pow({ type = "add", args = { x, { type = "number", value = -center } } }, { type = "number", value = n })
      table.insert(terms, 1, mul({ coeff, term }))
    end
  end

  if #terms == 0 then return { type = "number", value = 0 } end
  return add(terms)
end

_G.series = series
