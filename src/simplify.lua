--[[
  Symbolic Expression Simplification Engine (CAS)
  Standalone Lua module: no dependencies, all helpers and rules included.
  Entrypoint: simplify.simplify(expr_ast)
  AST node types: assumes standard 'number', 'variable', 'add', 'mul', 'pow', 'neg', 'func', etc.
  Extensible: just add rules to the rule table or helper functions.
  See comments for structure and extension points.
--]]


local simplify = {}

local DEBUG = true
local function dbgprint(...)
  if DEBUG then print("[DEBUG]", ...) end
end

-- Rules table must be declared before any table.insert(rules, ...)
local rules = {}

local function deepcopy(expr)
  if type(expr) ~= "table" then return expr end
  local t = {}
  for k,v in pairs(expr) do t[k] = deepcopy(v) end
  return t
end

local function is_num(e) return e and e.type == "number" end
local function is_var(e) return e and e.type == "variable" end
local function is_add(e) return e and e.type == "add" end
local function is_mul(e) return e and e.type == "mul" end
local function is_pow(e) return e and e.type == "pow" end
local function is_neg(e) return e and e.type == "neg" end
local function is_func(e) return e and e.type == "func" end

local function numval(e) return e.value end

local function ast_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  if a.type ~= b.type then return false end
  -- Compare keys present in both
  for k,v in pairs(a) do
    if not ast_eq(v, b[k]) then return false end
  end
  for k,v in pairs(b) do
    if not ast_eq(v, a[k]) then return false end
  end
  return true
end

local function flatten(node)
  if node.type ~= "add" and node.type ~= "mul" then return node end
  local args = {}
  local function gather(n)
    if n.type == node.type and n.args then
      for _,a in ipairs(n.args) do gather(a) end
    else
      table.insert(args, n)
    end
  end
  gather(node)
  return {type=node.type, args=args}
end

local function serialize_for_sort(node)
  if is_num(node) then return "N:" .. tostring(node.value)
  elseif is_var(node) then return "V:" .. node.name
  elseif is_add(node) then
    local parts = {}
    for _, arg in ipairs(node.args) do table.insert(parts, serialize_for_sort(arg)) end
    table.sort(parts)
    return "A:" .. table.concat(parts, ",")
  elseif is_mul(node) then
    local parts = {}
    for _, arg in ipairs(node.args) do table.insert(parts, serialize_for_sort(arg)) end
    table.sort(parts)
    return "M:" .. table.concat(parts, ",")
  elseif is_pow(node) then
    return "P:" .. serialize_for_sort(node.base) .. "^" .. serialize_for_sort(node.exp)
  elseif is_neg(node) then
    return "Neg:" .. serialize_for_sort(node.arg)
  elseif is_func(node) then
    local parts = {}
    for _, arg in ipairs(node.args) do table.insert(parts, serialize_for_sort(arg)) end
    return "F:" .. node.name .. "(" .. table.concat(parts, ",") .. ")"
  else
    return "U:" .. tostring(node)
  end
end

local function sort_args(node)
  if node.type ~= "add" and node.type ~= "mul" then return node end
  local args = {}
  for _,a in ipairs(node.args) do table.insert(args, a) end
  table.sort(args, function(a,b)
    local sa = serialize_for_sort(a)
    local sb = serialize_for_sort(b)
    return sa < sb
  end)
  return {type=node.type, args=args}
end

-- Forward declaration for recursive_simplify to allow its use in canonicalize
local recursive_simplify

local function canonicalize(expr)
  if type(expr) ~= "table" then return expr end
  local e = deepcopy(expr)
  if e.type == "add" or e.type == "mul" then
    local new_args = {}
    for i, a in ipairs(e.args) do new_args[i] = recursive_simplify(a) end
    e.args = new_args
    e = flatten(e)
    e = sort_args(e)
    return e
  elseif e.type == "pow" then
    e.base = canonicalize(e.base)
    e.exp = canonicalize(e.exp)
    return e
  elseif e.type == "neg" then
    e.arg = canonicalize(e.arg)
    return e
  elseif e.type == "func" then
    local new_args = {}
    for i,a in ipairs(e.args) do new_args[i] = canonicalize(a) end
    e.args = new_args
    return e
  end
  return e
end

local function occurs(var, expr)
  if is_var(expr) and expr.name == var then return true end
  if type(expr) ~= "table" then return false end
  for k,v in pairs(expr) do
    if occurs(var, v) then return true end
  end
  return false
end

local function copy_node(node, fields)
  local t = {type=node.type}
  for k,v in pairs(fields or {}) do t[k] = v end
  return t
end

local function map_args(node, f)
  if not node.args then return node end
  local new_args = {}
  for i,a in ipairs(node.args) do new_args[i] = f(a) end
  return {type=node.type, args=new_args}
end

-- Node builders
local function num(n) return {type="number", value=n} end
local function var(x) return {type="variable", name=x} end
local function add(args) return {type="add", args=args} end
local function mul(args) return {type="mul", args=args} end
local function pow(base, exp) return {type="pow", base=base, exp=exp} end
local function neg(arg) return {type="neg", arg=arg} end
local function func(name, args) return {type="func", name=name, args=args} end

-- Helper Predicates
local function is_integer(n) return math.floor(n) == n end
local function is_zero(e) return is_num(e) and numval(e) == 0 end
local function is_one(e) return is_num(e) and numval(e) == 1 end
local function is_minus_one(e) return is_num(e) and numval(e) == -1 end
-- Helpers from the second snippet
local function is_positive(e) return is_num(e) and numval(e) > 0 end
local function is_negative(e) return is_num(e) and numval(e) < 0 end
local function is_even(e) return is_num(e) and is_integer(numval(e)) and numval(e) % 2 == 0 end
local function is_odd(e) return is_num(e) and is_integer(numval(e)) and numval(e) % 2 == 1 end


--[[
  Rule Engine: Each rule is a function: rule(expr) -> new_expr or nil
  The rules are applied recursively and iteratively until stable.
  To add new rules, insert into the rules table.
--]]


-- Constants: for quick lookup
local ZERO = num(0)
local ONE = num(1)
local MINUS_ONE = num(-1)
-- Constants from the second snippet
local TWO = num(2)
local PI = num(math.pi)
local E = num(math.e)


-- 1. BASIC ARITHMETIC SIMPLIFICATION
table.insert(rules, function(expr)
  if is_add(expr) then
    -- Fold numeric terms in addition
    local sum = 0
    local others = {}
    for _,a in ipairs(expr.args) do
      if is_num(a) then sum = sum + numval(a) else table.insert(others, a) end
    end
    if sum ~= 0 or #others == 0 then table.insert(others, 1, num(sum)) end
    -- Remove leading zero if there are other terms
    if #others > 1 and is_zero(others[1]) then table.remove(others, 1) end
    if #others == 1 then return others[1] end
    if #others ~= #expr.args or (is_num(expr.args[1]) and numval(expr.args[1]) ~= sum) then
      return add(others)
    end
  elseif is_mul(expr) then
    -- Fold numeric terms in multiplication
    local prod = 1
    local others = {}
    for _,a in ipairs(expr.args) do
      if is_num(a) then prod = prod * numval(a) else table.insert(others, a) end
    end
    if prod == 0 then return ZERO end
    if prod ~= 1 or #others == 0 then table.insert(others, 1, num(prod)) end
    -- Remove all ones if there are other terms
    for i = #others, 1, -1 do
      if is_one(others[i]) then table.remove(others, i) end
    end
    if #others == 0 then return ONE end
    if #others == 1 then return others[1] end
    if #others ~= #expr.args or (is_num(expr.args[1]) and numval(expr.args[1]) ~= prod) then
      return mul(others)
    end
  elseif is_pow(expr) then
    -- Enhanced pow simplification block
    if is_pow(expr) then
      if is_one(expr.exp) then return expr.base end
      if is_zero(expr.exp) then return ONE end
      if is_zero(expr.base) then return ZERO end
      if is_one(expr.base) then return ONE end
      if is_num(expr.base) and is_num(expr.exp) then
        local b, e = numval(expr.base), numval(expr.exp)
        if b > 0 or (b < 0 and is_integer(e)) then
          return num(b ^ e)
        end
      end
    end
  end
end)

