-- factorial.lua
-- Symbolic factorial using the Gamma function
-- Assumes input is an AST with type = "func" and name = "factorial"
local function factorial(n)
  assert(n >= 0 and math.floor(n) == n, "factorial only defined for non-negative integers")
  local result = 1
  for i = 2, n do result = result * i end
  return result
end

local function matchFactorial(ast)
  if ast.type == "func" and ast.name == "factorial" and ast.args and #ast.args == 1 then
    local arg = ast.args[1]
    -- Convert factorial(n) to gamma(n+1)
    return {
      type = "func",
      name = "gamma",
      args = {
        {
          type = "add",
          args = { arg, { type = "number", value = 1 } }  -- ← Fixed: Use args array
        }
      }
    }
  end
  return ast
end

-- Replace factorials recursively in an AST
function transformFactorial(ast)
  if type(ast) ~= "table" then return ast end
  
  -- Transform factorial(n) → gamma(n+1)
  if ast.type == "func" and ast.name == "factorial" and ast.args and #ast.args == 1 then
    local arg = transformFactorial(ast.args[1])
    return {
      type = "func",
      name = "gamma",
      args = {
        {
          type = "add",
          args = { arg, { type = "number", value = 1 } }  -- ← Fixed: Use args array
        }
      }
    }
  end
  
  local out = {}
  for k, v in pairs(ast) do
    if type(v) == "table" then
      if #v > 0 then
        out[k] = {}
        for i = 1, #v do
          out[k][i] = transformFactorial(v[i])
        end
      else
        out[k] = transformFactorial(v)
      end
    else
      out[k] = v
    end
  end
  return out
end

_G.transformFactorial = transformFactorial
