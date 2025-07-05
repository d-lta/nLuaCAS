platform.apilevel = "2.4"
table.unpack = table.unpack or unpack

local exact = {}
exact.__index = exact

-- Greatest Common Divisor
function exact.gcd(a, b)
    while b ~= 0 do a, b = b, a % b end
    return math.abs(a)
end

-- Check integer
function exact.isInteger(n)
    return type(n) == "number" and math.floor(n) == n
end

-- Detect if value is exact type
function exact.isExact(x)
    return type(x) == "table" and getmetatable(x) == exact
end

-- Less than
function exact.lt(a, b)
    a, b = exact.toExact(a), exact.toExact(b)
    if a.type == "integer" and b.type == "integer" then return a.value < b.value end
    if a.type == "rational" or b.type == "rational" then
        local an = (a.type == "rational") and a.num or a.value * b.den
        local ad = (a.type == "rational") and a.den or b.den
        local bn = (b.type == "rational") and b.num or b.value * a.den
        local bd = (b.type == "rational") and b.den or a.den
        return an * bd < bn * ad
    end
    error("Comparison not implemented")
end

-- Less than or equal
function exact.leq(a, b)
    return exact.lt(a, b) or exact.eq(a, b)
end

-- Greater than or equal
function exact.geq(a, b)
    return not exact.lt(b, a)
end

-- Negation
function exact.neg(x)
    x = exact.toExact(x)
    if x.type == "integer" then return exact.newInteger(-exact.tonumber(x.value)) end
    if x.type == "rational" then return exact.newRational(-x.num, x.den) end
    error("Negation not implemented")
end

-- Square root (only rational roots for now)
function exact.sqrt(x)
    x = exact.toExact(x)
    if x.type == "integer" then
        local n = exact.tonumber(x.value)
        if type(n) ~= "number" then error("sqrt: not a number") end
        local root = math.sqrt(n)
        if exact.isInteger(root) then return exact.newInteger(root) end
    end
    error("Sqrt not implemented for type")
end

-- Power
function exact.pow(a, b)
    a, b = exact.toExact(a), exact.toExact(b)
    local bval = exact.tonumber(b.value)
    if b.type == "integer" and exact.isInteger(bval) then
        local result = 1
        local base = exact.tonumber(a.value)
        for _ = 1, math.abs(bval) do
            result = result * base
        end
        if bval < 0 then return exact.newRational(1, result) end
        return exact.newInteger(result)
    end
    error("Power not implemented")
end

-- Wraps Lua primitive to exact
function exact.new(x)
    return exact.toExact(x)
end

-- Extracts Lua number
function exact.tonumber(x)
    if type(x) == "number" then return x end
    if type(x) == "table" then
        if x.type == "integer" then return x.value end
        if x.type == "rational" then return x.num / x.den end
        if x.type == "float" then return x.value end
    end
    return nil  -- For non-number types, return nil (not a table)
end

-- Convert to exact type
function exact.toExact(x)
    -- If x is an AST node wrapping a value, unwrap recursively
    if type(x) == "table" and x.type == "number" and x.value ~= nil then
        return exact.toExact(x.value)
    end

    if exact.isExact(x) then return x end
    if exact.isInteger(x) then return exact.newInteger(x) end
    return exact.newFloat(x)
end

-- Normalize operands
function exact.normalize(a, b)
    return exact.toExact(a), exact.toExact(b)
end

-- Integer constructor
function exact.newInteger(n)
    assert(exact.isInteger(n), "Not an integer")
    return setmetatable({type="integer", value=n}, exact)
end

-- Rational constructor
function exact.newRational(num, den)
    assert(den ~= 0, "Denominator cannot be zero")
    local g = exact.gcd(num, den)
    local sign = den < 0 and -1 or 1
    return setmetatable({type="rational", num=num/g * sign, den=math.abs(den)/g}, exact)
end

-- Float wrapper (minimal use)
function exact.newFloat(n)
    return setmetatable({type="float", value=n}, exact)
end

-- String conversion
function exact:__tostring()
    if self.type == "integer" then return tostring(self.value) end
    if self.type == "rational" then return self.num .. "/" .. self.den end
    if self.type == "float" then return tostring(self.value) end
    return "<exact?>"
end

function exact.__add(a, b)
    a, b = exact.normalize(a, b)
    local allowed = {integer=true, rational=true, float=true}
    if not (allowed[a.type] and allowed[b.type]) then
        return {type="add", args={a, b}}
    end
    if a.type == "integer" and b.type == "integer" then
        return exact.newInteger(a.value + b.value)
    elseif a.type == "rational" and b.type == "rational" then
        return exact.newRational(a.num * b.den + b.num * a.den, a.den * b.den)
    elseif a.type == "integer" and b.type == "rational" then
        return exact.newRational(a.value * b.den + b.num, b.den)
    elseif a.type == "rational" and b.type == "integer" then
        return exact.newRational(a.num + b.value * a.den, a.den)
    elseif a.type == "float" and b.type == "float" then
        return exact.newFloat(a.value + b.value)
    elseif a.type == "float" and (b.type == "integer" or b.type == "rational") then
        local na, nb = exact.tonumber(a), exact.tonumber(b)
        if type(na) ~= "number" or type(nb) ~= "number" then
            return {type="add", args={a, b}}
        end
        return exact.newFloat(na + nb)
    elseif b.type == "float" and (a.type == "integer" or a.type == "rational") then
        local na, nb = exact.tonumber(a), exact.tonumber(b)
        if type(na) ~= "number" or type(nb) ~= "number" then
            return {type="add", args={a, b}}
        end
        return exact.newFloat(na + nb)
    end
    return {type="add", args={a, b}}
