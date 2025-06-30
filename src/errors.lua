-- errors.lua: handles sarcastic diagnostics for the criminally wrong

_G.errors = {}

_G.errors.custom = {
  ["simplify(human_emotion)"] = {
  "simplify(human_emotion): undefined behavior. Try numbing instead.",
  "expression too irrational. Can't simplify that.",
  "simplify(): emotions do not cancel out algebraically."
},

["solve(economy)"] = {
  "solution too volatile. Try again next fiscal cycle.",
  "solve(economy): infinite variables, zero stability.",
  "output is imaginary. So is the value of your currency."
},

["int(motivation)"] = {
  "area under the curve is... flat. Burnout detected.",
  "integrated result: exhaustion + C",
  "int(motivation): indefinite. Like your deadlines."
},

["diff(common_sense)"] = {
  "∂/∂x(common_sense) = 0. It’s a constant…ly missing.",
  "derivative undefined. Assumed extinct.",
  "diff(): nothing to differentiate. It was never there."
},

["subs(truth, society, propaganda)"] = {
  "truth replaced with propaganda. Output looks familiar.",
  "subs(): societal override complete. Result: fiction.",
  "did you mean: rationalize(disaster)?"
},

["solve(existence = absurdity)"] = {
  "solve(): contradiction detected. Camus would approve.",
  "equation tautological. Output is void.",
  "solution: undefined. Please consult your local philosopher."
},

["tokenize(entropy)"] = {
  "tokenize(): too much randomness. Try less chaos.",
  "failed to classify: input appears stochastic.",
  "token stream is melting. So is reality."
},

["parse(hope)"] = {
  "parser found optimism. Immediately rejected.",
  "hope is not a valid token.",
  "parse(): unexpected symbol. Are you dreaming again?"
},
  ["simplify(existence)"] = {
    "undefined. Like your weekend plans.",
    "simplify(existence): returns 'absurd'. Camus approves.",
    "Trying to simplify existence? Good luck with that."
  },
  ["solve(life)"] = {
    "solution not found. Try philosophy().",
    "solve(life): result is complex. No real solutions.",
    "solve(life): nice try. Meaning remains undefined."
  },
  ["diff(nothing)"] = {
    "finally, something you can't screw up.",
    "∂/∂nothing = nothing. Revolutionary.",
    "You differentiated nothing. Ambitious."
  },
  ["d/dx(nothing))"] = {
    "d/dx(nothing): you're trying too hard and also failing.",
    "diff(expr, var): both required. Unlike your faith in syntax.",
    "You wrote a fraction that looks like math. But isn't."
  },
  ["int(hopelessness)"] = {
    "integrated result: depression + C",
    "area under the curve? it's flatlining.",
    "hope cancelled. integration complete."
  },
  ["subs(sanity, reality, chaos)"] = {
    "sanity → chaos applied. welcome to symbolic algebra.",
    "substitution complete. your mind is now unstable.",
    "why did you do that? too late now."
  },
  ["gcd(404, not_found)"] = {
    "Missing operand. Or file.",
    "gcd error: inputs not located.",
    "check your gcd privileges."
  }
}

function _G.errors.get(key)
  local val = _G.errors.custom and _G.errors.custom[key]
  if type(val) == "table" then
    return val[math.random(#val)]
  else
    return val
  end
end

function _G.errors.invalid(fn, hint)
  local base = {
    simplify = {
      default = "simplify() expects an expression. Yours was... questionable.",
      type = "simplify(): expected expression, got a math-themed prank."
    },
    solve = {
      default = "solve() needs an equation. Not interpretive math dance.",
      missing_eq = "solve(): that’s not an equation. It’s a suggestion.",
      empty = "solve(): nothing to solve. Existential, huh?"
    },
    subs = {
      default = "subs(expr, var, val): you're missing something. Probably 'val'.",
      args = "subs(): three arguments please. This isn’t blackjack.",
      type = "subs(): expected AST, got a philosophical void."
    },
    int = {
      default = "int(expr) wants an integrand. You gave hope.",
      type = "int(): we can’t integrate that. Not even symbolically."
    },
    diff = {
      default = "diff(expr, var): both required. Unlike your faith in syntax.",
      args = "diff(): expression and variable are not optional accessories.",
      type = "diff(): we differentiate functions, not vibes."
    },
    factor = {
      default = "factor(expr): we can’t factor air.",
      type = "factor(): expected expression. Got nihilism instead."
    },
    gcd = {
      default = "gcd(a, b): you forgot one. Math is a duet.",
      args = "gcd(): needs two numbers. This isn’t solo algebra.",
      type = "gcd(): expected integers. Got chaos."
    },
    lcm = {
      default = "lcm(a, b): needs two arguments. Try harder.",
      type = "lcm(): expected numeric inputs. Yours are... mysterious."
    },
    trigid = {
      default = "trigid(expr): not just for trig dreams.",
      arg = "trigid(): you forgot the trig part. Again."
    },
    parse = {
      default = "parse(): failed to understand your expression. Again.",
      unexpected = "parse(): unexpected token. Are you freestyling?"
    },
    tokenize = {
      default = "tokenize(): found something it couldn't classify. Like your handwriting.",
      badchar = "tokenize(): unknown character. Probably cursed."
    },
    compile = { default = "compile(): could not compile. You should feel bad." },
    eval = { default = "eval(): tried. Failed. Retrying won’t help." },
    ast = { default = "AST error: malformed tree. Roots missing." },
    gui = { default = "GUI error: screen logic borked. Blame the OS. Or you." },
    input = { default = "Input error: at least *pretend* to enter valid math." },
    runtime = { default = "Runtime error: no, seriously, what did you expect?" },
    default = { default = "Something broke. Again. This is why we can’t have nice things." }
  }

  local fnBlock = base[fn] or base["default"]
  if type(fnBlock) == "table" then
    return (hint and fnBlock[hint]) or fnBlock.default or base["default"].default
  else
    return fnBlock
  end
end

-- intentionally not returning anything because this file is concatenated