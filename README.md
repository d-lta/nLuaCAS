if not parseExpr then
  function parseExpr(expr)
    -- Dummy parser to prevent crash until real implementation
    return { type = "symbol", value = expr }
  end
end

-- Inside tokenizer or parser function handling identifiers:
if token.value == "sin" or token.value == "cos" or token.value == "tan" then
  local funcName = token.value
  nextToken() -- skip function name
  expect("(")
  local arg = parseExpr()
  expect(")")
  return { type = "func", name = funcName, arg = arg }
end

-- Inside evaluator function walking the AST:
if node.type == "func" then
  local arg = evaluate(node.arg)
  if node.name == "sin" then return math.sin(arg) end
  if node.name == "cos" then return math.cos(arg) end
  if node.name == "tan" then return math.tan(arg) end
end

-- In your parsing function, add handling for unmatched closing parentheses:
if token.value == ")" and not expectingClose then
  error("Unexpected closing parenthesis")
end

-- Before evaluation, for inputs ending with ')', validate full expression is parsed and parentheses are balanced.