-- Abstract Syntax Tree (AST) library for nLuaCAS.
-- Defines constructors, utilities, and transformation tools for symbolic expressions.

table.unpack = unpack

-- Use simplify.pretty_print for all string conversion of ASTs
local ok, simplify = pcall(require, "simplify")
if ok and simplify and simplify.pretty_print then
  function ast_tostring(ast)
    return simplify.pretty_print(ast)
  end
  ast.tostring = ast_tostring
end

-- Recursively print AST structure with optional indentation for debugging.
function ast_debug_print(ast, indent)
    indent = indent or ""
    if type(ast) ~= "table" then
        print(indent .. tostring(ast))
        return
    end
    if ast.type then
        local desc = ast.type
        if ast.name then desc = desc .. " (" .. tostring(ast.name) .. ")" end
        print(indent .. desc)
        if ast.value ~= nil then print(indent .. "  value: " .. tostring(ast.value)) end
        if ast.name ~= nil and ast.type ~= "variable" then print(indent .. "  name: " .. tostring(ast.name)) end
        if ast.args then
            print(indent .. "  args:")
            for i, arg in ipairs(ast.args) do
                ast_debug_print(arg, indent .. "    ")
            end
        end
        -- Print left/right for binary nodes
        if ast.left then
            print(indent .. "  left:")
            ast_debug_print(ast.left, indent .. "    ")
        end
        if ast.right then
            print(indent .. "  right:")
            ast_debug_print(ast.right, indent .. "    ")
        end
    else
        for k, v in pairs(ast) do
            print(indent .. tostring(k) .. ":")
            ast_debug_print(v, indent .. "  ")
        end
    end
end

-- Node constructors for common AST types.
function ast_number(val) return { type = "number", value = val } end
function ast_symbol(name) return { type = "variable", name = name } end
function ast_func(name, args) return { type = "func", name = name, args = args or {} } end
function ast_binop(op, left, right) return { type = op, left = left, right = right } end
function ast_neg(val) return { type = "neg", arg = val } end
function ast_pow(base, exp) return { type = "pow", base = base, exp = exp } end
function ast_raw(str) return { type = "raw", value = str } end


-- Sets a metatable for all AST nodes to provide a __tostring method.
-- This allows for a clean print(ast) output.
local ast_mt = {
  __tostring = function(self)
    if _G.ast_tostring then
      return _G.ast_tostring(self)
    elseif _G.simplify and _G.simplify.pretty_print then
      return _G.simplify.pretty_print(self)
    else
      return "[AST]"
    end
  end
}
-- Patches constructors to apply the metatable to all AST nodes.
local function set_ast_mt(node)
  if type(node) == "table" and node.type and getmetatable(node) ~= ast_mt then
    setmetatable(node, ast_mt)
    -- Recursively set for children
    if node.args then
      for _, v in ipairs(node.args) do set_ast_mt(v) end
    end
    if node.left then set_ast_mt(node.left) end
    if node.right then set_ast_mt(node.right) end
    if node.base then set_ast_mt(node.base) end
    if node.exp then set_ast_mt(node.exp) end
    if node.value and type(node.value) == "table" then set_ast_mt(node.value) end
    -- Patch matrix rows if present
    if node.rows then
      for _, row in ipairs(node.rows) do
        for i, cell in ipairs(row) do
          row[i] = set_ast_mt(cell)
        end
      end
    end
  end
  return node
end

function ast_matrix(rows)
  return set_ast_mt({ type = "matrix", rows = rows })
end

-- Creates a deep copy of an AST.
function ast_deepcopy(obj)
    if type(obj) ~= "table" then return obj end
    local res = {}
    for k, v in pairs(obj) do
        res[k] = ast_deepcopy(v)
    end
    return res
end

-- Performs a structural equality check for two ASTs.
function ast_equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not ast_equal(v, b[k]) then return false end
    end
    for k, v in pairs(b) do
        if not ast_equal(v, a[k]) then return false end
    end
    return true
end

-- Depth-first traversal of the AST, applying a function to every node.
function ast_traverse(ast, fn)
    fn(ast)
    if type(ast) == "table" then
        if ast.type == "add" or ast.type == "mul" or ast.type == "func" then
            for _, v in ipairs(ast.args) do
                ast_traverse(v, fn)
            end
        else
            for k, v in pairs(ast) do
                if type(v) == "table" then ast_traverse(v, fn) end
            end
        end
    end