-- Simplify x^1 => x
table.insert(rules, function(expr)
  if is_pow(expr) and is_one(expr.exp) then
    return expr.base
  end
end)

-- Flatten nested adds/muls (associativity)
table.insert(rules, function(expr)
  if is_add(expr) or is_mul(expr) then
    local flat = flatten(expr)
    if #flat.args ~= #expr.args then return flat end
  end
end)

-- Sort args (commutativity)
table.insert(rules, function(expr)
  if is_add(expr) or is_mul(expr) then
    local sorted = sort_args(expr)
    -- Compare by structure
    for i=1,#expr.args do
      if not ast_eq(expr.args[i], sorted.args[i]) then return sorted end
    end
  end
end)

table.insert(rules, function(expr)
  if is_add(expr) then
    local out = {}
    for _,a in ipairs(expr.args) do if not is_zero(a) then table.insert(out,a) end end
    if #out == 0 then return ZERO end
    if #out == 1 then return out[1] end
    if #out < #expr.args then return add(out) end
  elseif is_mul(expr) then
    local out = {}
    for _,a in ipairs(expr.args) do
      if is_zero(a) then return ZERO end
      if not is_one(a) then table.insert(out,a) end
    end
    if #out == 0 then return ONE end
    if #out == 1 then return out[1] end
    if #out < #expr.args then return mul(out) end
  end
end)

table.insert(rules, function(expr)
  if is_neg(expr) then
    if is_num(expr.arg) then return num(-numval(expr.arg)) end
    if is_neg(expr.arg) then return expr.arg.arg end -- --a = a
    -- -a + b = b - a, handled by add/mul rules
  end
end)

-- Rewrite -a*b*c as -1 * a * b * c
table.insert(rules, function(expr)
  if is_neg(expr) and is_mul(expr.arg) then
    local new_args = {num(-1)}
    for _, a in ipairs(expr.arg.args) do
      table.insert(new_args, a)
    end
    return mul(new_args)
  end
end)

table.insert(rules, function(expr)
  if is_add(expr) then
    -- Group by non-numeric term
    local coeffs = {}
    local others = {}
    for _,a in ipairs(expr.args) do
      if is_mul(a) then
        -- Look for numeric coefficient
        local c, rest = nil, {}
        for _,f in ipairs(a.args) do
          if is_num(f) then c = (c or 1) * numval(f) else table.insert(rest, f) end
        end
        if #rest > 0 then
          local key_parts = {} -- Use a table for complex keys
          for _, r_term in ipairs(rest) do table.insert(key_parts, serialize_for_sort(r_term)) end
          table.sort(key_parts)
          local key = table.concat(key_parts, "*")
          
          coeffs[key] = coeffs[key] or {c=0, term=rest}
          coeffs[key].c = coeffs[key].c + (c or 1)
        else -- All terms in mul were numbers, should have been folded
          table.insert(others, a)
        end
      elseif is_num(a) then
        coeffs["#num"] = coeffs["#num"] or {c=0, term={}} -- term is not really applicable here
        coeffs["#num"].c = coeffs["#num"].c + numval(a)
      elseif is_var(a) then
        local key = serialize_for_sort(a) -- Use serialize for consistency
        coeffs[key] = coeffs[key] or {c=0, term={a}}
        coeffs[key].c = coeffs[key].c + 1
      else
        table.insert(others, a)
      end
    end
    local out = {}
    local changed_from_coeffs = false
    for k,info in pairs(coeffs) do
      if k == "#num" then
        if info.c ~= 0 then table.insert(out, num(info.c)) end
        if info.c == 0 and #expr.args > 1 then changed_from_coeffs = true end -- A number became zero
      else
        if info.c ~= 0 then
          if info.c == 1 then
            if #info.term == 1 then table.insert(out, info.term[1])
            else table.insert(out, mul(info.term)) end
          else
            local t_terms = deepcopy(info.term)
            table.insert(t_terms, 1, num(info.c)) -- Coefficient first
            table.insert(out, mul(t_terms))
          end
        else -- Coefficient became zero, term vanishes
           changed_from_coeffs = true
        end
      end
    end

    for _,a in ipairs(others) do table.insert(out, a) end
    
    if #out == 0 then return ZERO end
    if #out == 1 and #others == 0 and not (coeffs["#num"] and #expr.args == 1 and ast_eq(expr.args[1], out[1])) then -- Avoid infinite loop for single number
        return out[1] 
    end

    -- Check if a meaningful change occurred or if the number of terms was reduced
    if #out < #expr.args or changed_from_coeffs then
        if #out == 0 then return ZERO end
        if #out == 1 then return out[1] end
        return add(out)
    end
  end
end)

-- Cancel additive inverses: a + (-a) => 0
table.insert(rules, function(expr)
  if is_add(expr) and #expr.args >= 2 then
    local to_remove = {}
    for i = 1, #expr.args do
      for j = i + 1, #expr.args do
        local a, b = expr.args[i], expr.args[j]
        if is_neg(a) and ast_eq(a.arg, b) then
          table.insert(to_remove, i)
          table.insert(to_remove, j)
        elseif is_neg(b) and ast_eq(b.arg, a) then
          table.insert(to_remove, i)
          table.insert(to_remove, j)
        end
      end
    end
    if #to_remove > 0 then
      local keep = {}
      local skip = {}
      for _, idx in ipairs(to_remove) do skip[idx] = true end
      for i = 1, #expr.args do
        if not skip[i] then table.insert(keep, expr.args[i]) end
      end
      if #keep == 0 then return num(0) end
      if #keep == 1 then return keep[1] end
      return add(keep)
    end
  end
end)


-- Combining exponents: x^a * x^b = x^(a+b)
table.insert(rules, function(expr)
  if is_mul(expr) then
    local exps = {} -- base_repr -> list of exponents
    local others = {}
    local has_combined = false

    for _,a in ipairs(expr.args) do
      local base_node, exp_node
      if is_pow(a) then
        base_node = a.base
        exp_node = a.exp
      elseif is_var(a) then
        base_node = a
        exp_node = ONE
      else
        table.insert(others, a)
      end

      if base_node then
        local key = serialize_for_sort(base_node)
        exps[key] = exps[key] or {base = base_node, exps_list = {}}
        table.insert(exps[key].exps_list, exp_node)
      end
    end

    local out = {}
    for _,a in ipairs(others) do table.insert(out, a) end -- Add non-power/non-var terms first

    for _,info in pairs(exps) do
      local current_base = info.base
      local current_exps_list = info.exps_list
      local final_exp
      if #current_exps_list == 1 then
        final_exp = current_exps_list[1]
      else
        final_exp = simplify.simplify(add(current_exps_list)) -- Simplify the sum of exponents
        has_combined = true -- Mark that we combined exponents
      end

      if is_zero(final_exp) then
        table.insert(out, ONE) -- x^0 = 1
        has_combined = true
      elseif is_one(final_exp) then
        table.insert(out, current_base) -- x^1 = x
      else
        table.insert(out, pow(current_base, final_exp))
      end
    end
    
    if not has_combined and #out == #expr.args then return nil end -- No change

    -- Post-process 'out' to remove ONEs if other terms exist, and handle products of ONEs
    local final_out = {}
    local non_one_terms = 0
    for _, term in ipairs(out) do
        if not is_one(term) then
            table.insert(final_out, term)
            non_one_terms = non_one_terms + 1
        end
    end

    if #final_out == 0 then return ONE end -- All terms were ONE or cancelled to ONE
    if #final_out == 1 then return final_out[1] end
    if #final_out < #expr.args or has_combined or non_one_terms < #out then -- Check if simplification occurred
      return mul(final_out)
    end
  end
end)


