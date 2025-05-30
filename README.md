# nLuaCAS - Symbolic Calculus Engine for TI-Nspire CX

**nLuaCAS** is a lightweight, high-performance symbolic math engine built entirely in Lua for the TI-Nspire CX and CX II calculators. It provides a rich set of calculus and algebra tools in a user-friendly, calculator-native UI.

🚧 This is a work-in-progress (WIP) project and may continue to evolve with features, refinements, and bug fixes.  
✅ Despite its lightweight design, **nLuaCAS qualifies as a functional Computer Algebra System (CAS)** — it performs symbolic manipulation including differentiation, integration, simplification, and solving, all on-device.

⚠️ This tool is for educational use only. It is not intended for exams or assessments unless explicitly permitted. Misuse may violate academic integrity policies.

---

## ✨ Features

- **Expression Simplification**  
  Like-term combining, power rules, expansion, and constant folding.

- **Symbolic Derivatives**  
  Supports standard, partial, higher-order, and chain rule differentiation.

- **Symbolic Integrals**  
  Indefinite and definite integrals, power rule, and common functions.

- **Equation Solving**  
  Supports linear, quadratic, and some cubic equations symbolically.

- **Pretty-Printed Output**  
  Fractions, powers, and symbols rendered in a human-friendly display.

- **History Navigation**  
  View past computations in the History tab.

- **Function Definition and Memory**  
  Define and evaluate user functions with `let f(x) = ...`.

- **Themed UI with Dark Mode**  
  Stylish, custom-themed interface that remembers your mode.

---

## 🖥 How to Use

### Input Formats

| Action | Example |
|--------|---------|
| Derivative | `d/dx(x^2)` |
| Partial Derivative | `∂/∂y(x^2 + y^2)` |
| Integral | `int(x^2)` or `∫(x^2)dx` |
| Definite Integral | `int(x^2, 0, 1)` |
| Solve Equation | `solve(x^2 = 4)` |
| Simplify Expression | `x^2 + 2x + 1` |
| Function Definition | `let f(x) = x^2 + 3` |
| Function Evaluation | `f(2)` |

> Autocomplete suggestions appear as you type, and pressing `Enter` evaluates the input. Press `Tab` to switch views (Main ↔ History ↔ About).

---

## 🧠 Installation

1. Install [TI-Nspire Computer Link Software](https://education.ti.com/en/products/computer-software/ti-nspire-cx-student-software).
2. Transfer the `nLuaCAS.tns` file to your TI-Nspire calculator.
3. Launch the app from My Documents.

---

## 💡 Notes

- Tested on **TI-Nspire CX II**, works across **CX** and **CX II** models.
- Does **not** require Ndless or OS modification.
- No internet access or OS modification required.
- Runs fully offline.

---

## ⚠️ Legal Notice

This project is **not affiliated with or endorsed by Texas Instruments**.  
All code is original and adheres to TI's SDK and Lua API guidelines.  
No TI firmware, OS, or proprietary assets are used or redistributed.

This repository and its author are not responsible for any misuse of this tool in academic settings. Use at your own discretion and in accordance with your school or exam policies.

## 📚 Educational Purpose

nLuaCAS is intended as a tool for learning, exploration, and conceptual understanding of symbolic mathematics. It is designed to support self-study and enrichment, particularly for students interested in calculus, algebra, and computer algebra systems.

⚠️ Please do **not** use this application in test or exam environments unless explicitly permitted by your instructor or institution. Unauthorized usage could breach academic integrity rules.

By using this software, you agree to use it responsibly and ethically.

This project is not designed to give unfair advantages — it is an educational enhancement, not a replacement for critical thinking or curriculum learning.

---

## 🧑‍💻 Credits

Made with ❤️ by [@DeltaDev]

---