end

-- Traverses and returns a new, transformed AST.
function ast_map(ast, fn)
    if type(ast) ~= "table" then return fn(ast) end
    local mapped = {}
    if ast.type == "add" or ast.type == "mul" or ast.type == "func" then
        mapped.type = ast.type
        mapped.args = {}
        if ast.name then mapped.name = ast.name end
        for i, v in ipairs(ast.args) do
            mapped.args[i] = ast_map(v, fn)
        end
    else
        for k, v in pairs(ast) do
            mapped[k] = ast_map(v, fn)
        end
    end
    return fn(mapped)
end

-- Replaces all occurrences of a target subtree with a replacement subtree.
function ast_substitute(ast, target, replacement)
    if ast_equal(ast, target) then return ast_deepcopy(replacement) end
    if type(ast) ~= "table" then return ast end
    local res = {}
    if ast.type == "add" or ast.type == "mul" or ast.type == "func" then
        res.type = ast.type
        if ast.name then res.name = ast.name end
        res.args = {}
        for i, v in ipairs(ast.args) do
            res.args[i] = ast_substitute(v, target, replacement)
        end
    else
        for k, v in pairs(ast) do
            res[k] = ast_substitute(v, target, replacement)
        end
    end
    return res
end

-- Collects all unique variable symbols in the AST.
function ast_vars(ast, found)
    found = found or {}
    if type(ast) ~= "table" then return found end
    if ast.type == "variable" then found[ast.name] = true end
    if ast.type == "add" or ast.type == "mul" or ast.type == "func" then
        for _, v in ipairs(ast.args) do
            ast_vars(v, found)
        end
    else
        for k, v in pairs(ast) do
            ast_vars(v, found)
        end
    end
    return found
end

-- Counts the total number of nodes in an AST.
function ast_size(ast)
    if type(ast) ~= "table" then return 1 end
    local sum = 1
    if ast.type == "add" or ast.type == "mul" or ast.type == "func" then
        for _, v in ipairs(ast.args) do sum = sum + ast_size(v) end
    else
        for k, v in pairs(ast) do sum = sum + ast_size(v) end
    end
    return sum
end

-- Computes the maximum depth of the AST.
function ast_depth(ast)
    if type(ast) ~= "table" then return 0 end
    local maxd = 0
    if ast.type == "add" or ast.type == "mul" or ast.type == "func" then
        for _, v in ipairs(ast.args) do
            local d = ast_depth(v)
            if d > maxd then maxd = d end
        end
    else
        for k, v in pairs(ast) do
            local d = ast_depth(v)
            if d > maxd then maxd = d end
        end
    end
    return 1 + maxd
end


-- Original raw AST-to-string printer, primarily for debugging purposes.
function ast_tostring_raw(ast)
    if type(ast) ~= "table" then return tostring(ast) end
    if ast.type == "number" then return tostring(ast.value) end
    if ast.type == "variable" then return ast.name end
    if ast.type == "func" then
        local args = {}
        for i, v in ipairs(ast.args) do args[i] = ast_tostring_raw(v) end
        return ast.name .. "(" .. table.concat(args, ",") .. ")"
    end
    if ast.type == "neg" then
        return "-(" .. ast_tostring_raw(ast.arg) .. ")"
    end
    if ast.type == "pow" then
        return "(" .. ast_tostring_raw(ast.base) .. ")^(" .. ast_tostring_raw(ast.exp) .. ")"
    end
    if ast.type == "add" then
        local parts = {}
        for i, v in ipairs(ast.args) do
            parts[i] = ast_tostring_raw(v)
        end
        return "(" .. table.concat(parts, " + ") .. ")"
    end
    if ast.type == "sub" then
        return "(" .. ast_tostring_raw(ast.left) .. ") - (" .. ast_tostring_raw(ast.right) .. ")"
    end
    if ast.type == "mul" then
        local parts = {}
        for i, v in ipairs(ast.args) do
            parts[i] = ast_tostring_raw(v)
        end
        -- Special formatting for 2x and x2 for readability.
        if #parts == 2 then
            local a, b = ast.args[1], ast.args[2]
            if ast_is_number(a) and ast_is_variable(b) then
                return tostring(a.value) .. parts[2]
            elseif ast_is_variable(a) and ast_is_number(b) then
                return parts[1] .. tostring(b.value)
            end
        end
        return table.concat(parts, "*")
    end
    if ast.type == "div" then
        return "(" .. ast_tostring_raw(ast.left) .. ")/(" .. ast_tostring_raw(ast.right) .. ")"
    end
    if ast.type == "raw" then
        return "[RAW:" .. tostring(ast.value) .. "]"
    end
    -- fallback
    local str = "{" .. (ast.type or "?")
    for k, v in pairs(ast) do
        if k ~= "type" then str = str .. "," .. k .. "=" .. ast_tostring_raw(v) end
    end
    return str .. "}"
