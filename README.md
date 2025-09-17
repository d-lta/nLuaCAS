# nLuaCAS

A symbolic math engine for TI-Nspire CX (non-CAS models), written in Lua.

![nLuaCAS for Dark Mode](https://github.com/user-attachments/assets/4864dcbe-9734-49ab-9f9b-ce416bb81f36#gh-dark-mode-only)
![nLuaCAS for Light Mode](https://github.com/user-attachments/assets/9afb1f0a-9372-4887-91d8-3c445a32b1c8#gh-light-mode-only)

This runs entirely in native Lua without requiring Ndless or OS patches. It parses expressions into ASTs, applies symbolic transformations, and outputs readable results.

![image2](https://github.com/user-attachments/assets/13fb7b85-52d2-46fb-857c-b977ed7a453b)

> Educational tool. Check your institution's assessment policies before use.

## Installation

1. Download `nLuaCAS.tns`
2. Transfer to calculator using TI-Nspire Link or [nLink](https://lights0123.com/n-link/)
3. Open from Documents screen
4. Use TAB to navigate between Main, History, Help tabs

## Usage Examples

| Operation | Input | Output |
|-----------|-------|--------|
| Derivative | `d/dx(x^2)` | `2x` |
| Integration | `int(x^2)` | `x^3/3` |
| Definite integral | `int(x^2, 0, 1)` | `1/3` |
| Equation solving | `solve(x^2 - 4 = 0)` | `x = ±2` |
| Simplification | `simplify(x + x)` | `2x` |
| Function definition | `let f(x) = x^2 + 3` | - |
| Function evaluation | `f(2)` | `7` |

New features:
- `series()` for Taylor/Maclaurin expansions
- Enhanced `int()` with integration by parts
- Step-by-step explanations (look for "Explain" button)

## Features

**Arithmetic & Algebra**
- Basic operations: `2 + 3` → `5`, `x * x^2` → `x^3`
- Power simplification: `(x^2)^3` → `x^6`
- Binomial expansion: `(a + b)^n` (up to n=4)

**Calculus**
- Derivatives of polynomials, trig, exponential, log functions
- Symbolic integration (basic cases)
- Chain rule support (partial)

**Trigonometry**
- Identity simplification: `sin^2(x) + cos^2(x)` → `1`
- Sign properties: `sin(-x)` → `-sin(x)`

**Logarithms**
- Product rule: `log(a*b)` → `log(a) + log(b)`
- Power rule: `log(a^b)` → `b*log(a)`

**Rational expressions**
- Cancellation: `x/x` → `1`
- Cross-cancellation: `(a*b)/(b*c)` → `a/c`

**Factorials**
- Exact values for integers
- Symbolic simplification: `x!/(x-1)!` → `x`
- Gamma function for non-integers

## Compatibility

- ✅ TI-Nspire CX II (OS 6.2) - tested
- ✅ TI-Nspire CX (non-CAS) - supported
- ❌ Monochrome models - unsupported
- ❌ Ndless - not required

## Build System

TI-Nspire Lua executes single `.tns` files only. The build script merges all source files:

```bash
./build.sh
```

This creates `build.lua` which you can either:
- Copy into TI Lua editor, or  
- Compile to `.tns` using [Luna](https://github.com/tangrs/luna)

## Architecture

**Parser** - Converts input strings to AST representation:
```lua
{type="add", args={
  {type="pow", base={type="variable", name="x"}, exp={type="number", value=2}},
  {type="mul", args={{type="number", value=2}, {type="variable", name="x"}}}
}}
```

**Simplifier** - Multi-pass rule engine operating on ASTs. Handles canonicalization, algebraic reductions, and identity applications.

**Differentiator** - Takes AST and variable name, produces derivative AST. Supports polynomial, trigonometric, exponential, and logarithmic functions.

**Pretty Printer** - Renders AST back to readable math notation.

Data flow:
```
String → Parser → AST → Simplifier → AST → Pretty Printer → String
```

## What's Missing

- Integration still unreliable
- Advanced chain rule support
- Partial derivatives
- More sophisticated equation solving

## Credits

Engine and AST system by d-lta. UI framework adapted from SuperSpire (S²) by Xavier Andréani. Build system concept from Adriweb. Menu concepts from khicas project.

Licensed under MIT. No TI proprietary code used.
