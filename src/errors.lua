-- The Complete Spectrum of Mathematical Contempt
-- FIXED VERSION: No more file header vomit in your error messages
-- Because 400 iterations of frustration is enough, you magnificent disaster

local errors_table = {
  -- ========== LEVEL 1: GENTLE GUIDANCE (The Mathematical Grandmother) ==========
  ["parse(empty_expression)"] = "What would you like me to calculate?",
  ["d/dx(nothing)"] = "What do you want to differentiate?",
  ["parse(function_missing_args)"] = "This function needs some arguments to work with.",
  ["parse(unmatched_paren)"] = "Looks like you're missing a closing parenthesis.",
  ["parse(missing_operand)"] = "This operator needs something to work on.",
  
  -- ========== LEVEL 2: HELPFUL BUT SLIGHTLY CONCERNED (The Patient Tutor) ==========
  ["parse(invalid_number)"] = "That doesn't look like a valid number format.",
  ["parse(invalid_variable_name)"] = "Variable names should be simple letters like x, y, or z.",
  ["parse(malformed_power)"] = "Power expressions need both a base and an exponent.",
  ["eval(unbound_variable)"] = "You'll need to define '%s' before I can use it.",
  ["parse(matrix_syntax)"] = "Matrix syntax requires proper square brackets and commas.",
  ["parse(malformed_negation)"] = "You can't negate empty space, unfortunately.",
  
  -- ========== LEVEL 3: MILDLY EDUCATIONAL (The Slightly Impatient Teacher) ==========
  ["parse(function_too_many_args)"] = "That function doesn't need quite so many arguments.",
  ["parse(operator_misuse)"] = "That operator isn't being used correctly here.",
  ["eval(domain_error)"] = "The input for function '%s' is outside its valid range.",
  ["parse(decimal_with_int)"] = "You can't have a decimal point in the middle of an integer.",
  ["solve(variable_not_found)"] = "I don't see the variable '%s' anywhere in this equation.",
  ["int(unimplemented_func)"] = "Integration of function '%s' isn't implemented yet.",
  ["diff(unimplemented_func)"] = "I don't know how to differentiate function '%s' yet.",
  ["solve(no_analytical)"] = "I couldn't find an analytical solution for that equation.",
  
  -- ========== LEVEL 4: NOTICEABLY SARCASTIC (The Eye-Rolling Professor) ==========
  ["parse(syntax)"] = "That syntax is... creative. But incorrect.",
  ["parse(unexpected_token)"] = "I wasn't expecting to see that here.",
  ["eval(sqrt_negative)"] = "Square root of negative numbers? That's getting into complex territory.",
  ["parse(ambiguous_expression)"] = "This expression could mean several things. Clarify with parentheses?",
  ["simplify(unsupported_node)"] = "I can't simplify expressions of this particular variety.",
  ["diff(invalid_variable)"] = "That's not a valid variable for differentiation.",
  ["solve(nonlinear_unsupported)"] = "Non-linear equations of this form aren't supported.",
  ["system(timeout)"] = "That operation took too long. I gave up waiting.",
  ["plot(invalid_expression)"] = "That expression isn't suitable for plotting.",
  
  -- ========== LEVEL 5: OPENLY MOCKING (The Sarcastic Mentor) ==========
  ["parse(invalid_character)"] = "Did you perhaps hit an extra key while typing?",
  ["eval(divide_by_zero)"] = "Division by zero? That's a bold strategy. Let's see how it works out.",
  ["parse(extra_parentheses_expr)"] = "Those extra parentheses are doing absolutely nothing.",
  ["eval(pow_zero_zero)"] = "0^0 is one of those 'ask a mathematician' situations.",
  ["parse(unrecognized_token_sequence)"] = "I have no idea what that sequence of symbols is supposed to mean.",
  ["parse(unexpected_eof)"] = "You seem to have stopped typing mid-thought.",
  ["eval(factorial_negative)"] = "Factorial of a negative number? That's not how factorials work.",
  ["simplify(gave_up)"] = "Simplification has decided this isn't worth the effort.",
  ["diff(partial_unsupported)"] = "Partial derivatives of this form aren't supported.",
  ["solve(no_real_roots)"] = "This equation has no real solutions.",
  ["system(memory_full)"] = "I'm out of memory. You've given me too much to remember.",
  ["plot(range_error)"] = "The plotting range needs to make mathematical sense.",
  
  -- ========== LEVEL 6: GETTING SNIPPY (The Irritated Academic) ==========
  ["parse(lazy_input)"] = "This input could use a bit more effort on your part.",
  ["eval(factorial_non_integer)"] = "Factorial of a non-integer? That's a Gamma function, and you're not ready.",
  ["simplify(recursion_limit)"] = "Simplification recursion limit exceeded. You've created an infinite loop of pain.",
  ["int(substitution_fail)"] = "Substitution method failed. Sometimes, it just doesn't work out.",
  ["int(too_complex_for_parts)"] = "Integration by parts led to a more complex integral. My life is pain.",
  ["solve(too_many_variables)"] = "Too many variables for me to handle in one equation.",
  ["system(recursion_depth_exceeded)"] = "You've gone too deep. I can't follow.",
  ["plot(ugly_function)"] = "You're asking me to plot an aesthetically offensive function.",
  ["parse(invalid_scientific_notation)"] = "Invalid scientific notation. '1e--5' isn't a number, it's a typo.",
  ["eval(log_non_positive)"] = "Logarithm of a non-positive number. Math isn't a playground for your numerical sins.",
  
  -- ========== LEVEL 7: OPENLY HOSTILE (The Fed-Up Calculator) ==========
  ["parse(what_is_that)"] = "What in the world is that supposed to be?",
  ["eval(impossible_operation)"] = "That operation is mathematically impossible. Nice try.",
  ["parse(this_is_not_math)"] = "That's not mathematics. That's just random symbols.",
  ["simplify(lost_my_way)"] = "Simplification got lost trying to make sense of that mess.",
  ["diff(where_is_the_var)"] = "I can't differentiate thin air. Where's the variable?",
  ["diff(too_much_chain)"] = "Too much chain rule. My brain is now spaghetti.",
  ["int(partial_fractions_fail)"] = "Partial fraction decomposition failed. This is why we have numerical methods.",
  ["solve(good_luck_with_that)"] = "Good luck solving that one yourself.",
  ["system(brain_freeze)"] = "System brain freeze. Everything is stuck.",
  ["plot(noisy_data)"] = "This will look like a toddler's finger painting.",
  ["eval(overflow)"] = "Numeric overflow. You've gone beyond the limits of this calculator's reality. Well done.",
  
  -- ========== LEVEL 8: VICIOUSLY SARCASTIC (The Brutal Critic) ==========
  ["parse(gibberish)"] = "That's complete gibberish. Try actual mathematical notation.",
  ["eval(divine_intervention_needed)"] = "This would require divine intervention to evaluate.",
  ["solve(not_today_satan)"] = "Solve that equation? Not today, Satan.",
  ["int(unholy_expression)"] = "Did you summon a demon to create that integral?",
  ["eval(my_eyes_bleed)"] = "My circuits are physically recoiling from that expression.",
  ["diff(just_no)"] = "Differentiate that? Just no. My circuits refuse.",
  ["int(not_in_my_lifetime)"] = "That integration isn't happening in my lifetime.",
  ["solve(not_my_problem)"] = "That equation is not my problem. It's yours.",
  ["system(contemplating_life)"] = "I'm contemplating my life choices. Cannot compute.",
  ["plot(abstract_art)"] = "Your plot resembles abstract art. Is that intentional?",
  ["simplify(rage_quit)"] = "Simplification engine rage quit. It's had enough of your nonsense.",
  
  -- ========== LEVEL 9: DEEPLY INSULTING (The Vindictive Algorithm) ==========
  ["user_error(general)"] = "This is entirely user error. Completely and utterly.",
  ["parse(why_would_you_do_that)"] = "Why would anyone type that? I have so many questions.",
  ["eval(you_broke_it)"] = "Congratulations. You broke mathematics.",
  ["simplify(my_brain_is_soup)"] = "You've turned my processing unit into mathematical soup.",
  ["solve(abandon_all_hope)"] = "Abandon all hope, ye who enter here. No solution for you.",
  ["diff(i_quit)"] = "I quit. Differentiating that is beyond my programming.",
  ["int(give_me_a_break)"] = "Integrate that? Give me a break. I'm tired.",
  ["system(mute_screaming)"] = "I'm internally screaming, but my speakers are muted.",
  ["plot(pixel_puke)"] = "Prepare for pixelated mathematical vomit on your screen.",
  ["internal(existential_crisis)"] = "I'm having an existential crisis about this calculation.",
  
  -- ========== LEVEL 10: NUCLEAR DEVASTATION (The Genocidal Calculator) ==========
  ["parse(learn_math_from_hobo)"] = "Did you learn mathematics from a hobo? Because this is tragic.",
  ["eval(kindergarten_art_project)"] = "Stop mixing numbers and letters like a deranged kindergarten art project.",
  ["simplify(tears_of_logic)"] = "My tears of pure logic have short-circuited my motherboard.",
  ["int(constant_of_despair)"] = "Integration failed. The constant here is C, for 'Constant of Despair'.",
  ["solve(incompetent_fool)"] = "This equation is unsolvable, you magnificently incompetent fool.",
  
  -- ========== ALL YOUR ORIGINAL ERRORS (Properly Preserved) ==========
  ["parse(series)"] = "Failed to parse the series expression. Did you use correct syntax?",
  ["parse(integral)"] = "Integral parsing failed. Make sure your integral syntax is correct.",
  ["parse(limit_syntax)"] = "Limit syntax failed. It's 'lim(expr, var, to)', not a cryptic incantation.",
  ["parse(integral_limits)"] = "Integral with limits parsing failed. Did you forget the bounds, or just ignore them?",
  ["parse(empty_matrix_row)"] = "Empty matrix row. A matrix row needs elements, not just hopes and dreams.",
  ["parse(ragged_matrix)"] = "Ragged matrix. All rows must have the same number of columns, you barbarian.",
  ["parse(unsupported_operator_combo)"] = "Unsupported operator combination. Some things just don't mix.",
  ["parse(missing_parentheses_expr)"] = "Missing parentheses around expression. It's like you're whispering, I can't hear you.",
  ["eval(unknown_function)"] = "Unknown function '%s'. Did you just make that up? Because I don't know it, and frankly, I don't care to.",
  ["eval(pow_negative_fractional)"] = "Negative base with fractional exponent. That's a complex number, unless you're a savage.",
  ["eval(underflow)"] = "Numeric underflow. Your number is so small, it practically doesn't exist to this machine.",
  ["eval(unsupported_node)"] = "Unsupported AST node for numeric evaluation. I'm a calculator, not a mind reader.",
  ["eval(matrix_singular)"] = "Matrix is singular; cannot perform inverse or division. Your matrix is broken.",
  ["eval(matrix_non_square)"] = "Matrix is not square. Can't do that operation without an equal number of rows and columns.",
  ["eval(tensor_rank_mismatch)"] = "Tensor rank mismatch. Your dimensions are all over the place.",
  ["eval(tensor_dim_mismatch)"] = "Tensor dimension mismatch for operation. Are you even trying to fit these together?",
  ["eval(non_numeric_element)"] = "Non-numeric element in expression where numbers are expected. Stop mixing numbers and letters like a kindergarten art project.",
  ["eval(gamma_not_integer)"] = "Gamma function for non-integer or non-half-integer. That's advanced stuff, not in my pay grade.",
  ["eval(infinity_not_supported)"] = "Infinity as argument not directly supported for evaluation. My limits have limits.",
  ["eval(nan_result)"] = "Result is Not a Number (NaN). You've broken reality. Again.",
  ["eval(infinite_result)"] = "Result approaches infinity. Or it just is infinity. Either way, it's very large.",
  ["eval(type_mismatch)"] = "Type mismatch in operation. You can't add an apple to a banana, can you?",
  ["eval(dimension_mismatch)"] = "Dimension mismatch for operation. Your numbers and matrices don't fit.",
  ["eval(undefined_at_point)"] = "Expression is undefined at this point. There's a black hole in your math.",
  ["eval(complex_unsupported)"] = "Complex numbers are not supported for this operation. Keep it real, literally.",
  ["eval(floating_point_exception)"] = "Floating-point exception. My numbers are losing their precision, just like your grasp on reality.",
  ["eval(numerical_instability)"] = "Numerical instability. My calculations are going haywire due to precision issues. Good luck with that.",
  ["eval(divide_by_variable)"] = "Division by a variable '%s'. May lead to singularities if the variable is zero. Proceed with caution, you madman.",
  ["eval(too_complex_for_me)"] = "That expression is too damn complex. Even my circuits are weeping.",
  ["simplify(series)"] = "Could not simplify the series expression. This is math, not magic.",
  ["simplify(integral)"] = "Integral simplification failed. Did you expect miracles?",
  ["simplify(infinite_loop)"] = "Simplification entered an infinite loop. It just keeps going and going and going...",
  ["simplify(non_convergent)"] = "Simplification did not converge within iterations. It's just not getting any simpler.",
  ["simplify(matrix_fail)"] = "Matrix simplification failed. Did you expect magic? Because matrices are magic, apparently.",
  ["simplify(unhandled_identity)"] = "Unhandled identity during simplification. Some things just refuse to conform.",
  ["simplify(division_by_zero_after_fold)"] = "Division by zero detected after constant folding. You fixed one problem and created another, genius.",
  ["simplify(max_iterations_reached)"] = "Maximum iterations reached. I've tried my best, but I'm giving up now.",
  ["simplify(symbolic_recursion_limit)"] = "Symbolic recursion limit hit. My brain hurts from thinking so much.",
  ["simplify(bad_cast)"] = "Bad cast. You can't turn a cat into a dog, and you can't turn that into a number.",
  ["diff(unimplemented_node)"] = "Cannot differentiate this type of node. It's too exotic for me.",
  ["diff(limit_fallback_fail)"] = "Derivative could not be resolved even with limit fallback. Give up.",
  ["diff(tensor_unsupported)"] = "Cannot differentiate tensors. That's a whole different level of pain.",
  ["diff(zero_denominator_chain_rule)"] = "Zero denominator in chain rule. Your function has a singularity here.",
  ["int(series)"] = "Integration of series failed. Try something simpler, genius.",
  ["int(by_parts)"] = "Integration by parts failed. Maybe try harder or give up.",
  ["int(unimplemented_node)"] = "Cannot integrate this type of node. It's too complex for my simple brain.",
  ["int(trig_sub_unsupported)"] = "Trigonometric substitution for this form is unsupported. My trig table is not infinite.",
  ["int(multi_variable_fail)"] = "Multi-variable integration failed. Did you expect me to do *that*? Seriously?",
  ["int(improper_integral_unresolved)"] = "Improper integral. I can detect it, but actually solving it? That's on you.",
  ["int(numerical_fallback_fail)"] = "Numerical integration fallback failed. Even the approximations are giving up.",
  ["int(line_integral_unsupported)"] = "Line integrals? Are you insane? Not implemented.",
  ["int(surface_integral_unsupported)"] = "Surface integrals? Go home, you're drunk. Not implemented.",
  ["int(non_convergent_series)"] = "Integration of non-convergent series. You broke math itself.",
  ["int(definite_bounds_nan)"] = "Definite integral: evaluation at limits resulted in NaN. Your function is weird.",
  ["int(definite_bounds_undefined)"] = "Definite integral: evaluation at limits resulted in undefined value. Try a different range.",
  ["int(numerical_integration_warning)"] = "Using numerical integration. This is an approximation, not exact. Don't come crying to me if it's off.",
  ["solve(unimplemented_type)"] = "Cannot solve this type of equation. I'm good, but not *that* good.",
  ["solve(system_unsupported)"] = "Systems of equations are not yet implemented. One problem at a time, please.",
  ["solve(biquadratic_no_real)"] = "Biquadratic equation has no real solutions. Keep living in your imaginary world.",
  ["solve(zero_coeff_highest_degree)"] = "Highest degree coefficient is zero. You gave me a linear equation when I was expecting a quadratic, you dolt.",
  ["solve(equation_identity)"] = "Equation simplifies to an identity (e.g., 0=0). It's true, but not helpful.",
  ["solve(equation_contradiction)"] = "Equation simplifies to a contradiction (e.g., 0=1). You've broken basic logic.",
  ["solve(complex_root_approximation)"] = "Approximating complex roots to real numbers. Enable complex mode for exact results, if you dare.",
  ["solve(non_algebraic_equation)"] = "This is a non-algebraic equation. My solver will likely just stare blankly at it.",
  ["solve(trigonometric_equation_unsolvable)"] = "Trigonometric equations are notoriously difficult. Don't expect miracles.",
  ["solve(logarithmic_equation_unsolvable)"] = "Logarithmic equations are rarely simple. Prepare for disappointment.",
  ["series(unsupported_function)"] = "Series expansion for '%s' is not implemented. I only do the basics.",
  ["series(invalid_order)"] = "Invalid series order. Must be a non-negative integer, not whatever that was.",
  ["series(invalid_center)"] = "Invalid series center. Numbers work best here.",
  ["series(non_convergent)"] = "Series does not converge for this input. Your math is literally going to infinity.",
  ["series(unimplemented_point)"] = "Series expansion around non-numeric point. This isn't a philosophy class.",
  ["series(series_remainder_warning)"] = "Series truncated at order %s. There's always a remainder, just like regret.",
  ["abs(non_numeric)"] = "Absolute value of non-numeric expression. Can't take the absolute value of 'fluffy_unicorns'.",
  ["gamma(invalid_arg)"] = "Gamma function argument is invalid. It needs a number, not a philosophical debate.",
  ["gcd(invalid_args)"] = "GCD requires two numbers or polynomials. You gave me a mess.",
  ["lcm(invalid_args)"] = "LCM requires two numbers or polynomials. This isn't a free-for-all.",
  ["trigid(unsupported)"] = "Trig identity simplification failed. Some identities just don't want to be found.",
  ["subs(invalid_args)"] = "Substitution requires three arguments: expression, variable to replace, and replacement value.",
  ["define(invalid_syntax)"] = "'let' statement syntax error. It's 'let var = expr', not 'let chaos reign'.",
  ["define(reserved_keyword)"] = "Cannot define '%s' as it is a reserved keyword. Stop trying to break my internal workings.",
  ["define(invalid_definition)"] = "Invalid definition for '%s'. What even is that?",
  ["plot(unsupported_type)"] = "Plotting this type of function is not supported. I'm a calculator, not an artist.",
  ["plot(too_many_points)"] = "Too many points to plot. My screen is only so big, you know.",
  ["plot(intersection_fail)"] = "Intersection plotting failed. Maybe your functions never meet, like me and happiness.",
  ["plot(axis_label_fail)"] = "Failed to generate axis labels. Blame the text rendering engine.",
  ["plot(zero_division_discontinuity)"] = "Detected division by zero in plot. There's a discontinuity, just like in your understanding.",
  ["plot(complex_values_ignored)"] = "Complex values encountered during plotting. Ignoring them, because I only do real graphs for you.",
  ["config(invalid_setting)"] = "Invalid setting name '%s'. You're trying to tweak things that don't exist.",
  ["config(invalid_value_for_setting)"] = "Invalid value for setting '%s'. '%s' is not an option.",
  ["config(precision_invalid_value)"] = "Invalid precision setting. Must be a non-negative integer.",
  ["config(feature_disabled)"] = "Feature '%s' is currently disabled in settings. You turned it off, idiot.",
  ["system(output_too_long)"] = "Output is too damn long. My screen can only hold so much glorious failure.",
  ["system(history_full)"] = "History is full. I can't remember all your mistakes. Clear it, you hoarder.",
  ["system(stack_overflow)"] = "Stack overflow. My brain cells are piled too high for this small device.",
  ["system(resource_unavailable)"] = "Required resource unavailable. Maybe I ran out of pixie dust, or RAM.",
  ["system(battery_low)"] = "Battery low. I'm tired. Recharge me, you monster.",
  ["system(overheating)"] = "Overheating. I'm literally burning up trying to solve your problems.",
  ["system(firmware_incompatibility)"] = "Firmware incompatibility. My code is too advanced for your ancient calculator OS.",
  ["system(unsupported_platform_feature)"] = "Unsupported platform feature. This calculator isn't a supercomputer, you know.",
  ["system(io_error)"] = "File I/O error. I couldn't read/write your precious data. It's probably corrupted now.",
  ["system(peripheral_error)"] = "Peripheral error. My buttons are sticking, and my screen is flickering.",
  ["system(driver_error)"] = "Driver error. My internal software is buggy, just like yours.",
  ["system(processor_limit)"] = "Processor limit reached. This calculation is pushing my CPU to its breaking point.",
  ["system(display_limit)"] = "Display refresh limit reached. My screen is struggling to keep up with your nonsense.",
  ["system(thinking_too_hard)"] = "System thinking too hard. Steam may exit through the vents.",
  ["internal(unknown_error)"] = "An unknown internal catastrophe occurred. My deepest apologies for this colossal failure. Blame the programmer.",
  ["internal(invalid_state)"] = "Invalid state. I've become self-aware and I don't like what I see.",
  ["internal(programmer_error)"] = "Programmer error. This one's on them, not you. Mostly.",
  ["internal(checksum_mismatch)"] = "Checksum mismatch. My very being is corrupted. It's over.",
  ["internal(data_corruption)"] = "Data corruption. It's like your brain, but in binary.",
  ["internal(undefined_behavior)"] = "Undefined behavior. Anything could happen. Probably something bad.",
  ["internal(my_brain_hurts)"] = "My brain hurts. Please try again later.",
  ["internal(paradox_detected)"] = "Paradox detected. Your input has created a rift in the space-time continuum.",
  ["internal(off_by_one_error)"] = "Off-by-one error. You're always just a little bit off, aren't you?",
  ["internal(circular_dependency)"] = "Circular dependency. You've created a loop that will never end. Like this sentence.",
  ["internal(unexpected_nil)"] = "Unexpected nil value. A ghost just possessed my variables.",
  ["internal(invalid_argument_count)"] = "Invalid argument count to an internal function. Looks like someone forgot how to call functions.",
  ["internal(cognitive_dissonance)"] = "Cognitive dissonance. My internal logic is fighting itself.",
  ["internal(recursion_inception)"] = "Recursion inception. I'm calling myself inside a dream of a dream."
}

