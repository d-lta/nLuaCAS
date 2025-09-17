-- Error message library for nLuaCAS.

local errors_table = {
  ["parse(empty_expression)"] = "What would you like me to calculate?",
  ["d/dx(nothing)"] = "You must provide a function to differentiate.",
  ["parse(function_missing_args)"] = "This function requires arguments.",
  ["parse(unmatched_paren)"] = "Syntax error: missing a closing parenthesis.",
  ["parse(missing_operand)"] = "Syntax error: missing an operand for the operator.",
  
  ["parse(invalid_number)"] = "Invalid number format.",
  ["parse(invalid_variable_name)"] = "Invalid variable name. Use simple letters like x, y, or z.",
  ["parse(malformed_power)"] = "Malformed power expression: requires both a base and an exponent.",
  ["eval(unbound_variable)"] = "Undefined variable: '%s'. You must define it first.",
  ["parse(matrix_syntax)"] = "Invalid matrix syntax. Check for proper brackets and commas.",
  ["parse(malformed_negation)"] = "Malformed negation. An expression must follow the minus sign.",
  ["parse(function_too_many_args)"] = "Too many arguments provided for this function.",
  ["parse(operator_misuse)"] = "Incorrect use of an operator.",
  ["eval(domain_error)"] = "Domain error: the input for function '%s' is outside its valid range.",
  ["parse(decimal_with_int)"] = "Syntax error: cannot have a decimal point within an integer.",
  ["solve(variable_not_found)"] = "The variable '%s' was not found in the equation.",
  ["int(unimplemented_func)"] = "Integration of function '%s' is not yet implemented.",
  ["diff(unimplemented_func)"] = "Differentiation of function '%s' is not yet implemented.",
  ["solve(no_analytical)"] = "Could not find an analytical solution for that equation.",
  ["parse(syntax)"] = "Syntax error: please check your expression.",
  ["parse(unexpected_token)"] = "Syntax error: unexpected token found.",
  ["eval(sqrt_negative)"] = "Domain error: square root of a negative number is not supported.",
  ["parse(ambiguous_expression)"] = "Ambiguous expression. Try using parentheses to clarify.",
  ["simplify(unsupported_node)"] = "Simplification is not supported for this type of expression.",
  ["diff(invalid_variable)"] = "Invalid variable for differentiation.",
  ["solve(nonlinear_unsupported)"] = "Solving non-linear equations of this form is not supported.",
  ["system(timeout)"] = "Operation timed out.",
  ["plot(invalid_expression)"] = "The expression provided is not suitable for plotting.",
  ["parse(invalid_character)"] = "Invalid character in expression.",
  ["eval(divide_by_zero)"] = "Division by zero.",
  ["parse(extra_parentheses_expr)"] = "Redundant parentheses.",
  ["eval(pow_zero_zero)"] = "Evaluation error: 0^0 is undefined.",
  ["parse(unrecognized_token_sequence)"] = "Unrecognized sequence of symbols.",
  ["parse(unexpected_eof)"] = "Unexpected end of expression.",
  ["eval(factorial_negative)"] = "Domain error: factorial of a negative number is undefined.",
  ["simplify(gave_up)"] = "Simplification limit reached.",
  ["diff(partial_unsupported)"] = "Partial derivatives of this form are not supported.",
  ["solve(no_real_roots)"] = "The equation has no real solutions.",
  ["system(memory_full)"] = "System memory is full. Cannot perform operation.",
  ["plot(range_error)"] = "Invalid plotting range.",
  ["parse(lazy_input)"] = "Input too short to be a valid expression.",
  ["eval(factorial_non_integer)"] = "Domain error: factorial is only defined for non-negative integers.",
  ["simplify(recursion_limit)"] = "Simplification recursion limit exceeded.",
  ["int(substitution_fail)"] = "The substitution method failed for this integral.",
  ["int(too_complex_for_parts)"] = "Integration by parts resulted in a more complex integral.",
  ["solve(too_many_variables)"] = "Too many variables to solve in a single equation.",
  ["system(recursion_depth_exceeded)"] = "System recursion depth exceeded.",
  ["plot(ugly_function)"] = "Cannot plot: function is too complex or non-continuous.",
  ["parse(invalid_scientific_notation)"] = "Invalid scientific notation.",
  ["eval(log_non_positive)"] = "Domain error: logarithm of a non-positive number is undefined.",
  ["parse(what_is_that)"] = "Syntax error: unrecognizable expression.",
  ["eval(impossible_operation)"] = "The operation is mathematically impossible.",
  ["parse(this_is_not_math)"] = "The input does not resemble a mathematical expression.",
  ["simplify(lost_my_way)"] = "Simplification failed to converge.",
  ["diff(where_is_the_var)"] = "No variable was provided for differentiation.",
  ["diff(too_much_chain)"] = "Too many nested functions for differentiation (chain rule).",
  ["int(partial_fractions_fail)"] = "Partial fraction decomposition failed.",
  ["solve(good_luck_with_that)"] = "Could not find a solution.",
  ["system(brain_freeze)"] = "System is unresponsive. Please try again.",
  ["plot(noisy_data)"] = "Cannot plot: function is too erratic.",
  ["eval(overflow)"] = "Numeric overflow.",
  ["parse(gibberish)"] = "Unrecognizable gibberish.",
  ["eval(divine_intervention_needed)"] = "Unable to evaluate: expression is too complex.",
  ["solve(not_today_satan)"] = "Unable to solve: expression is too complex.",
  ["int(unholy_expression)"] = "Unable to integrate: expression is too complex.",
  ["eval(my_eyes_bleed)"] = "Unable to evaluate: expression is too complex.",
  ["diff(just_no)"] = "Unable to differentiate: expression is too complex.",
  ["int(not_in_my_lifetime)"] = "Unable to integrate: expression is too complex.",
  ["solve(not_my_problem)"] = "Unable to solve: expression is too complex.",
  ["system(contemplating_life)"] = "System is unresponsive. Please try again.",
  ["plot(abstract_art)"] = "Cannot plot: expression is too abstract.",
  ["simplify(rage_quit)"] = "Simplification limit reached.",
  ["user_error(general)"] = "An error occurred due to user input.",
  ["parse(why_would_you_do_that)"] = "Syntax error: invalid input.",
  ["eval(you_broke_it)"] = "An error occurred during evaluation.",
  ["simplify(my_brain_is_soup)"] = "Simplification failed.",
  ["solve(abandon_all_hope)"] = "No solution found.",
  ["diff(i_quit)"] = "Differentiation failed.",
  ["int(give_me_a_break)"] = "Integration failed.",
  ["system(mute_screaming)"] = "An internal error occurred.",
  ["plot(pixel_puke)"] = "The plot contains too many discontinuities.",
  ["internal(existential_crisis)"] = "An unknown internal error occurred.",
  ["parse(learn_math_from_hobo)"] = "Syntax error: invalid mathematical notation.",
  ["eval(kindergarten_art_project)"] = "Type mismatch: mixing numeric and symbolic values incorrectly.",
  ["simplify(tears_of_logic)"] = "Simplification failed due to logical inconsistencies.",
  ["int(constant_of_despair)"] = "Integration failed.",
  ["solve(incompetent_fool)"] = "The equation is unsolvable.",
  ["parse(series)"] = "Series parsing failed. Check for correct syntax.",
  ["parse(integral)"] = "Integral parsing failed. Check for correct syntax.",
  ["parse(limit_syntax)"] = "Limit syntax failed. Use the format 'lim(expr, var, to)'.",
  ["parse(integral_limits)"] = "Definite integral parsing failed. Missing or incorrect bounds.",
  ["parse(empty_matrix_row)"] = "Matrix syntax error: an empty row was found.",
  ["parse(ragged_matrix)"] = "Ragged matrix: all rows must have the same number of columns.",
  ["parse(unsupported_operator_combo)"] = "Unsupported operator combination.",
  ["parse(missing_parentheses_expr)"] = "Missing parentheses around expression.",
  ["eval(unknown_function)"] = "Unknown function '%s'.",
  ["eval(pow_negative_fractional)"] = "Domain error: negative base with a fractional exponent is not supported.",
  ["eval(underflow)"] = "Numeric underflow.",
  ["eval(unsupported_node)"] = "Unsupported AST node for numeric evaluation.",
  ["eval(matrix_singular)"] = "Matrix is singular and cannot be inverted.",
  ["eval(matrix_non_square)"] = "Matrix is not square, and the operation requires a square matrix.",
  ["eval(tensor_rank_mismatch)"] = "Tensor rank mismatch.",
  ["eval(tensor_dim_mismatch)"] = "Tensor dimension mismatch for the operation.",
  ["eval(non_numeric_element)"] = "Non-numeric element found where a number was expected.",
  ["eval(gamma_not_integer)"] = "Gamma function is not supported for non-integer or non-half-integer values.",
  ["eval(infinity_not_supported)"] = "Infinity as an argument is not directly supported.",
  ["eval(nan_result)"] = "The result is Not a Number (NaN).",
  ["eval(infinite_result)"] = "The result is infinite.",
  ["eval(type_mismatch)"] = "Type mismatch in the operation.",
  ["eval(dimension_mismatch)"] = "Dimension mismatch for the operation.",
  ["eval(undefined_at_point)"] = "The expression is undefined at the given point.",
  ["eval(complex_unsupported)"] = "Complex numbers are not supported for this operation.",
  ["eval(floating_point_exception)"] = "Floating-point exception occurred.",
  ["eval(numerical_instability)"] = "Numerical instability detected.",
  ["eval(divide_by_variable)"] = "Division by variable '%s'. May result in a singularity.",
  ["eval(too_complex_for_me)"] = "The expression is too complex for evaluation.",
  ["simplify(series)"] = "Could not simplify the series expression.",
  ["simplify(integral)"] = "Integral simplification failed.",
  ["simplify(infinite_loop)"] = "Simplification entered an infinite loop.",
  ["simplify(non_convergent)"] = "Simplification did not converge.",
  ["simplify(matrix_fail)"] = "Matrix simplification failed.",
  ["simplify(unhandled_identity)"] = "An unhandled identity was encountered during simplification.",
  ["simplify(division_by_zero_after_fold)"] = "Division by zero detected after constant folding.",
  ["simplify(max_iterations_reached)"] = "Maximum simplification iterations reached.",
  ["simplify(symbolic_recursion_limit)"] = "Symbolic recursion limit exceeded.",
  ["simplify(bad_cast)"] = "Bad cast: a value could not be converted to the required type.",
  ["diff(unimplemented_node)"] = "Cannot differentiate this type of AST node.",
  ["diff(limit_fallback_fail)"] = "Derivative could not be resolved with limit fallback.",
  ["diff(tensor_unsupported)"] = "Differentiation of tensors is not supported.",
  ["diff(zero_denominator_chain_rule)"] = "Zero denominator in the chain rule.",
  ["int(series)"] = "Integration of series failed.",
  ["int(by_parts)"] = "Integration by parts failed.",
  ["int(unimplemented_node)"] = "Cannot integrate this type of AST node.",
  ["int(trig_sub_unsupported)"] = "Trigonometric substitution is not supported for this form.",
  ["int(multi_variable_fail)"] = "Multi-variable integration failed.",
  ["int(improper_integral_unresolved)"] = "Improper integral could not be resolved.",
  ["int(numerical_fallback_fail)"] = "Numerical integration fallback failed.",
  ["int(line_integral_unsupported)"] = "Line integrals are not implemented.",
  ["int(surface_integral_unsupported)"] = "Surface integrals are not implemented.",
  ["int(non_convergent_series)"] = "Integration of a non-convergent series is not possible.",
  ["int(definite_bounds_nan)"] = "Definite integral evaluation at the bounds resulted in NaN.",
  ["int(definite_bounds_undefined)"] = "Definite integral evaluation at the bounds resulted in an undefined value.",
  ["int(numerical_integration_warning)"] = "Using numerical integration. This is an approximation.",
  ["solve(unimplemented_type)"] = "Cannot solve this type of equation.",
  ["solve(system_unsupported)"] = "Systems of equations are not yet implemented.",
  ["solve(biquadratic_no_real)"] = "Biquadratic equation has no real solutions.",
  ["solve(zero_coeff_highest_degree)"] = "The highest degree coefficient is zero, which changes the equation type.",
  ["solve(equation_identity)"] = "Equation simplifies to an identity (e.g., 0=0).",
  ["solve(equation_contradiction)"] = "Equation simplifies to a contradiction (e.g., 0=1).",
  ["solve(complex_root_approximation)"] = "Approximating complex roots to real numbers. Enable complex mode for exact results.",
  ["solve(non_algebraic_equation)"] = "This is a non-algebraic equation and cannot be solved with this method.",
  ["solve(trigonometric_equation_unsolvable)"] = "This trigonometric equation is not supported.",
  ["solve(logarithmic_equation_unsolvable)"] = "This logarithmic equation is not supported.",
  ["series(unsupported_function)"] = "Series expansion for '%s' is not implemented.",
  ["series(invalid_order)"] = "Invalid series order. Must be a non-negative integer.",
  ["series(invalid_center)"] = "Invalid series center. Must be a number.",
  ["series(non_convergent)"] = "Series does not converge for this input.",
  ["series(unimplemented_point)"] = "Series expansion around a non-numeric point is not supported.",
  ["series(series_remainder_warning)"] = "Series truncated at order %s. This is an approximation.",
  ["abs(non_numeric)"] = "Absolute value can only be applied to a numeric expression.",
  ["gamma(invalid_arg)"] = "Invalid argument for Gamma function.",
  ["gcd(invalid_args)"] = "GCD requires two numeric or polynomial arguments.",
  ["lcm(invalid_args)"] = "LCM requires two numeric or polynomial arguments.",
  ["trigid(unsupported)"] = "Trigonometric identity simplification is not supported for this form.",
  ["subs(invalid_args)"] = "Substitution requires three arguments: expression, variable, and replacement.",
  ["define(invalid_syntax)"] = "'let' statement syntax error. Use 'let var = expr'.",
  ["define(reserved_keyword)"] = "Cannot define '%s' as it is a reserved keyword.",
  ["define(invalid_definition)"] = "Invalid definition for '%s'.",
  ["plot(unsupported_type)"] = "Plotting this type of function is not supported.",
  ["plot(too_many_points)"] = "Too many points to plot.",
  ["plot(intersection_fail)"] = "Intersection plotting failed.",
  ["plot(axis_label_fail)"] = "Failed to generate axis labels.",
  ["plot(zero_division_discontinuity)"] = "Division by zero discontinuity detected in the plot.",
  ["plot(complex_values_ignored)"] = "Complex values were encountered and ignored.",
  ["config(invalid_setting)"] = "Invalid setting name: '%s'.",
  ["config(invalid_value_for_setting)"] = "Invalid value for setting '%s': '%s'.",
  ["config(precision_invalid_value)"] = "Invalid precision setting. Must be a non-negative integer.",
  ["config(feature_disabled)"] = "Feature '%s' is currently disabled.",
  ["system(output_too_long)"] = "The output is too large to display.",
  ["system(history_full)"] = "History is full. Please clear it.",
  ["system(stack_overflow)"] = "Stack overflow.",
  ["system(resource_unavailable)"] = "A required system resource is unavailable.",
  ["system(battery_low)"] = "Battery is low. Please recharge the device.",
  ["system(overheating)"] = "The system is overheating. Please let it cool down.",
  ["system(firmware_incompatibility)"] = "Firmware incompatibility detected.",
  ["system(unsupported_platform_feature)"] = "The current platform does not support this feature.",
  ["system(io_error)"] = "File I/O error occurred.",
  ["system(peripheral_error)"] = "A peripheral error occurred.",
  ["system(driver_error)"] = "A driver error occurred.",
  ["system(processor_limit)"] = "Processor limit reached.",
  ["system(display_limit)"] = "Display refresh limit reached.",
  ["system(thinking_too_hard)"] = "System is busy. Please wait.",
  ["internal(unknown_error)"] = "An unknown internal error occurred.",
  ["internal(invalid_state)"] = "Invalid internal state.",
  ["internal(programmer_error)"] = "An internal programmer error occurred.",
  ["internal(checksum_mismatch)"] = "Checksum mismatch detected.",
  ["internal(data_corruption)"] = "Data corruption detected.",
  ["internal(undefined_behavior)"] = "Undefined behavior.",
  ["internal(my_brain_hurts)"] = "An internal error occurred.",
  ["internal(paradox_detected)"] = "An internal logical paradox was detected.",
  ["internal(off_by_one_error)"] = "Off-by-one internal error.",
  ["internal(circular_dependency)"] = "Circular dependency detected.",
  ["internal(unexpected_nil)"] = "Unexpected nil value encountered.",
  ["internal(invalid_argument_count)"] = "Invalid argument count to an internal function.",
  ["internal(cognitive_dissonance)"] = "Internal logical inconsistency.",
  ["internal(recursion_inception)"] = "Deep recursion occurred."
}