end

-- Subtraction
function exact.__sub(a, b)
    return exact.__add(a, exact.neg(b))
end

function exact.__mul(a, b)
    a, b = exact.normalize(a, b)
    local allowed = {integer=true, rational=true, float=true}
    if not (allowed[a.type] and allowed[b.type]) then
        return {type="mul", args={a, b}}
    end
    if a.type == "integer" and b.type == "integer" then
        return exact.newInteger(a.value * b.value)
    elseif a.type == "rational" and b.type == "rational" then
        return exact.newRational(a.num * b.num, a.den * b.den)
    elseif a.type == "integer" and b.type == "rational" then
        return exact.newRational(a.value * b.num, b.den)
    elseif a.type == "rational" and b.type == "integer" then
        return exact.newRational(a.num * b.value, a.den)
    elseif a.type == "float" and b.type == "float" then
        return exact.newFloat(a.value * b.value)
    elseif a.type == "float" and (b.type == "integer" or b.type == "rational") then
        local na, nb = exact.tonumber(a), exact.tonumber(b)
        if type(na) ~= "number" or type(nb) ~= "number" then
            return {type="mul", args={a, b}}
        end
        return exact.newFloat(na * nb)
    elseif b.type == "float" and (a.type == "integer" or a.type == "rational") then
        local na, nb = exact.tonumber(a), exact.tonumber(b)
        if type(na) ~= "number" or type(nb) ~= "number" then
            return {type="mul", args={a, b}}
        end
        return exact.newFloat(na * nb)
    end
    return {type="mul", args={a, b}}
end

function exact.__div(a, b)
    a, b = exact.normalize(a, b)
    local allowed = {integer=true, rational=true, float=true}
    if not (allowed[a.type] and allowed[b.type]) then
        return {type="div", args={a, b}}
    end
    if (b.type == "integer" and b.value == 0) or (b.type == "rational" and b.num == 0) or (b.type == "float" and b.value == 0) then
        error("Div by zero")
    end
    if a.type == "integer" and b.type == "integer" then
        return exact.newRational(a.value, b.value)
    elseif a.type == "rational" and b.type == "rational" then
        return exact.newRational(a.num * b.den, a.den * b.num)
    elseif a.type == "integer" and b.type == "rational" then
        return exact.newRational(a.value * b.den, b.num)
    elseif a.type == "rational" and b.type == "integer" then
        return exact.newRational(a.num, a.den * b.value)
    elseif a.type == "float" and b.type == "float" then
        return exact.newFloat(a.value / b.value)
    elseif a.type == "float" and (b.type == "integer" or b.type == "rational") then
        local na, nb = exact.tonumber(a), exact.tonumber(b)
        if type(na) ~= "number" or type(nb) ~= "number" then
            return {type="div", args={a, b}}
        end
        return exact.newFloat(na / nb)
    elseif b.type == "float" and (a.type == "integer" or a.type == "rational") then
        local na, nb = exact.tonumber(a), exact.tonumber(b)
        if type(na) ~= "number" or type(nb) ~= "number" then
            return {type="div", args={a, b}}
        end
        return exact.newFloat(na / nb)
    end
    return {type="div", args={a, b}}
end

function exact.__eq(a, b)
    a, b = exact.normalize(a, b)
    -- Only compare if both are numbers handled by exact (integer, rational, float)
    if not ((a.type == "integer" or a.type == "rational" or a.type == "float") and
            (b.type == "integer" or b.type == "rational" or b.type == "float")) then
        return false
    end
    if a.type == "integer" and b.type == "integer" then
        return a.value == b.value
    elseif a.type == "rational" and b.type == "rational" then
        return a.num * b.den == b.num * a.den
    elseif a.type == "integer" and b.type == "rational" then
        return a.value * b.den == b.num
    elseif a.type == "rational" and b.type == "integer" then
        return a.num == b.value * a.den
    elseif a.type == "float" and b.type == "float" then
        return a.value == b.value
    elseif (a.type == "float" and (b.type == "integer" or b.type == "rational")) or
           (b.type == "float" and (a.type == "integer" or a.type == "rational")) then
        return exact.tonumber(a) == exact.tonumber(b)
    end
    return false
end

-- AST Conversion
function exact.fromAST(node)
    if node.type ~= "number" then return nil end
    return exact.toExact(node.value)
end

function exact.toAST(exact_num)
    if exact_num.type == "integer" then return {type="number", value=exact_num.value} end
    if exact_num.type == "rational" then
        return {type="div", left={type="number", value=exact_num.num}, right={type="number", value=exact_num.den}}
    end
    error("Cannot convert to AST")
end

-- Legacy API Wrappers
function exact.from(x) return exact.toExact(x) end
function exact.add(a, b) return a + b end
function exact.sub(a, b) return a - b end
function exact.mul(a, b) return a * b end
function exact.div(a, b) return a / b end
function exact.eq(a, b) return a == b end
function exact.is_number(x) return exact.isExact(x) end

-- Register globally
print("[exact] Full patched exact module loaded")
_G.exact = exact