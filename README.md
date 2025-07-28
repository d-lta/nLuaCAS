# [WIP] nLuaCAS – Symbolic Calculus Engine for TI-Nspire CX
![nLuaCAS for Dark Mode](https://github.com/user-attachments/assets/4864dcbe-9734-49ab-9f9b-ce416bb81f36#gh-dark-mode-only)
![nLuaCAS for Light Mode](https://github.com/user-attachments/assets/9afb1f0a-9372-4887-91d8-3c445a32b1c8#gh-light-mode-only)

A symbolic mathematics engine for the TI-Nspire CX (non-CAS models), written entirely in Lua. No Ndless, no OS patches — just native capabilities repurposed for symbolic algebra.
![image2](https://github.com/user-attachments/assets/13fb7b85-52d2-46fb-857c-b977ed7a453b)


> Educational tool. Use during assessments only if explicitly permitted.

---

## Overview

`nLuaCAS` enables symbolic operations — differentiation, simplification, and integration — on TI-Nspire CX calculators that were never meant to support them. It parses mathematical expressions, transforms them via a custom AST engine, and prints the result as readable output.

Beyond just providing answers, `nLuaCAS` can now **show its work**. For complex operations like integration by parts, a step-by-step explanation dialog breaks down the solution, turning a black box calculation into a valuable learning tool.
---

## How to Use

1.  **Transfer** `nLuaCAS.tns` to your calculator using TI-Nspire Link or [nLink](https://lights0123.com/n-link/).
2.  **Open** it from the Documents screen.
3.  **Type** expressions in the Main tab.
4.  **Switch** tabs using `TAB` — History, Help, etc.
5.  Look for an "Explain" button next to certain results to see a step-by-step breakdown.

> New commands available: `series()` for series expansions and enhanced `int()` supporting integration by parts with detailed explanations.


---

## Step-by-Step Explanations

To make `nLuaCAS` a more effective educational tool, an explanation engine has been implemented to demystify the solution process for certain functions. Instead of just returning a final answer, the engine can now generate a human-readable, step-by-step breakdown of the method used.

This is powered by an internal `add_step()` mechanism that hooks into the symbolic transformation pipeline. As the engine performs a significant action (like choosing $u$ and $dv$ for integration by parts), it logs that action as a descriptive step.

**Currently Supported Explanations:**

* **Derivative Explanations:** Details the process of finding derivatives.
* **Equation Solving :** Details the process of solving equations up to quartic.
![About](https://github.com/user-attachments/assets/df9bc3ec-a7c5-485d-b919-e435adc88286)
### Example Inputs

| Operation             | Input                      |
|-----------------------|----------------------------|
| Derivative            | `d/dx(x^2)`                |
| Integral              | `int(x^2)` or `∫(x^2)dx`   |
| Definite Integral     | `int(x^2, 0, 1)`           |
| Solve Equation        | `solve(x^2 - 4 = 0)`       |
| Simplify Expression   | `simplify(x + x)`          |
| Function Definition   | `let f(x) = x^2 + 3`       |
| Function Evaluation   | `f(2)`                     |

---

## Supported Features

### Arithmetic & Algebra
- `2 + 3` → `5`
- `x * x^2` → `x^3`
- `(x^2)^3` → `x^6`
- `(a + b)^n` expanded up to `n = 4`

### Factorials
- Exact values for integers
- Simplifications like `x! / (x - 1)!` → `x`
- `factorial(x)` preserved symbolically
- Gamma approximation: `4.5!` → `gamma(5.5)` → number

### Trigonometry
- `sin^2(x) + cos^2(x)` → `1`
- `sin(-x)` → `-sin(x)`
- `cos(-x)` → `cos(x)`
- Partial support: `sin(a + b)`, `cos(a + b)`

### Logs & Exponentials
- `log(a * b)` → `log(a) + log(b)`
- `log(a^b)` → `b * log(a)`
- `exp(log(x))` → `x`

### Rational Expressions
- `x / x` → `1`
- `(a * b) / (b * c)` → `a / c`
- `x * x^(-1)` → `1`

### Derivatives
- `d/dx(x^2)` → `2x`
- Supports: sin, cos, e^x, log
- Partial chain rule support

### Series Expansions
- Generalized series expansions (Taylor, Maclaurin) with explanations.
- Support for symbolic center and variable.
- Uses Gamma function and factorial transformations for coefficients.

### Factorials and Gamma
- Extended factorial support via Gamma function.
- Lanczos approximation for factorial of complex and negative numbers.
- Symbolic factorial simplifications.
### Arithmetic & Algebra
- `2 + 3` → `5`
- `x * x^2` → `x^3`
- `(x^2)^3` → `x^6`
- `(a + b)^n` expanded up to `n = 4`

### Factorials
- Exact values for integers
- Simplifications like `x! / (x - 1)!` → `x`
- `factorial(x)` preserved symbolically
- Gamma approximation: `4.5!` → `gamma(5.5)` → number

### Trigonometry
- `sin^2(x) + cos^2(x)` → `1`
- `sin(-x)` → `-sin(x)`
- `cos(-x)` → `cos(x)`
- Partial support: `sin(a + b)`, `cos(a + b)`

### Logs & Exponentials
- `log(a * b)` → `log(a) + log(b)`
- `log(a^b)` → `b * log(a)`
- `exp(log(x))` → `x`

### Rational Expressions
- `x / x` → `1`
- `(a * b) / (b * c)` → `a / c`
- `x * x^(-1)` → `1`

### Derivatives
- `d/dx(x^2)` → `2x`
- Supports: sin, cos, e^x, log
- Partial chain rule support

### Integration
- Symbolic integration including integration by parts(rudimentary)

### Series Expansions
- Generalized series expansions (Taylor, Maclaurin)
- Support for symbolic center and variable
- Uses Gamma function and factorial transformations for coefficients

### Factorials and Gamma
- Extended factorial support via Gamma function
- Lanczos approximation for factorial of complex and negative numbers
- Symbolic factorial simplifications

---

## Not Yet Implemented

### Exact Engine
- Still WIP 
  
### Integration
- Still seems to only work sometimes
  
---

## Compatibility

- ✅ TI-Nspire CX II (OS 6.2) — tested
- ✅ TI-Nspire CX (non-CAS) — supported (minor UI quirks)
- ❌ Monochrome models — unsupported
- ❌ Ndless — not required

---

## Build System

TI-Nspire Lua does not support `require()` or multi-file project structures at runtime. It executes only the contents of a single `.tns` file — everything else is ignored.

To deal with this, `nLuaCAS` uses a lightweight build process:

1. `build.sh` merges all files in `src/` into a single `build.lua`
2. You deploy it via:

   - **Option A**: Copy `build.lua` into the TI Lua editor.
   - **Option B**: Use [Luna](https://github.com/tangrs/luna) to compile it into `.tns`  
     

```
./build.sh
```

Thanks to Adriweb for suggesting the build system strategy.

---

## Architecture Overview

This section describes how the system transforms input into structured output.
### Parser

- Converts raw input (e.g., `"x^2 + 2x"`) into an AST:
```lua
{type="add", args={
  {type="pow", base={type="variable", name="x"}, exp={type="number", value=2}},
  {type="mul", args={
    {type="number", value=2},
    {type="variable", name="x"}
  }}
}}
```
- Fixes:
  - `"power"` → `"pow"`
  - Symbolic variables as structured tables
  - Nested AST support for functions and derivatives

### Simplifier (`simplify.lua`)

- Multi-pass rule engine operating on ASTs
- Rules for `add`, `mul`, `pow`, `func`, etc.
- Supports:
  - Canonicalization and reordering
  - Factorials, gamma, trig/log identities
  - Algebraic reductions

Core functions:
- `simplify.simplify(expr)`
- `recursive_simplify(expr)`
- `pretty_print(expr)`

### Differentiator (`diff.lua`)

- Accepts AST and variable name
- Produces derivative AST
- Handles:
  - Polynomial forms
  - sin, cos, log, exp
  - Basic composition (`sin(x^2)`, etc.)
- Roadmap:
  - Advanced chain rule
  - Partial derivatives

### Expression Flattening

- Internal `flatten(node)` and `canonicalize(node)`  
  collapse and sort nested arithmetic trees

### Output / Display

- `pretty_print(expr)` renders AST to readable string
- Used in:
  - On-calc display
  - Debug
  - Round-tripping and re-simplification

---

## Data Flow

```
Raw Input String
        ↓
┌──────────────────┐
│     Parser       │
│ (string → AST)   │
└──────────────────┘
        ↓
┌──────────────────┐
│   Simplifier     │
│ (AST → reduced)  │
└──────────────────┘
        ↓
┌──────────────────┐
│ Pretty Printer   │
│ (AST → string)   │
└──────────────────┘
```

---
## More Screenshots
![07-28-2025 Image002](https://github.com/user-attachments/assets/1e60ca21-89b4-4c8b-94b5-4c29a0747bf2)
![07-28-2025 Image003](https://github.com/user-attachments/assets/dbe5c0e2-2d47-4951-8be6-9639f03d5cd4)

![About](https://github.com/user-attachments/assets/df9bc3ec-a7c5-485d-b919-e435adc88286)

## License & Attribution

- **Symbolic engine and transformation logic:**  
  © 2024 DeltaDev — MIT License

- **UI base adapted from:**  
  SuperSpire (S²) by Xavier Andréani  
  https://tipla.net/a29172  
  Licensed under CC BY-SA 2.0 FR

- **Menu elements and control concepts adapted from:**
  `khicas` by Bernard Parisse and the Giac/Xcas team. The robust menu interaction in `khicas` served as a valuable reference.

No TI firmware, OS binaries, or proprietary assets are used.
---

## Credits

In the spirit of open-source collaboration (and shameless pragmatism), this project stands on the shoulders of giants:

- **Engine, AST system, documentation** — [@DeltaDev](https://github.com/Delta-Dev-1)  
- **UI framework** — SuperSpire by Xavier Andréani  
- **Build system concept** — [Adriweb](https://github.com/adriwebs)  
- **Menu concepts & UI philosophy** — The `khicas` project, for demonstrating how a powerful CAS interface should feel.
- Developed with support from the open calculator ecosystem.
