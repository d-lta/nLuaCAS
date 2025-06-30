-- factorial.lua
-- Converts symbolic factorial calls to Gamma-based equivalents
-- Works even when you feed it algebra instead of numbers, which is both useful and terrifying

-- Numerical fallback (not actually used in AST transforms)
-- Just here for completeness, or when someone evaluates factorial(5) directly
-- Lanczos approximation for Gamma function, accurate for most real numbers
local lanczos_coef = {
  676.5203681218851, -1259.1392167224028, 771.32342877765313,
  -176.61502916214059, 12.507343278686905, -0.13857109526572012,
  9.9843695780195716e-6, 1.5056327351493116e-7
}

local function gamma(z)
  if z < 0.5 then
    -- Reflection formula for negative arguments
    return math.pi / (math.sin(math.pi * z) * gamma(1 - z))
  else
    z = z - 1
    local x = 0.99999999999980993
    for i = 1, #lanczos_coef do
      x = x + lanczos_coef[i] / (z + i)
    end
    local t = z + #lanczos_coef - 0.5
    return math.sqrt(2 * math.pi) * t^(z + 0.5) * math.exp(-t) * x
  end
end

-- General factorial using Gamma, valid for real/complex domain
local function factorial(n)
  return gamma(n + 1)
end

-- Matches factorial(x) and returns gamma(x + 1)
-- Strictly cosmetic — lets us pretend we know how to differentiate factorials
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

-- Walks the AST and replaces every factorial(...) with gamma(... + 1)
-- Recursively rewrites child nodes as well, whether they like it or not
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

-- Evaluate the Gamma function numerically using the Lanczos approximation
local function evaluateGamma(z)
  return gamma(z)
end

-- Evaluate the factorial numerically using the Gamma function
local function evaluateFactorial(n)
  return factorial(n)
end

_G.transformFactorial = transformFactorial
_G.evaluateGamma = evaluateGamma  -- Expose evaluateGamma globally
_G.evaluateFactorial = evaluateFactorial  -- Expose evaluateFactorial globally
