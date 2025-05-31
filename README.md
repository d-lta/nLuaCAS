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
# nLuaCAS - Symbolic Calculus Engine for TI-Nspire CX

**nLuaCAS** is a symbolic math engine built in Lua for TI-Nspire calculators. Designed for educational purposes, it enables symbolic differentiation, integration, simplification, and solving — all without requiring Ndless.

> ⚠️ This tool is meant for learning and exploration. Do not use during assessments unless explicitly allowed.

## ✨ Features

- **Symbolic Differentiation** — Basic, higher-order, partial, and chain rule support.
- **Symbolic Integration** — Indefinite and definite integrals with rules for polynomials and trig.
- **Simplification** — Combine like terms, expand binomials, reduce expressions.
- **Equation Solving** — Solve linear, quadratic, and some cubic equations symbolically.
- **Function Memory** — Define and reuse functions (e.g., `let f(x) = x^2 + 1`).
- **Pretty Output** — Clean rendering of fractions, exponents, and symbols.
- **History + Help** — Tabs for prior computations and examples.
- **Dark Mode** — Customizable appearance with persistent mode memory.
- **No Ndless Required** — Fully compatible with TI-Nspire CX II and CX.

## 🖥 How to Use

Transfer `nLuaCAS.tns` to your calculator using TI-Nspire Link Software or [nLink](https://github.com/ndless-nspire/nlink).

### Input Examples

| Action               | Example                    |
|----------------------|----------------------------|
| Derivative           | `d/dx(x^2)`                |
| Integral             | `int(x^2)` or `∫(x^2)dx`   |
| Definite Integral    | `int(x^2, 0, 1)`           |
| Solve Equation       | `solve(x^2 - 4 = 0)`       |
| Simplify Expression  | `simplify(x + x)`          |
| Function Definition  | `let f(x) = x^2 + 3`       |
| Function Evaluation  | `f(2)`                     |

Use `TAB` to switch views: Main ↔ History ↔ About ↔ Help.

## ✅ Compatibility

- ✅ Tested on **TI-Nspire CX II** (OS 6.2)
- ✅ Compatible with **TI-Nspire CX** (may have minor UI limitations)
- ❌ Not for monochrome models
- ❌ Does not require Ndless or OS modification

## 🔐 Legal & Usage

This is a **community-made** educational tool and is **not affiliated with or endorsed by Texas Instruments**. All functionality is implemented via the official Lua scripting API provided by TI.

- You are responsible for how and where this tool is used.
- Do not use in exam settings unless explicitly allowed.
- No TI firmware, OS files, or proprietary assets are included.

## 📦 License

MIT License

## 🙏 Credits

Built by [@DeltaDev] with help from the open calculator dev community ❤️