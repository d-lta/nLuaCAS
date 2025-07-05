local ast = _G.ast or error("AST module required")

local Tensor = {}
Tensor.__index = Tensor


-- Get shape of nested table recursively
local function get_shape(data)
  local shape = {}
  local cur = data
  while type(cur) == "table" do
    table.insert(shape, #cur)
    cur = cur[1]
  end
  return shape
end

-- Validate shape uniformity recursively
local function validate_shape(data, shape, level)
  level = level or 1
  if level > #shape then return true end
  if type(data) ~= "table" or #data ~= shape[level] then
    error("Shape mismatch at level "..level)
  end
  for _, v in ipairs(data) do
    validate_shape(v, shape, level + 1)
  end
end

-- Deep copy nested table
local function deep_copy(data)
  if type(data) ~= "table" then return data end
  local copy = {}
  for k,v in pairs(data) do
    copy[k] = deep_copy(v)
  end
  return copy
end

-- Recursive map over two tensors elementwise
local function map_recursive(t1_data, t2_data, fn, level, shape)
  if level > #shape then
    return fn(t1_data, t2_data)
  end
  local res = {}
  for i = 1, shape[level] do
    res[i] = map_recursive(t1_data[i], t2_data[i], fn, level + 1, shape)
  end
  return res
end

-- Recursive eval_numeric on nested data
local function eval_recursive(data, env)
  if type(data) ~= "table" then
    return ast.eval_numeric(data, env)
  end
  local res = {}
  for i, v in ipairs(data) do
    res[i] = eval_recursive(v, env)
  end
  return res
end

-- Recursive function to permute axes of nested tensor data
local function transpose_recursive(data, perm, level, old_shape)
  level = level or 1
  if level > #perm then
    return data
  end

  local new_dim_size = old_shape[perm[level]]
  local res = {}
  for i = 1, new_dim_size do
    -- Gather slice along axis perm[level]
    local function get_sliced(data, indices, cur_level)
      if cur_level > #perm then
        return data
      end
      local idx = indices[cur_level]
      return get_sliced(data[idx], indices, cur_level + 1)
    end

    -- Build indices array for recursive calls
    local function build_indices(level, fixed_index)
      if level > #perm then return {} end
      if level == level then
        local rest = build_indices(level + 1, fixed_index)
        table.insert(rest, 1, fixed_index)
        return rest
      else
        -- Return range over dimension (hacky, but for full transpose you need full iterator)
        local arr = {}
        for j=1, old_shape[perm[level]] do
          arr[j] = j
        end
        return arr
      end
    end

    -- Because full implementation is complicated, do a simpler approach:
    -- We'll transpose by swapping axes by recursively re-indexing
    -- For now, we'll leave this stubbed, returning data as-is (TODO)

    res[i] = data -- TODO: Implement full permutation
  end
  return res
end

-- Function to get value from nested tensor data by index array
local function get_element(data, indices)
  local cur = data
  for _, idx in ipairs(indices) do
    cur = cur[idx]
  end
  return cur
end

-- Function to set value in nested tensor data by index array
local function set_element(data, indices, value)
  local cur = data
  for i = 1, #indices - 1 do
    cur = cur[indices[i]]
  end
  cur[indices[#indices]] = value
end

-- Utility to generate all index tuples for given shape
local function index_iterator(shape)
  local indices = {}
  for i=1,#shape do indices[i] = 1 end

  return function()
    if not indices then return nil end
    local result = {table.unpack(indices)}
    -- increment indices
    for i = #indices, 1, -1 do
      indices[i] = indices[i] + 1
      if indices[i] > shape[i] then
        if i == 1 then
          indices = nil
          break
        else
          indices[i] = 1
        end
      else
        break
      end
    end
    return result
  end
end

-- Tensor constructor
function Tensor.new(data)
  assert(type(data) == "table", "Tensor must be constructed from nested table")
  local shape = get_shape(data)
  validate_shape(data, shape)
  local function wrap_numbers(d)
    if type(d) ~= "table" then
      if type(d) == "number" then
        return { type = "number", value = d }
      else
        return d
      end
    end
    local res = {}
    for k, v in pairs(d) do
      res[k] = wrap_numbers(v)
    end
    return res
  end

  local wrapped_data = wrap_numbers(data)
  return setmetatable({ type = "tensor", data = wrapped_data, shape = shape }, Tensor)
end

function Tensor:eval_numeric(env)
  return eval_recursive(self.data, env)
end

function Tensor:add(other)
  assert(#self.shape == #other.shape, "Shape rank mismatch for addition")
  for i=1,#self.shape do
    assert(self.shape[i] == other.shape[i], "Shape dimension mismatch for addition")
  end
  local res_data = map_recursive(self.data, other.data, ast.add, 1, self.shape)
  return Tensor.new(res_data)
end

function Tensor:mul(other)
  assert(#self.shape == #other.shape, "Shape rank mismatch for multiplication")
  for i=1,#self.shape do
    assert(self.shape[i] == other.shape[i], "Shape dimension mismatch for multiplication")
  end
  local res_data = map_recursive(self.data, other.data, ast.mul, 1, self.shape)
  local res_tensor = Tensor.new(res_data)
  return Tensor.new(res_tensor:eval_numeric({}))
end

-- Generalized transpose (permute axes)
function Tensor:transpose(perm)
  perm = perm or {}
  local rank = #self.shape
  if #perm == 0 then
    -- default reverse axes
    for i=rank,1,-1 do table.insert(perm, i) end
  end
  assert(#perm == rank, "Permutation length must equal tensor rank")
  local new_shape = {}
  for i=1, rank do
    new_shape[i] = self.shape[perm[i]]
  end

  -- TODO: full transpose requires complex recursive reindexing
  -- for now, stub to just return self, but shape updated
  -- WARNING: This won't actually rearrange data correctly
  return Tensor.new(deep_copy(self.data)) -- TODO: fix data permuting
end

-- Tensor contraction over specified axes
-- axes1 and axes2 are arrays of axis indices in self and other respectively to contract over
function Tensor:contract(other, axes1, axes2)
  assert(#axes1 == #axes2, "Must contract same number of axes")

  local rank1 = #self.shape
  local rank2 = #other.shape

  -- Validate axes
  for i=1,#axes1 do
    assert(axes1[i] >=1 and axes1[i] <= rank1, "axes1 out of range")
    assert(axes2[i] >=1 and axes2[i] <= rank2, "axes2 out of range")
    assert(self.shape[axes1[i]] == other.shape[axes2[i]], "Dimension mismatch for contraction axes")
  end

  -- Result shape is all axes of self not in axes1 + all axes of other not in axes2
  local result_shape = {}
  local used_axes1 = {}
  for _, a in ipairs(axes1) do used_axes1[a] = true end
  for i=1, rank1 do
    if not used_axes1[i] then table.insert(result_shape, self.shape[i]) end
  end
  local used_axes2 = {}
  for _, a in ipairs(axes2) do used_axes2[a] = true end
  for i=1, rank2 do
    if not used_axes2[i] then table.insert(result_shape, other.shape[i]) end
  end

  -- Helper to get index mapping
  local function build_indices(base_indices, shape, exclude_axes)
    local indices = {}
    local skip = {}
    for _, e in ipairs(exclude_axes) do skip[e] = true end
    local idx = 1
    for i=1,#shape do
      if not skip[i] then
        indices[idx] = base_indices[i]
        idx = idx + 1
      end
    end
    return indices
  end

  -- All indices iterator for given shape
  local function iter_indices(shape)
    local idxs = {}
    for i=1,#shape do idxs[i] = 1 end
    return function()
      if not idxs then return nil end
      local ret = {table.unpack(idxs)}
      for i=#idxs,1,-1 do
        idxs[i] = idxs[i] + 1
        if idxs[i] > shape[i] then
          if i == 1 then idxs = nil break end
          idxs[i] = 1
        else
          break
        end
      end
      return ret
    end
  end

  -- Indices for contracted axes shape
  local contract_shape = {}
  for i=1,#axes1 do
    table.insert(contract_shape, self.shape[axes1[i]])
  end

  -- Indices for non-contracted axes in self
  local non_contract_shape1 = {}
  local non_contract_axes1 = {}
  for i=1, rank1 do
    if not used_axes1[i] then
      table.insert(non_contract_shape1, self.shape[i])
      table.insert(non_contract_axes1, i)
    end
  end

  -- Indices for non-contracted axes in other
  local non_contract_shape2 = {}
  local non_contract_axes2 = {}
  for i=1, rank2 do
    if not used_axes2[i] then
      table.insert(non_contract_shape2, other.shape[i])
      table.insert(non_contract_axes2, i)
    end
  end

  local contract_iter = iter_indices(contract_shape)
  local non_contract_iter1 = iter_indices(non_contract_shape1)
  local non_contract_iter2 = iter_indices(non_contract_shape2)

  -- Create zero-initialized nested table for result
  local function create_nested_table(shape, level)
    if level > #shape then return ast.number(0) end
    local t = {}
    for i=1, shape[level] do
      t[i] = create_nested_table(shape, level + 1)
    end
    return t
  end

  local result_data = create_nested_table(result_shape, 1)

  -- Main contraction loop
  -- Iterate over all non contracted indices of self and other, then sum over contracted axes
  local idx1 = non_contract_iter1()
  while idx1 do
    local idx2 = non_contract_iter2()
    while idx2 do
      local sum = nil
      local contract_idx = iter_indices(contract_shape)()
      while contract_idx do
        -- Build full indices for self and other
        local full_idx_self = {}
        for i=1, rank1 do
          if used_axes1[i] then
            -- contracted axis, find position in axes1 to get index
            for pos, ax in ipairs(axes1) do
              if ax == i then full_idx_self[i] = contract_idx[pos] break end
            end
          else
            -- find position in non_contract_axes1
            for pos2, ax2 in ipairs(non_contract_axes1) do
              if ax2 == i then
                full_idx_self[i] = idx1[pos2]
                break
              end
            end
          end
        end
        local full_idx_other = {}
        for i=1, rank2 do
          if used_axes2[i] then
            for pos, ax in ipairs(axes2) do
              if ax == i then full_idx_other[i] = contract_idx[pos] break end
            end
          else
            for pos2, ax2 in ipairs(non_contract_axes2) do
              if ax2 == i then
                full_idx_other[i] = idx2[pos2]
                break
              end
            end
          end
        end
        -- Fetch elements
        local val1 = get_element(self.data, full_idx_self)
        local val2 = get_element(other.data, full_idx_other)
        local mul_val = ast.mul(val1, val2)
        if sum == nil then sum = mul_val else sum = ast.add(sum, mul_val) end
        contract_idx = iter_indices(contract_shape)()
      end
      -- Set result element
      local res_idx = {}
      for _, v in ipairs(idx1) do table.insert(res_idx, v) end
      for _, v in ipairs(idx2) do table.insert(res_idx, v) end
      set_element(result_data, res_idx, sum)
      idx2 = non_contract_iter2()
    end
    idx1 = non_contract_iter1()
  end

  return Tensor.new(result_data)
end

-- Default tensor multiplication: contract last axis of self with first axis of other
function Tensor:tensor_multiply(other)
  -- Default tensor multiplication contracts last axis of self with first axis of other
  local axes1 = { #self.shape }
  local axes2 = { 1 }
  return self:contract(other, axes1, axes2)
end

_G.Tensor = Tensor

-- Hook for AST simplifier to use for tensor multiplication
-- (This is not strictly needed here, but for clarity in patch context)