-- Distributive law: a*(b + c) => a*b + a*c
table.insert(rules, function(expr)
  if is_mul(expr) then
    for i, arg_outer in ipairs(expr.args) do
      if is_add(arg_outer) then
        local factor_terms = {} -- The terms not being distributed over
        for j, other_arg in ipairs(expr.args) do
          if i ~= j then table.insert(factor_terms, other_arg) end
        end

        if #factor_terms == 0 then return nil end -- e.g. just (b+c), no a to distribute

        local expanded_terms = {}
        for _, term_inner in ipairs(arg_outer.args) do
          local current_product_args = {deepcopy(term_inner)}
          for _, ft in ipairs(factor_terms) do
            table.insert(current_product_args, deepcopy(ft))
          end
          table.insert(expanded_terms, mul(current_product_args))
        end
        return add(expanded_terms)
      end
    end
  end
end)


-- Expand (a+b)^n for small integer n
table.insert(rules, function(expr)
    if is_pow(expr) and is_add(expr.base) and #expr.base.args == 2 and is_num(expr.exp) and is_integer(numval(expr.exp)) then
        local n_val = numval(expr.exp)
        if n_val > 1 and n_val <= 5 then -- Limit expansion to avoid blowup, e.g. (a+b)^2 to (a+b)^5
            local n = n_val
            local function binom(N, K) -- N choose K
                if K < 0 or K > N then return 0 end
                if K == 0 or K == N then return 1 end
                if K > N / 2 then K = N - K end -- Symmetry
                local res = 1
                for i = 1, K do
                    res = res * (N - i + 1) / i
                end
                return res
            end

            local terms = {}
            local term_a, term_b -- Assuming base is a sum of two terms a+b
            
            -- Handle cases like (x-y)^n which is (x + (-y))^n
            local base_args = expr.base.args
            term_a = base_args[1]

            -- Check if the second term is a negation or part of a subtraction
            if is_neg(base_args[2]) then
                term_b = base_args[2] -- Keep as neg node for a + (-b)
            else
                -- This part needs to correctly identify (a-b) which might be represented as add(a, mul(-1, b)) after some canonicalization
                -- For now, let's assume a simple add({a, b}) or add({a, neg(b)})
                term_b = base_args[2] 
            end


            for k = 0, n do
                local coeff_val = binom(n, k)
                if coeff_val ~= 0 then
                    local coeff_node = num(coeff_val)
                    
                    local parts_of_term = {}
                    if not is_one(coeff_node) or (n==0 and k==0) then -- Add coefficient unless it's 1 (and not for 1*1^0*b^0)
                        table.insert(parts_of_term, coeff_node)
                    end

                    -- term_a^(n-k)
                    if n - k > 0 then
                        if n - k == 1 then
                            table.insert(parts_of_term, deepcopy(term_a))
                        else
                            table.insert(parts_of_term, pow(deepcopy(term_a), num(n - k)))
                        end
                    elseif n-k == 0 and is_one(coeff_node) and k == n and n ~= 0 then -- case a^0 * b^n, don't add 1 if coeff is 1
                         -- but if it's just (a+b)^0 = 1, the coeff_node=1 is already there
                    elseif n-k == 0 and not (is_one(coeff_node) and #parts_of_term > 0) and #parts_of_term == 0 then
                         -- if coefficient is not 1, or if it's the only term so far (e.g. for 1 * a^0 * b^0)
                        -- table.insert(parts_of_term, ONE) -- a^0 = 1
                    end

                    -- term_b^k
                    if k > 0 then
                        if k == 1 then
                            table.insert(parts_of_term, deepcopy(term_b))
                        else
                            table.insert(parts_of_term, pow(deepcopy(term_b), num(k)))
                        end
                    elseif k == 0 and is_one(coeff_node) and n-k == n and n ~=0 then
                        -- case a^n * b^0, don't add 1
                    elseif k == 0 and not (is_one(coeff_node) and #parts_of_term > 0) and #parts_of_term == 0 then
                        -- table.insert(parts_of_term, ONE) -- b^0 = 1
                    end
                    
                    if #parts_of_term == 0 then -- e.g. for (a+b)^0, only coefficient 1 remains
                        if is_one(coeff_node) then table.insert(terms, ONE)
                        else table.insert(terms, coeff_node) end -- Should not happen if binom(0,0)=1
                    elseif #parts_of_term == 1 then
                        table.insert(terms, parts_of_term[1])
                    else
                        table.insert(terms, mul(parts_of_term))
                    end
                end
            end
            if #terms == 0 then return ONE end -- e.g. (a+b)^0 results in one term: 1
            if #terms == 1 then return terms[1] end
            return add(terms)
        end
    end
end)


-- Expand (a-b)^2, (a+b)^2, (a-b)^3, etc (This rule seems redundant if the above handles it for n<=5)
-- table.insert(rules, function(expr)
--   if is_pow(expr) and is_add(expr.base) and is_num(expr.exp) and is_integer(numval(expr.exp)) and numval(expr.exp) > 1 then
--     -- Already handled for n <= 5 above
--     -- For larger n, skip (to avoid blowup)
--   end
-- end)

-- x^a^b = x^(a*b)
table.insert(rules, function(expr)
  if is_pow(expr) and is_pow(expr.base) then
    return pow(expr.base.base, mul{expr.base.exp, expr.exp})
  end
end)

-- Logarithmic and exponential rules
table.insert(rules, function(expr)
  if is_func(expr) then
    local n = expr.name
    local a = expr.args[1] -- Assuming single argument for most of these
    if n == "log" then
      if not a then return expr end -- Should not happen with valid AST
      -- log(1) = 0
      if is_one(a) then return ZERO end
      -- log(x^a) = a*log(x)
      if is_pow(a) then return mul{deepcopy(a.exp), func("log",{deepcopy(a.base)})} end
      -- log(e^x) = x (if base e is implied, or if E constant is used for base)
      if is_pow(a) and ((is_var(a.base) and a.base.name == "e") or (is_num(a.base) and math.abs(numval(a.base) - math.exp(1)) < 1e-10)) then
        return a.exp
      end
      if is_func(a) and a.name == "exp" then -- log(exp(x)) = x
        return a.args[1]
      end
      -- log(a*b) = log(a) + log(b)
      if is_mul(a) then
        local logs = {}
        for _,t in ipairs(a.args) do table.insert(logs, func("log",{deepcopy(t)})) end
        return add(logs)
      end
       -- log(a/b) = log(a) - log(b)
      if is_mul(a) and #a.args == 2 and is_pow(a.args[2]) and is_minus_one(a.args[2].exp) then
        -- a is of form term1 * term2^-1
        local term1 = a.args[1]
        local term2_base = a.args[2].base
        return add({ func("log", {deepcopy(term1)}), neg(func("log", {deepcopy(term2_base)})) })
      end
    elseif n == "exp" then
      if not a then return expr end
      -- exp(0) = 1
      if is_zero(a) then return ONE end
      -- exp(log(x)) = x
      if is_func(a) and a.name == "log" then return a.args[1] end
      -- exp(a+b) = exp(a)*exp(b)
      if is_add(a) then
        local exps = {}
        for _,term in ipairs(a.args) do
          table.insert(exps, func("exp", {deepcopy(term)}))
        end
        return mul(exps)
      end
      -- (e^a)^b = e^(a*b) -- exp(a*log(b)) = b^a; exp(b*log(a)) = a^b
      -- This one is tricky: exp(X) where X = Y * log(Z)  => Z^Y
      if is_mul(a) and #a.args == 2 then
          local arg1, arg2 = a.args[1], a.args[2]
          if is_func(arg2) and arg2.name == "log" then -- arg1 * log(arg2_inner)
              return pow(deepcopy(arg2.args[1]), deepcopy(arg1))
          elseif is_func(arg1) and arg1.name == "log" then -- log(arg1_inner) * arg2
              return pow(deepcopy(arg1.args[1]), deepcopy(arg2))
          end
      end

    elseif n == "sin" or n == "cos" then
      if not a then return expr end
      -- sin(0)=0, cos(0)=1
      if is_zero(a) then return n == "sin" and ZERO or ONE end
      -- sin(-x) = -sin(x), cos(-x) = cos(x)
      if is_neg(a) then
        if n == "sin" then return neg(func("sin", {deepcopy(a.arg)})) end
        if n == "cos" then return func("cos", {deepcopy(a.arg)}) end
      end
      -- sin(n*pi) = 0 for integer n
      if n == "sin" and is_mul(a) and #a.args == 2 then
          local factor1, factor2 = a.args[1], a.args[2]
          if is_num(factor1) and is_integer(numval(factor1)) and is_var(factor2) and factor2.name == "pi" then return ZERO end
          if is_num(factor2) and is_integer(numval(factor2)) and is_var(factor1) and factor1.name == "pi" then return ZERO end
          if is_num(factor1) and is_integer(numval(factor1)) and is_num(factor2) and math.abs(numval(factor2) - math.pi) < 1e-9 then return ZERO end
          if is_num(factor2) and is_integer(numval(factor2)) and is_num(factor1) and math.abs(numval(factor1) - math.pi) < 1e-9 then return ZERO end
      end
      -- cos(n*pi) = (-1)^n for integer n
      if n == "cos" and is_mul(a) and #a.args == 2 then
          local factor_n, factor_pi
          if is_num(a.args[1]) and is_integer(numval(a.args[1])) and ((is_var(a.args[2]) and a.args[2].name == "pi") or (is_num(a.args[2]) and math.abs(numval(a.args[2]) - math.pi) < 1e-9)) then
              factor_n = a.args[1]
          elseif is_num(a.args[2]) and is_integer(numval(a.args[2])) and ((is_var(a.args[1]) and a.args[1].name == "pi") or (is_num(a.args[1]) and math.abs(numval(a.args[1]) - math.pi) < 1e-9)) then
              factor_n = a.args[2]
          end
          if factor_n then
              if numval(factor_n) % 2 == 0 then return ONE else return MINUS_ONE end
          end
      end

    elseif n == "tan" then
      if not a then return expr end
      -- tan(0)=0
      if is_zero(a) then return ZERO end
      -- tan(-x) = -tan(x)
      if is_neg(a) then return neg(func("tan", {deepcopy(a.arg)})) end
    end
  end
end)

-- Trig identities (basic)
table.insert(rules, function(expr)
  -- sin^2(x) + cos^2(x) = 1
  if is_add(expr) and #expr.args == 2 then
    local term1, term2 = expr.args[1], expr.args[2]
    local sin_arg, cos_arg

    local function check_sq_func(term, func_name)
        if is_pow(term) and is_num(term.exp) and numval(term.exp) == 2 and
           is_func(term.base) and term.base.name == func_name and #term.base.args == 1 then
            return term.base.args[1]
        end
        return nil
    end

    sin_arg = check_sq_func(term1, "sin")
    cos_arg = check_sq_func(term2, "cos")
    if sin_arg and cos_arg and ast_eq(sin_arg, cos_arg) then return ONE end

    sin_arg = check_sq_func(term2, "sin")
    cos_arg = check_sq_func(term1, "cos")
    if sin_arg and cos_arg and ast_eq(sin_arg, cos_arg) then return ONE end
  end

  -- tan(x) = sin(x)/cos(x) => sin(x) * cos(x)^-1
  if is_func(expr) and expr.name == "tan" and #expr.args == 1 then
    local arg = expr.args[1]
    return mul({ func("sin", {deepcopy(arg)}), pow(func("cos", {deepcopy(arg)}), MINUS_ONE) })
  end
  
  -- 1 - cos^2(x) = sin^2(x)
  if is_add(expr) and #expr.args == 2 then
    local one_term, minus_cos_sq_term
    if is_one(expr.args[1]) and is_neg(expr.args[2]) and is_pow(expr.args[2].arg) and is_num(expr.args[2].arg.exp) and numval(expr.args[2].arg.exp) == 2 and is_func(expr.args[2].arg.base) and expr.args[2].arg.base.name == "cos" then
        return pow(func("sin", {deepcopy(expr.args[2].arg.base.args)}), TWO)
    elseif is_one(expr.args[2]) and is_neg(expr.args[1]) and is_pow(expr.args[1].arg) and is_num(expr.args[1].arg.exp) and numval(expr.args[1].arg.exp) == 2 and is_func(expr.args[1].arg.base) and expr.args[1].arg.base.name == "cos" then
        return pow(func("sin", {deepcopy(expr.args[1].arg.base.args)}), TWO)
    end
  end
  -- 1 - sin^2(x) = cos^2(x)
  if is_add(expr) and #expr.args == 2 then
    local one_term, minus_sin_sq_term
    if is_one(expr.args[1]) and is_neg(expr.args[2]) and is_pow(expr.args[2].arg) and is_num(expr.args[2].arg.exp) and numval(expr.args[2].arg.exp) == 2 and is_func(expr.args[2].arg.base) and expr.args[2].arg.base.name == "sin" then
        return pow(func("cos", {deepcopy(expr.args[2].arg.base.args)}), TWO)
    elseif is_one(expr.args[2]) and is_neg(expr.args[1]) and is_pow(expr.args[1].arg) and is_num(expr.args[1].arg.exp) and numval(expr.args[1].arg.exp) == 2 and is_func(expr.args[1].arg.base) and expr.args[1].arg.base.name == "sin" then
        return pow(func("cos", {deepcopy(expr.args[1].arg.base.args)}), TWO)
    end
  end

end)


table.insert(rules, function(expr)
  -- Multiplication of fractions: (a/b) * (c/d) = (a*c)/(b*d)
  -- This is generally handled by canonicalization (flattening muls, combining powers)
  -- e.g. a * b^-1 * c * d^-1  becomes a * c * b^-1 * d^-1 which is mul({a,c}, pow(mul({b,d}), MINUS_ONE))

  -- Addition of fractions: a/b + c/d = (ad+bc)/bd
  -- This rule can be complex and lead to expression blowup if not careful.
  -- The existing rule is a bit basic, this is a placeholder for more advanced common denominator logic.
  -- Current implementation tries to make a common denominator by just multiplying all denominators.
  -- A more advanced version would find the LCM of denominators.
  if is_add(expr) then
    local terms_with_denominators = {}
    local other_terms = {}
    local has_fractions = false

    for _, arg in ipairs(expr.args) do
      if is_mul(arg) and #arg.args > 0 then
        local num_parts = {}
        local den_parts = {}
        for _, factor in ipairs(arg.args) do
          if is_pow(factor) and is_num(factor.exp) and numval(factor.exp) < 0 then
            table.insert(den_parts, pow(deepcopy(factor.base), num(-numval(factor.exp))))
            has_fractions = true
          else
            table.insert(num_parts, deepcopy(factor))
          end
        end
        if #den_parts > 0 then
          local numerator = (#num_parts == 0) and ONE or ((#num_parts == 1) and num_parts[1] or mul(num_parts))
          local denominator = (#den_parts == 1) and den_parts[1] or mul(den_parts)
          table.insert(terms_with_denominators, {n = numerator, d = denominator})
        else
          table.insert(other_terms, arg) -- Not a fraction of the form num * den^-1
        end
      elseif is_pow(arg) and is_num(arg.exp) and numval(arg.exp) < 0 then
        table.insert(terms_with_denominators, {n = ONE, d = pow(deepcopy(arg.base), num(-numval(arg.exp)))})
        has_fractions = true
      else
        table.insert(other_terms, arg)
      end
    end

    if not has_fractions or #terms_with_denominators == 0 then return nil end
    
    -- If there are other terms not in fraction form, treat them as other_term / 1
    for _, ot in ipairs(other_terms) do
        table.insert(terms_with_denominators, {n = ot, d = ONE})
    end
    if #terms_with_denominators <= 1 and #other_terms == 0 then return nil end -- only one fraction, or no fractions

    -- Find common denominator (simplified: product of all unique denominators)
    -- More advanced: LCM. For now, product of simplified denominators.
    local denominators_list = {}
    for _, frac in ipairs(terms_with_denominators) do
        table.insert(denominators_list, frac.d)
    end
    
    -- This is a very naive common denominator.
    -- A proper GCD/LCM for polynomials would be needed for better results.
    -- For now, just multiply them if more than one distinct.
    local common_denominator_terms = {}
    local unique_denoms_str = {}
    for _,d_node in ipairs(denominators_list) do
        if not is_one(d_node) then
            local s = serialize_for_sort(simplify.simplify(d_node)) -- Simplify and serialize
            if not unique_denoms_str[s] then
                table.insert(common_denominator_terms, simplify.simplify(d_node))
                unique_denoms_str[s] = true
            end
        end
    end
    
    local common_denominator
    if #common_denominator_terms == 0 then
        common_denominator = ONE
    elseif #common_denominator_terms == 1 then
        common_denominator = common_denominator_terms[1]
    else
        common_denominator = simplify.simplify(mul(common_denominator_terms))
    end
    
    if is_one(common_denominator) and #other_terms == #expr.args then return nil end -- all were whole numbers


    local new_numerators_sum_args = {}
    for _, frac in ipairs(terms_with_denominators) do
      local current_num = frac.n
      local current_den = frac.d

      if ast_eq(current_den, common_denominator) then
        table.insert(new_numerators_sum_args, current_num)
      else
        -- multiplier = common_denominator / current_den
        -- To avoid explicit division in AST if current_den is complex,
        -- we are essentially doing: num * (common_den / current_den)
        -- = num * common_den * current_den^-1
        -- This needs careful simplification itself.
        -- A simpler approach: find what to multiply num by.
        -- If common_den = d1*d2*d3 and current_den = d1, multiplier is d2*d3.
        -- This requires factorization of denominators. Too complex for now.
        -- Naive: new_num_part = current_num * (common_denominator / current_den)
        -- Let's use the simplify engine for (common_denominator * current_den^-1)
        if is_one(current_den) then
             table.insert(new_numerators_sum_args, simplify.simplify(mul({current_num, common_denominator})))
        else
            local den_inv = simplify.simplify(pow(current_den, MINUS_ONE))
            local multiplier = simplify.simplify(mul({common_denominator, den_inv}))
            table.insert(new_numerators_sum_args, simplify.simplify(mul({current_num, multiplier})))
        end
      end
    end
    
    local sum_of_new_numerators = simplify.simplify(add(new_numerators_sum_args))

    if is_zero(sum_of_new_numerators) then return ZERO end
    if is_one(common_denominator) then return sum_of_new_numerators end

    return mul({sum_of_new_numerators, pow(common_denominator, MINUS_ONE)})
  end
end)


table.insert(rules, function(expr)
  -- Simplify x^1 => x (already present, but good to have as a cleanup)
  if is_pow(expr) and is_one(expr.exp) then
    return expr.base
  end
  -- Simplify ...*1*... => ...
  if is_mul(expr) then
    local out = {}
    local changed = false
    for _,a in ipairs(expr.args) do
      if not is_one(a) then table.insert(out, a)
      else changed = true
      end
    end
    if not changed then return nil end
    if #out == 0 then return ONE end
    if #out == 1 then return out[1] end
    return mul(out)
  end
  -- Simplify add({n}) => n and mul({n}) => n (general cleanup)
  if (is_add(expr) or is_mul(expr)) and #expr.args == 1 then
    return expr.args[1]
  end
end)

table.insert(rules, function(expr)
  -- Clean up powers
  if is_pow(expr) then
    if is_one(expr.exp) then return expr.base end
    if is_zero(expr.exp) and not is_zero(expr.base) then return ONE end -- 0^0 is undefined/contextual, often 1 in combinatorics
    if is_zero(expr.base) and is_num(expr.exp) and numval(expr.exp) > 0 then return ZERO end -- 0^positive = 0
    if is_one(expr.base) then return ONE end -- 1^x = 1
  end
  -- Clean up multiplication by zero or one
  if is_mul(expr) then
    local out = {}
    local has_zero = false
    local changed = false
    for _, a in ipairs(expr.args) do
      if is_zero(a) then has_zero = true; break end
      if not is_one(a) then table.insert(out, a)
      else changed = true -- A '1' was removed
      end
    end
    if has_zero then return ZERO end
    if not changed and #out == #expr.args then return nil end -- No change

    if #out == 0 then return ONE end -- Product of ones
    if #out == 1 then return out[1] end
    return mul(out)
  end
  -- Clean up addition of zero
  if is_add(expr) then
    local out = {}
    local changed = false
    for _, a in ipairs(expr.args) do
      if not is_zero(a) then table.insert(out, a)
      else changed = true -- A '0' was removed
      end
    end
    if not changed and #out == #expr.args then return nil end -- No change

    if #out == 0 then return ZERO end -- Sum of zeros
    if #out == 1 then return out[1] end
    return add(out)
  end
end)


local function factorial(n_val)
  if not (n_val >= 0 and math.floor(n_val) == n_val) then
    -- For non-integer or negative, factorial is often undefined or uses Gamma
    -- This CAS might want to return gamma(n+1) or an error/unevaluated
    return nil -- Or perhaps func("gamma", {add({num(n_val), ONE})}) if that's desired behavior
  end
  local result = 1
  for i = 2, n_val do result = result * i end
  return result
end

-- Approximate gamma using Lanczos approximation
local function gamma_lanczos(z_val)
    local p_coeffs = {
        676.5203681218851, -1259.1392167224028, 771.32342877765313,
        -176.61502916214059, 12.507343278686905,
        -0.13857109526572012, 9.9843695780195716e-6,
        1.5056327351493116e-7
    }
    if z_val < 0.5 then
        if math.sin(math.pi * z_val) == 0 then return nil end -- Pole, undefined
        local gamma_one_minus_z = gamma_lanczos(1 - z_val)
        if not gamma_one_minus_z then return nil end
        return math.pi / (math.sin(math.pi * z_val) * gamma_one_minus_z)
    else
        local z_adj = z_val - 1
        local x = 0.99999999999980993
        for i = 1, #p_coeffs do
            x = x + p_coeffs[i] / (z_adj + i)
        end
        local t = z_adj + #p_coeffs - 0.5
        return math.sqrt(2 * math.pi) * (t^(z_adj + 0.5)) * math.exp(-t) * x
    end
end


-- Gamma and Factorial function rules
table.insert(rules, function(expr)
  if is_func(expr) then
    if expr.name == "gamma" and #expr.args == 1 and is_num(expr.args[1]) then
      local x_val = numval(expr.args[1])
      if x_val > 0 then
        if is_integer(x_val) then -- gamma(n) = (n-1)! for positive integer n
          local fact_val = factorial(x_val - 1)
          if fact_val then return num(fact_val) end
        else -- Positive non-integer
          local gamma_val = gamma_lanczos(x_val)
          if gamma_val then return num(gamma_val) end
        end
      elseif x_val <= 0 and is_integer(x_val) then
          return nil -- Undefined (pole) for 0 and negative integers
      else -- Negative non-integer, use reflection formula if gamma_lanczos handles it or transformed
          local gamma_val = gamma_lanczos(x_val)
          if gamma_val then return num(gamma_val) end
      end
    elseif expr.name == "factorial" and expr.args and #expr.args == 1 then
      local arg_node = expr.args[1]
      if is_num(arg_node) then
        local n_val = numval(arg_node)
        if is_integer(n_val) and n_val >= 0 then
          local fact_val = factorial(n_val)
          if fact_val then return num(fact_val) end
        else
          -- factorial(non-integer) -> gamma(non-integer + 1)
          local gamma_arg = simplify.simplify(add({ arg_node, ONE }))
          return func("gamma", { gamma_arg })
        end
      -- factorial(x+1) is often kept as is, or gamma(x+2)
      -- No specific symbolic transformation here beyond numerical evaluation or gamma conversion
      end
    end
  end
end)

-- Symbolic simplification for factorial/gamma relations
table.insert(rules, function(expr)
    -- gamma(x+1) => x*gamma(x) or x! if x is suitable for factorial
    if is_func(expr) and expr.name == "gamma" and #expr.args == 1 then
        local arg = expr.args[1]
        if is_add(arg) and #arg.args == 2 then
            local term1, term2
            if is_one(arg.args[2]) then -- x + 1 form
                term1 = arg.args[1] 
                term2 = arg.args[2]
            elseif is_one(arg.args[1]) then -- 1 + x form
                term1 = arg.args[2]
                term2 = arg.args[1]
            end
            if term1 then
                -- If term1 is an integer or variable for which factorial makes sense:
                -- gamma(n+1) = n!
                -- This transformation to factorial is often preferred
                -- For now, let's do x*gamma(x)
                -- return mul({deepcopy(term1), func("gamma", {deepcopy(term1)})})
                -- The transformFactorial function already handles factorial -> gamma,
                -- so perhaps we want gamma(x+1) -> x! if it simplifies things
                 return func("factorial", {deepcopy(term1)}) -- This is done by transformFactorial's intent or a specific rule.
                                                           -- Re-evaluate if this rule is beneficial here or creates loops.
                                                           -- Given transformFactorial, this might be redundant or better placed.
                                                           -- Let's keep it as is per user's original structure intent.
            end
        end
    end

    -- x! / (x-1)! = x
    -- Representation: mul({ factorial(x), pow(factorial(add({x, num(-1)})), MINUS_ONE) })
    if is_mul(expr) and #expr.args == 2 then
        local fac_term, inv_fac_term
        if is_func(expr.args[1]) and expr.args[1].name == "factorial" and
           is_pow(expr.args[2]) and is_func(expr.args[2].base) and expr.args[2].base.name == "factorial" and
           is_minus_one(expr.args[2].exp) then
            fac_term = expr.args[1]
            inv_fac_term = expr.args[2].base
        elseif is_func(expr.args[2]) and expr.args[2].name == "factorial" and
                 is_pow(expr.args[1]) and is_func(expr.args[1].base) and expr.args[1].base.name == "factorial" and
                 is_minus_one(expr.args[1].exp) then
            fac_term = expr.args[2]
            inv_fac_term = expr.args[1].base
        end

        if fac_term and inv_fac_term then
            local fac_arg = fac_term.args[1]
            local inv_fac_arg = inv_fac_term.args[1]
            -- Check if fac_arg is inv_fac_arg + 1
            local diff_check = simplify.simplify(add({deepcopy(inv_fac_arg), ONE}))
            if ast_eq(fac_arg, diff_check) then
                return deepcopy(fac_arg) -- Returns x (if fac_arg was x, from x! / (x-1)!)
            end
        end
    end

    -- x! / x = (x-1)!
    -- Representation: mul({ factorial(x), pow(x, MINUS_ONE) })
    if is_mul(expr) and #expr.args == 2 then
        local fac_node, var_inv_node
        if is_func(expr.args[1]) and expr.args[1].name == "factorial" and is_pow(expr.args[2]) and is_minus_one(expr.args[2].exp) then
            fac_node = expr.args[1]
            var_inv_node = expr.args[2]
        elseif is_func(expr.args[2]) and expr.args[2].name == "factorial" and is_pow(expr.args[1]) and is_minus_one(expr.args[1].exp) then
            fac_node = expr.args[2]
            var_inv_node = expr.args[1]
        end

        if fac_node and var_inv_node then
            if ast_eq(fac_node.args[1], var_inv_node.base) then
                return func("factorial", {simplify.simplify(add({deepcopy(fac_node.args[1]), MINUS_ONE}))})
            end
        end
    end
    
    -- x! * x = (x+1)! -- This rule seems to be implemented inversely below, x! * x usually doesn't combine this way unless it's (x-1)! * x
    -- More common is (x-1)! * x = x!
    if is_mul(expr) and #expr.args == 2 then
        local term1, term2 = expr.args[1], expr.args[2]
        local fac_node, var_node
        if is_func(term1) and term1.name == "factorial" then
            fac_node = term1; var_node = term2;
        elseif is_func(term2) and term2.name == "factorial" then
            fac_node = term2; var_node = term1;
        end

        if fac_node and var_node then -- var_node must be a variable or expression
            -- We want to match (X)! * (X+1)  -> (X+1)!
            -- Or X! * (X+1) -> (X+1)!
            local fac_arg_plus_one = simplify.simplify(add({deepcopy(fac_node.args[1]), ONE}))
            if ast_eq(var_node, fac_arg_plus_one) then
                 return func("factorial", {deepcopy(var_node)}) -- { (X+1)! }
            end
        end
    end


    -- x! / x! = 1
    if is_mul(expr) and #expr.args == 2 and is_func(expr.args[1]) and expr.args[1].name == "factorial" and
       is_pow(expr.args[2]) and is_func(expr.args[2].base) and expr.args[2].base.name == "factorial" and
       is_minus_one(expr.args[2].exp) then
        if ast_eq(expr.args[1].args[1], expr.args[2].base.args[1]) then return ONE end
    end
end)


--[[
------------------------------------------------------------------------------------
-- PLACEHOLDER FOR ADDITIONAL RULES FROM THE (INCOMPLETE) SECOND SNIPPET:
-- If the second snippet (Comprehensive CAS) had complete rule definitions like:
-- table.insert(rules, function(expr) ... advanced rule ... end)
-- They would be added here.
-- For example, if the second snippet contained:
-- table.insert(rules, function(expr)
--   -- Example advanced rule for derivative, e.g. d/dx(sin(x)) = cos(x)
--   if is_func(expr) and expr.name == "diff" and #expr.args == 2 then
--     local func_to_diff = expr.args[1]
--     local diff_var = expr.args[2]
--     if is_func(func_to_diff) and func_to_diff.name == "sin" and ast_eq(func_to_diff.args[1], diff_var) then
--       return func("cos", {deepcopy(diff_var)})
--     end
--   end
-- end)
-- That block of code would be inserted in this section.
------------------------------------------------------------------------------------
--]]

-- Fallback: return the node unchanged (already part of the iterative loop logic)
-- local function fallback(expr) return nil end

--[[
  Recursive and Iterative Simplification
  - Recursively simplify children
  - Apply all rules in order
  - Repeat passes until stable (fixed point)
--]]

-- Define recursive_simplify before its first usage (e.g., in canonicalize or simplify.simplify)
recursive_simplify = function(expr, recursion_depth)
  dbgprint("recursive_simplify called for:", simplify.pretty_print(expr))
  recursion_depth = recursion_depth or 0
  if recursion_depth > 50 then -- Max recursion depth to prevent infinite loops
    -- print("Warning: Max recursion depth reached for expression:", simplify.pretty_print(expr))
    return expr 
  end

  if type(expr) ~= "table" then return expr end
  
  local e = deepcopy(expr) -- Work on a copy to allow changes

  -- Recursively simplify children first
  if e.type == "add" or e.type == "mul" or e.type == "func" then
    if e.args then
        local new_args = {}
        for i,a in ipairs(e.args) do new_args[i] = recursive_simplify(a, recursion_depth + 1) end
        e.args = new_args
    end
  elseif e.type == "pow" then
    e.base = recursive_simplify(e.base, recursion_depth + 1)
    e.exp = recursive_simplify(e.exp, recursion_depth + 1)
  elseif e.type == "neg" then
    e.arg = recursive_simplify(e.arg, recursion_depth + 1)
  end

  -- Apply rules iteratively until no more changes
  local max_rule_passes = 50 -- Prevent runaway rule application
  for pass = 1, max_rule_passes do
    local changed_in_pass = false
    e = canonicalize(e) -- Canonicalize before each rule pass
    
    for _, rule in ipairs(rules) do
      local res = rule(e)
      if res and not ast_eq(res, e) then
        e = res
        e = canonicalize(e) -- Canonicalize after a successful rule application
        changed_in_pass = true
        -- break -- Restart rule application from the beginning for the new expression form
                -- Or continue applying other rules to the modified 'e'.
                -- Restarting (break) is often safer to ensure rules see a stable state.
      end
    end
    if not changed_in_pass then break end -- Stable state for this level
    if pass == max_rule_passes then
        -- print("Warning: Max rule passes reached for sub-expression:", simplify.pretty_print(expr))
    end
  end
  
  dbgprint("recursive_simplify result:", simplify.pretty_print(e))
  return canonicalize(e) -- Final canonical form for this level
end


-- Transform factorial(n) to gamma(n+1), recursively for all subnodes.
-- This should ideally run once before the main simplification loop,
-- or be integrated as a rule if gamma is the preferred internal form.
local function transformFactorialToGamma(expr)
  if type(expr) ~= "table" then return expr end

  local new_expr = deepcopy(expr) -- Operate on a copy

  if new_expr.type == "func" and new_expr.name == "factorial" and new_expr.args and #new_expr.args == 1 then
    local arg_transformed = transformFactorialToGamma(new_expr.args[1])
    return {
      type = "func",
      name = "gamma",
      args = {
        simplify.simplify(add({ arg_transformed, ONE })) -- Simplify (arg + 1)
      }
    }
  end

  -- Recursively transform arguments/parts of the expression
  if new_expr.args then
    for i, arg_child in ipairs(new_expr.args) do
      new_expr.args[i] = transformFactorialToGamma(arg_child)
    end
  elseif new_expr.arg then -- For unary operations like 'neg'
    new_expr.arg = transformFactorialToGamma(new_expr.arg)
  elseif new_expr.base and new_expr.exp then -- For 'pow'
    new_expr.base = transformFactorialToGamma(new_expr.base)
    new_expr.exp = transformFactorialToGamma(new_expr.exp)
  end
  
  return new_expr
end


function simplify.simplify(expr_input)
  dbgprint("Input to simplify:", simplify.pretty_print(expr_input))
  local expr = deepcopy(expr_input) -- Ensure we don't modify the input AST
  
  -- Step 1: Transform all factorial(n) to gamma(n+1) as a preprocessing step
  -- This makes gamma the canonical form for these types of functions.
  expr = transformFactorialToGamma(expr)
  expr = canonicalize(expr) -- Canonicalize after transformation

  dbgprint("Starting simplification main loop. Initial expr:", simplify.pretty_print(expr))
  local current_expr = expr
  local max_iterations = 20 -- Max iterations for the main simplification loop
  
  for i = 1, max_iterations do
    dbgprint("Iteration", i, "Current expr:", simplify.pretty_print(current_expr))
    local simplified_once = recursive_simplify(current_expr)
    local next_expr = canonicalize(simplified_once)
    
    if ast_eq(current_expr, next_expr) then
      -- print("Simplification converged in " .. i .. " iterations.")
      break -- Fixed point reached
    end
    current_expr = next_expr
    dbgprint("After iteration", i, "Next expr:", simplify.pretty_print(current_expr))
    if i == max_iterations then
        -- print("Warning: Simplification reached max iterations (" .. max_iterations .. ").")
    end
  end
  return current_expr
end


-- Export all utilities
simplify.rules = rules
simplify.deepcopy = deepcopy
simplify.ast_eq = ast_eq
simplify.is_num = is_num
simplify.is_var = is_var
simplify.is_add = is_add
simplify.is_mul = is_mul
simplify.is_pow = is_pow
simplify.is_neg = is_neg
simplify.is_func = is_func
simplify.num = num
simplify.var = var
simplify.add = add
simplify.mul = mul
simplify.pow = pow
simplify.neg = neg
simplify.func = func
simplify.flatten = flatten
simplify.sort_args = sort_args
simplify.occurs = occurs
simplify.copy_node = copy_node
simplify.map_args = map_args
simplify.canonicalize = canonicalize

_G.simplify = simplify -- For use in environment if not loaded as a module

-- Rule from original first snippet (already present before your comment)
-- x! * x^(-1) => (x - 1)! -- This is effectively gamma(x+1) * x^-1 => gamma(x)
-- Given transformFactorialToGamma, this rule might be better expressed in terms of gamma,
-- or ensured that factorial forms are simplified before transformation if this specific form is desired.
table.insert(rules, function(expr)
  if is_mul(expr) and #expr.args == 2 then
    local term_a, term_b = expr.args[1], expr.args[2]
    local fac_node, inv_node
    
    if is_func(term_a) and term_a.name == "factorial" and is_pow(term_b) and is_minus_one(term_b.exp) then
        fac_node = term_a
        inv_node = term_b
    elseif is_func(term_b) and term_b.name == "factorial" and is_pow(term_a) and is_minus_one(term_a.exp) then
        fac_node = term_b
        inv_node = term_a
    end

    if fac_node and inv_node and ast_eq(fac_node.args[1], inv_node.base) then
      -- fac_node.args[1] is 'x' from x!
      -- We want (x-1)! which is factorial(add({x, num(-1)}))
      return func("factorial", { add({ deepcopy(fac_node.args[1]), MINUS_ONE }) })
    end
  end
end)

table.insert(rules, function(expr)
  -- factorial(x) * x^(-1) → factorial(x - 1)
  if is_mul(expr) and #expr.args == 2 then
    local a, b = expr.args[1], expr.args[2]
    if is_func(a) and a.name == "factorial"
        and is_pow(b)
        and is_var(b.base)
        and ast_eq(b.base, a.args[1])
        and is_minus_one(b.exp) then
      return func("factorial", { add{a.args[1], num(-1)} })
    end
  end
end)
table.insert(rules, function(expr)
  -- x * x^(-1) → 1
  if is_mul(expr) and #expr.args == 2 then
    local a, b = expr.args[1], expr.args[2]
    if is_var(a) and is_pow(b)
       and ast_eq(a, b.base)
       and is_minus_one(b.exp) then
      return num(1)
    end
    if is_var(b) and is_pow(a)
       and ast_eq(b, a.base)
       and is_minus_one(a.exp) then
      return num(1)
    end
  end
end)
-- Simplify expressions like x * x^(-1) or x / x to 1
table.insert(rules, function(expr)
  if is_mul(expr) and #expr.args == 2 then
    local a, b = expr.args[1], expr.args[2]
    local function is_inverse_pair(u, v)
      return ast_eq(u, v.base) and is_pow(v) and is_minus_one(v.exp)
    end
    if is_inverse_pair(a, b) or is_inverse_pair(b, a) then
      return num(1)
    end
  end
end)
-- Symbolic inverse simplification: x^(-1) * x → 1
table.insert(rules, function(expr)
  if is_mul(expr) and #expr.args == 2 then
    local a, b = expr.args[1], expr.args[2]

    local function is_inverse_pair(x, y)
      return is_pow(x) and ast_eq(x.base, y) and is_num(x.exp) and numval(x.exp) == -1
    end

    if is_inverse_pair(a, b) or is_inverse_pair(b, a) then
      return num(1)
    end
  end
end)

-- Pretty printer: convert AST to human-readable math string
local function pretty_print_recursive(expr, parent_precedence)
  parent_precedence = parent_precedence or 0
  local current_precedence

  -- Defensive clause: malformed or non-table node
  if type(expr) ~= "table" or not expr.type then
    return "<?>"
  end
  -- Defensive checks for malformed nodes
  if expr.type == "pow" and (not expr.base or not expr.exp) then
    return "<?bad pow>"
  end
  if expr.type == "mul" and not expr.args then
    return "<?bad mul>"
  end
  if expr.type == "add" and not expr.args then
    return "<?bad add>"
  end
  if expr.type == "variable" and not expr.name then
    return "<?bad var>"
  end
  if expr.type == "number" and expr.value == nil then
    return "<?bad num>"
  end

  if is_num(expr) then return tostring(expr.value) end
  if is_var(expr) then return expr.name end
  
  if is_neg(expr) then
    current_precedence = 4 -- Precedence of unary minus
    local arg_str = pretty_print_recursive(expr.arg, current_precedence)
    return "-" .. arg_str
  end
  
  if is_add(expr) then
    current_precedence = 1 -- Precedence of addition
    local parts = {}
    for i, arg in ipairs(expr.args) do
      local s = pretty_print_recursive(arg, current_precedence)
      if i > 1 and (type(s) == "string" and s:sub(1,1) ~= "-") then 
        table.insert(parts, "+") 
      end
      table.insert(parts, s)
    end
    local res = table.concat(parts)
    if current_precedence < parent_precedence then return "(" .. res .. ")" end
    return res
  end

  
  if is_mul(expr) then
    current_precedence = 2 -- Precedence of multiplication
    local parts = {}
    for i, arg in ipairs(expr.args) do
      local s = pretty_print_recursive(arg, current_precedence)
      parts[i] = s
    end
    -- Try to print 2x instead of 2*x if the form is (number, variable)
    if #parts == 2 and is_num(expr.args[1]) and is_var(expr.args[2]) then
      local res = tostring(expr.args[1].value) .. parts[2]
      if current_precedence < parent_precedence then return "(" .. res .. ")" end
      return res
    end
    -- Or variable*number as x2
    if #parts == 2 and is_var(expr.args[1]) and is_num(expr.args[2]) then
      local res = parts[1] .. tostring(expr.args[2].value)
      if current_precedence < parent_precedence then return "(" .. res .. ")" end
      return res
    end
    -- Otherwise print with *
    local res = table.concat(parts, "*")
    if current_precedence < parent_precedence then return "(" .. res .. ")" end
    return res
  end
  
  if is_pow(expr) then
    current_precedence = 3 -- Precedence of power
    local base_str = pretty_print_recursive(expr.base, current_precedence)
    local exp_str = pretty_print_recursive(expr.exp, 0) -- Exponent is usually fine without parens unless it's complex itself
    -- if is_add(expr.base) or is_mul(expr.base) then base_str = "(" .. base_str .. ")" end -- Handled by precedence
    -- if is_add(expr.exp) or is_mul(expr.exp) or is_pow(expr.exp) or is_neg(expr.exp) then exp_str = "(" .. exp_str .. ")" end -- Handled by precedence in recursive call
    local res = base_str .. "^" .. exp_str
    -- No, power is right-associative, so only add parens if parent_precedence is higher (e.g. (a^b)^c needs parens for a^b)
    -- However, (a*b)^c needs parens for a*b. This is handled by recursive call's parent_precedence.
    if current_precedence < parent_precedence then return "(" .. res .. ")" end -- This might be too aggressive
    return res
  end
  
  if is_func(expr) then
    local args_str = {}
    for _, a in ipairs(expr.args) do table.insert(args_str, pretty_print_recursive(a, 0)) end
    return expr.name .. "(" .. table.concat(args_str, ", ") .. ")"
  end
  
  return "<?>"
end

simplify.pretty_print = function(expr)
    return pretty_print_recursive(expr, 0)
end

-- x * x^-1 => 1
table.insert(rules, function(expr)
  if is_mul(expr) then -- Check if it's a multiplication node
    -- Iterate through all pairs of arguments to find an inverse pair
    for i = 1, #expr.args do
      for j = i + 1, #expr.args do
        local a = expr.args[i]
        local b = expr.args[j]
        
        local function is_inverse_pair(u, v)
          -- u is base, v is base^-1 OR v is base, u is base^-1
          if is_pow(v) and is_minus_one(v.exp) and ast_eq(u, v.base) then return true end
          if is_pow(u) and is_minus_one(u.exp) and ast_eq(v, u.base) then return true end
          return false
        end

        if is_inverse_pair(a, b) then
          local others = {}
          for k = 1, #expr.args do
            if k ~= i and k ~= j then
              table.insert(others, expr.args[k])
            end
          end
          if #others == 0 then return ONE end -- Only a*a^-1, result is 1
          table.insert(others, 1, ONE) -- Add 1 to the remaining terms
          return mul(others) -- This will simplify to mul(others) after another rule pass removes the 1
        end
      end
    end
  end
end)


-- Patch: always set metatable on all AST results from simplify
if _G.set_ast_mt then
  local _old_simplify = simplify.simplify
  function simplify.simplify(expr_input)
    local result = _old_simplify(expr_input)
    _G.set_ast_mt(result)
    return result
  end
end