-- Fallback for invalid error types.
local function invalid_error(typ)
  if not typ then
    return "An unknown error occurred."
  else
    return "An unexpected error of type '" .. typ .. "' occurred."
  end
end

-- Set up the global errors table
_G.errors = errors_table
_G.errors.invalid = invalid_error

-- Get an error message by key.
function _G.errors.get(key)
  if _G.errors and type(_G.errors) == "table" then
    return _G.errors[key]
  end
  return nil
end

-- Throws a clean, user-friendly error with optional formatting.
function _G.errors.throw(key, ...)
    local msg = _G.errors.get(key)
    if msg then
        if select('#', ...) > 0 then
            msg = string.format(msg, ...)
        end
        error(msg, 0) -- Suppress file/line info
    else
        error(_G.errors.invalid(key), 0)
    end
end

-- Writes a clean error message to stderr and exits.
function _G.errors.throw_clean(key, ...)
    local msg = _G.errors.get(key)
    if msg then
        if select('#', ...) > 0 then
            msg = string.format(msg, ...)
        end
        io.stderr:write(msg .. "\n")
        os.exit(1)
    else
        io.stderr:write(_G.errors.invalid(key) .. "\n")
        os.exit(1)
    end
end

-- Handle parse errors based on context.
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

-- Handle simplification errors based on context.
function handleSimplifyError(context)
  if context == "series" then
    _G.errors.throw("simplify(series)")
  elseif context == "integral" then
    _G.errors.throw("simplify(integral)")
  else
    _G.errors.throw("simplify(unsupported_node)")
  end
end

-- Handle integral errors based on context.
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