end

-- AST node type test helper functions.
function ast_is_number(node)
    return type(node) == "table" and node.type == "number"
end
function ast_is_variable(node)
    return type(node) == "table" and node.type == "variable"
end
function ast_is_func(node, fname)
    return type(node) == "table" and node.type == "func" and (not fname or node.name == fname)
end
function ast_is_op(node, op)
    return type(node) == "table" and node.type == op
end


-- Evaluates the AST numerically if all nodes are numbers or supported functions.
function ast_eval_numeric(ast, env)
    env = env or {}
    if ast.type == "number" then return ast.value end
    if ast.type == "variable" then
        return env[ast.name] or error("Unbound variable: " .. tostring(ast.name))
    end
    if ast.type == "func" then
        local argv = {}
        for i, v in ipairs(ast.args) do
            argv[i] = ast_eval_numeric(v, env)
        end
        if math[ast.name] then
            return math[ast.name](table.unpack(argv))
        elseif ast.name == "ln" then
            return math.log(argv[1])
        elseif ast.name == "log" then
            return math.log10(argv[1])
        elseif ast.name == "gamma" then
            local n = argv[1]
            if n > 0 and math.floor(n) == n then
                local factorial = 1
                for i = 1, n - 1 do
                    factorial = factorial * i
                end
                return factorial
            elseif n == 0.5 then
                return math.sqrt(math.pi)
            else
                error("Gamma function not implemented for value: " .. tostring(n))
            end
        else
            error("Unknown function: " .. ast.name)
        end
    end
    if ast.type == "add" then
        local sum = 0
        for _, v in ipairs(ast.args) do
            sum = sum + ast_eval_numeric(v, env)
        end
        return sum
    end
    if ast.type == "sub" then
        return ast_eval_numeric(ast.left, env) - ast_eval_numeric(ast.right, env)
    end
    if ast.type == "mul" then
        local prod = 1
        for _, v in ipairs(ast.args) do
            prod = prod * ast_eval_numeric(v, env)
        end
        return prod
    end
    if ast.type == "div" then
        return ast_eval_numeric(ast.left, env) / ast_eval_numeric(ast.right, env)
    end
    if ast.type == "pow" then
        return ast_eval_numeric(ast.base, env) ^ ast_eval_numeric(ast.exp, env)
    end
    if ast.type == "neg" then
        return -ast_eval_numeric(ast.arg, env)
    end
    error("Unsupported node in ast_eval_numeric: " .. tostring(ast.type))
end

-- Pattern matching against an AST, binding variables as it goes.
function ast_match(pattern, ast, bindings)
    bindings = bindings or {}
    if type(pattern) ~= "table" then
        if pattern == ast then return bindings else return nil end
    end
    if pattern.var then
        if bindings[pattern.var] then
            return ast_equal(bindings[pattern.var], ast) and bindings or nil
        else
            bindings[pattern.var] = ast
            return bindings
        end
    end
    if type(ast) ~= "table" then return nil end
    if pattern.type and pattern.type ~= ast.type then return nil end
    if (pattern.type == "add" or pattern.type == "mul" or pattern.type == "func") and pattern.args then
        if #pattern.args ~= #ast.args then return nil end
        for i = 1, #pattern.args do
            local sub = ast_match(pattern.args[i], ast.args[i], bindings)
            if not sub then return nil end
            bindings = sub
        end
    else
        for k, v in pairs(pattern) do
            if k ~= "var" and k ~= "args" then
                local sub = ast_match(v, ast[k], bindings)
                if not sub then return nil end
                bindings = sub
            end
        end
    end
    return bindings