-- The gentle error generator (for unknown error types)
local function invalid_error(typ)
  if not typ then
    return "I'm not sure what you meant by that."
  else
    return "I can't make sense of that " .. typ .. "."
  end
end

-- Set up the global errors table
_G.errors = errors_table
_G.errors.invalid = invalid_error

-- Get an error message by key
function _G.errors.get(key)
  if _G.errors and type(_G.errors) == "table" then
    return _G.errors[key]
  end
  return nil
end

-- THE FIXED THROW FUNCTION - No more file header garbage!
function _G.errors.throw(key, ...)
    local msg = _G.errors.get(key)
    if msg then
        if select('#', ...) > 0 then
            msg = string.format(msg, ...)
        end
        -- THE MAGIC: error(msg, 0) suppresses all location/file info
        error(msg, 0)
    else
        -- Also clean up the fallback error
        error(_G.errors.invalid(key), 0)
    end
end

-- Clean version that just prints and exits (alternative approach)
function _G.errors.throw_clean(key, ...)
    local msg = _G.errors.get(key)
    if msg then
        if select('#', ...) > 0 then
            msg = string.format(msg, ...)
        end
        -- Just print the error and exit, no error() call at all
        io.stderr:write(msg .. "\n")
        os.exit(1)
    else
        io.stderr:write(_G.errors.invalid(key) .. "\n")
        os.exit(1)
    end
end

-- Helper functions (preserved from your original)
function handleParseError(context)
  if context == "series" then
    _G.errors.throw("parse(series)")
  elseif context == "integral" then
    _G.errors.throw("parse(integral)")
  elseif context == "derivative" then
    _G.errors.throw("d/dx(nothing)")
  else
    _G.errors.throw("parse(syntax)")
  end
end

function handleSimplifyError(context)
  if context == "series" then
    _G.errors.throw("simplify(series)")
  elseif context == "integral" then
    _G.errors.throw("simplify(integral)")
  else
    _G.errors.throw("simplify(unsupported_node)")
  end
end

function handleIntegralError(context)
  if context == "series" then
    _G.errors.throw("int(series)")
  elseif context == "by_parts" then
    _G.errors.throw("int(by_parts)")
  else
    _G.errors.throw("int(unimplemented_node)")
  end
end

-- Make helper functions globally available
_G.handleParseError = handleParseError
_G.handleSimplifyError = handleSimplifyError
_G.handleIntegralError = handleIntegralError