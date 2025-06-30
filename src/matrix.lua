local ast = _G.ast or error("AST module required")

local Matrix = {}
Matrix.__index = Matrix

function Matrix:eval_numeric(env)
  local result = {}
  for i = 1, self.rows do
    result[i] = {}
    for j = 1, self.cols do
      result[i][j] = ast.eval_numeric(self.data[i][j], env)
    end
  end
  return result
end

function Matrix.new(data)
  assert(type(data) == "table", "Matrix must be constructed from a table")
  local rows = #data
  local cols = #data[1]
  for i = 2, rows do
    assert(#data[i] == cols, "Matrix rows must be same length")
  end
  return setmetatable({ type = "matrix", data = data, rows = rows, cols = cols }, Matrix)
end

function Matrix:tostring()
  local out = {}
  for i = 1, self.rows do
    local row = {}
    for j = 1, self.cols do
      table.insert(row, tostring(self.data[i][j]))
    end
    table.insert(out, "{" .. table.concat(row, ", ") .. "}")
  end
  return "[" .. table.concat(out, ",\n ") .. "]"
end

function Matrix:add(B)
  assert(self.rows == B.rows and self.cols == B.cols, "Shape mismatch")
  local result = {}
  for i = 1, self.rows do
    result[i] = {}
    for j = 1, self.cols do
      result[i][j] = ast.add(self.data[i][j], B.data[i][j])
    end
  end
  return Matrix.new(result)
end

function Matrix:mul(B)
  assert(self.cols == B.rows, "Incompatible dimensions")
  local result = {}
  for i = 1, self.rows do
    result[i] = {}
    for j = 1, B.cols do
      local sum = ast.number(0)
      for k = 1, self.cols do
        sum = ast.add(sum, ast.mul(self.data[i][k], B.data[k][j]))
      end
      result[i][j] = sum
    end
  end
  return Matrix.new(result)
end

function Matrix:transpose()
  local result = {}
  for i = 1, self.cols do
    result[i] = {}
    for j = 1, self.rows do
      result[i][j] = self.data[j][i]
    end
  end
  return Matrix.new(result)
end

function Matrix:determinant()
  assert(self.rows == 2 and self.cols == 2, "Only 2x2 determinant supported")
  local a, b = self.data[1][1], self.data[1][2]
  local c, d = self.data[2][1], self.data[2][2]
  return ast.sub(ast.mul(a, d), ast.mul(b, c))
end

function Matrix:inverse()
  local det = self:determinant()
  local a, b = self.data[1][1], self.data[1][2]
  local c, d = self.data[2][1], self.data[2][2]
  local inv = {
    {d, ast.mul(ast.number(-1), b)},
    {ast.mul(ast.number(-1), c), a}
  }
  local det_inv = ast.pow(det, ast.number(-1))
  for i = 1, 2 do
    for j = 1, 2 do
      inv[i][j] = ast.mul(inv[i][j], det_inv)
    end
  end
  return Matrix.new(inv)
end

_G.Matrix = Matrix