end

-- Export all functions into a single 'ast' table.
ast = {
    number = ast_number,
    symbol = ast_symbol,
    variable = ast_symbol,
    func = ast_func,
    binop = ast_binop,
    neg = ast_neg,
    pow = ast_pow,
    raw = ast_raw,
    matrix = ast_matrix,

    -- Shorthand binary operation constructors
    add = function(...) return { type = "add", args = {...} } end,
    sub = function(l, r) return ast_binop("sub", l, r) end,
    mul = function(...) return { type = "mul", args = {...} } end,
    div = function(l, r) return ast_binop("div", l, r) end,
    pow = function(l, r) return ast_pow(l, r) end,
    neg = ast_neg,
    eq = function(left, right) return { type = "equation", left = left, right = right } end,

    deepcopy = ast_deepcopy,
    equal = ast_equal,
    traverse = ast_traverse,
    map = ast_map,
    substitute = ast_substitute,
    vars = ast_vars,
    size = ast_size,
    depth = ast_depth,
    tostring = ast_tostring,

    is_number = ast_is_number,
    is_variable = ast_is_variable,
    is_func = ast_is_func,
    is_op = ast_is_op,

    eval_numeric = ast_eval_numeric,
    match = ast_match,
    debug_print = ast_debug_print,
}

-- Flattens nested additive or multiplicative trees for canonicalization.
function ast_flatten_add(node)
    if not ast_is_op(node, "add") then return { node } end
    local parts = {}
    local function collect(n)
        if ast_is_op(n, "add") then
            for _, v in ipairs(n.args) do
                collect(v)
            end
        else
            table.insert(parts, n)
        end
    end
    collect(node)
    table.sort(parts, function(a, b) return ast_tostring(a) < ast_tostring(b) end)
    return parts
end

-- Flattens nested multiplicative trees for canonicalization.
function ast_flatten_mul(node)
    if not ast_is_op(node, "mul") then return { node } end
    local parts = {}
    local function collect(n)
        if ast_is_op(n, "mul") then
            for _, v in ipairs(n.args) do
                collect(v)
            end
        else
            table.insert(parts, n)
        end
    end
    collect(node)
    table.sort(parts, function(a, b) return ast_tostring(a) < ast_tostring(b) end)
    return parts
end

ast.flatten_add = ast_flatten_add
ast.flatten_mul = ast_flatten_mul

-- Generic AST node constructor.
function ast_node(typ, opts)
    local node = { type = typ }
    for k, v in pairs(opts or {}) do
        node[k] = v
    end
    return node
end
ast.node = ast_node
_G.ast_node = ast.node
_G.ast = ast






-- Wildcard pattern constructor for pattern matching.
function ast_wildcard(varname)
    return { var = varname }
end
ast.wildcard = ast_wildcard
_G.wildcard = ast_wildcard

_G.ast_debug_print = ast_debug_print


-- Patch ast.eval_numeric to support physics functions and avoid cyclic load errors.
do
  local old_eval_numeric = ast.eval_numeric

  function ast.eval_numeric(node, env)
    env = env or {}
    -- Lazy-load physics module to break cyclic dependency
    local physics = _G.physics or require("physics")

    if node.type == "func" then
      local args_eval = {}
      for i, arg in ipairs(node.args) do
        args_eval[i] = ast.eval_numeric(arg, env)
      end

      if math[node.name] then
        return math[node.name](table.unpack(args_eval))
      end

      if node.name == "ln" then return math.log(args_eval[1]) end
      if node.name == "log" then return math.log10(args_eval[1]) end
      if node.name == "gamma" then
        local n = args_eval[1]
        if n > 0 and math.floor(n) == n then
          local fact = 1
          for i = 1, n - 1 do fact = fact * i end
          return fact
        elseif n == 0.5 then
          return math.sqrt(math.pi)
        else
          error("Gamma function not implemented for value: " .. tostring(n))
        end
      end

      -- Delegate to physics evaluation if available
      local phys_val = physics.eval_physics_func(node.name, node.args)
      if phys_val ~= nil then
        return ast.eval_numeric(phys_val, env)
      end

      error("Unknown function: " .. tostring(node.name))
    else
      return old_eval_numeric(node, env)
    end
  end

  ast.eval_numeric = ast.eval_numeric
end