-- graph.lua
-- This module provides graphing capabilities for the TI-Nspire CX CAS,
-- leveraging an existing symbolic math engine.

-- IMPORTANT: This file assumes the following global CAS engine functions are already loaded:
-- _G.parse(expression_string) : Returns an AST for the given expression string.
-- _G.evaluate_ast_numeric(ast_node, variables_table) : Numerically evaluates an AST.
-- _G.solve(equation_string) : Solves an equation string symbolically, returns a table of solution ASTs.
-- _G.astToString(ast_node) : Converts an AST back to its symbolic string representation.
-- _G.errors.invalid(function_name, hint) : For consistent error reporting.

-- Nspire Lua built-in modules
-- REMOVED: local graphics = graphics
-- REMOVED: local math = math
-- REMOVED: local os = os -- For performance timing/sleep if needed

-- Define the graphing window (world coordinates)

local x_min_world = -10
local x_max_world = 10
local y_min_world = -10
local y_max_world = 10

-- Calculate screen dimensions once
local screen_width = 50
local screen_height = 50

-- --- Coordinate Transformation Functions ---
-- Converts world X-coordinate to screen pixel X-coordinate
local function world_to_screen_x(x_world)
    return (x_world - x_min_world) / (x_max_world - x_min_world) * screen_width
end

-- Converts world Y-coordinate to screen pixel Y-coordinate (Nspire Y-axis is inverted)
local function world_to_screen_y(y_world)
    return screen_height - ((y_world - y_min_world) / (y_max_world - y_min_world) * screen_height)
end

-- Converts screen pixel X-coordinate to world X-coordinate
local function screen_to_world_x(x_screen)
    return x_screen / screen_width * (x_max_world - x_min_world) + x_min_world
end

-- Converts screen pixel Y-coordinate to world Y-coordinate
local function screen_to_world_y(y_screen)
    return (screen_height - y_screen) / screen_height * (y_max_world - y_min_world) + y_min_world
end

-- --- Plotting Functions ---

--- Plots an explicit function of the form y = f(x)
-- @param expression_string string: The mathematical expression for f(x) (e.g., "x^2", "sin(x)")
-- @param color_r number: Red component (0-255)
-- @param color_g number: Green component (0-255)
-- @param color_b number: Blue component (0-255)
function plot_explicit_function(expression_string, color_r, color_g, color_b)
    local f_x_ast = _G.parse(expression_string) -- Parse the expression into an AST

    graphics.setColor(color_r, color_g, color_b)
    graphics.setPen(2, "solid") -- Set line thickness

    local prev_screen_x, prev_screen_y = nil, nil

    -- Iterate across every pixel column on the screen
    for screen_x_pixel = 0, screen_width do
        local x_world = screen_to_world_x(screen_x_pixel) -- Convert pixel X to world X

        -- Numerically evaluate the function AST for the current x_world
        local y_world_raw = _G.evaluate_ast_numeric(f_x_ast, {x = x_world})

        -- Check if the result is a valid number (not NaN, not infinite)
        if type(y_world_raw) == "number" and not (y_world_raw ~= y_world_raw) and y_world_raw ~= math.huge and y_world_raw ~= -math.huge then
            local screen_y_pixel = world_to_screen_y(y_world_raw) -- Convert world Y to pixel Y

            -- Only draw if the point is within the screen's Y bounds (with a small buffer for continuity)
            if screen_y_pixel >= -10 and screen_y_pixel <= screen_height + 10 then
                if prev_screen_x ~= nil then
                    -- Draw a line segment from the previous valid point to the current one
                    graphics.drawLine(prev_screen_x, prev_screen_y, screen_x_pixel, screen_y_pixel)
                end
                prev_screen_x, prev_screen_y = screen_x_pixel, screen_y_pixel
            else
                -- If the point goes off-screen (vertically), break the line to avoid drawing across discontinuities
                prev_screen_x, prev_screen_y = nil, nil
            end
        else
            -- If evaluation fails (e.g., division by zero, sqrt of negative), break the line
            prev_screen_x, prev_screen_y = nil, nil
        end
    end
end

--- Plots an implicit function of the form F(x,y) = 0
-- Uses a grid evaluation method. Performance can be slow on Nspire for high resolution/complex functions.
-- @param F_xy_expression_string string: The expression for F(x,y) (e.g., "x^2 + y^2 - 25")
-- @param color_r number: Red component (0-255)
-- @param color_g number: Green component (0-255)
-- @param color_b number: Blue component (0-255)
-- @param tolerance number: How close to zero F(x,y) must be to draw a pixel (e.g., 0.1)
-- @param resolution_factor number: Higher value means fewer samples (e.g., 2 for half resolution)
function plot_implicit_function(F_xy_expression_string, color_r, color_g, color_b, tolerance, resolution_factor)
    tolerance = tolerance or 0.1
    resolution_factor = math.max(1, math.floor(resolution_factor or 1)) -- Ensure at least 1

    local F_xy_ast = _G.parse(F_xy_expression_string)

    graphics.setColor(color_r, color_g, color_b)

    -- Determine step size for world coordinates based on screen resolution and resolution_factor
    local x_world_step = (x_max_world - x_min_world) / (screen_width / resolution_factor)
    local y_world_step = (y_max_world - y_min_world) / (screen_height / resolution_factor)

    -- Iterate over a grid of world coordinates
    for x_world = x_min_world, x_max_world, x_world_step do
        for y_world = y_min_world, y_max_world, y_world_step do
            -- Numerically evaluate F(x,y)
            local val = _G.evaluate_ast_numeric(F_xy_ast, {x = x_world, y = y_world})

            -- If the value is close to zero, draw a pixel
            if type(val) == "number" and not (val ~= val) and math.abs(val) <= tolerance then
                local screen_x = world_to_screen_x(x_world)
                local screen_y = world_to_screen_y(y_world)
                graphics.dot(screen_x, screen_y)
            end
        end
    end
end

--- Plots intersection points of two expressions, using symbolic solver and displaying exact labels.
-- @param expr1_string string: The first expression (e.g., "x^2")
-- @param expr2_string string: The second expression (e.g., "x+1")
-- @param color_r number: Red component (0-255)
-- @param color_g number: Green component (0-255)
-- @param color_b number: Blue component (0-255)
-- @param display_labels boolean: True to display exact coordinate labels, false otherwise.
function plot_intersections(expr1_string, expr2_string, color_r, color_g, color_b, display_labels)
    display_labels = display_labels ~= false -- Default to true if not explicitly false

    local equation_to_solve = expr1_string .. "=" .. expr2_string

    local solutions_for_x_asts = {}
    local success, solved_result = pcall(_G.solve, equation_to_solve)

    if success and solved_result and type(solved_result) == "table" then
        -- Process the solver's output. Assumes _G.solve returns a table of ASTs,
        -- where each AST is either a direct solution value for 'x' or an 'equals' AST like {left=x_var, right=solution_value}.
        for _, sol_item in ipairs(solved_result) do
            local solution_ast = nil
            if sol_item.type == "equals" and sol_item.left.type == "variable" and sol_item.left.name == "x" then
                solution_ast = sol_item.right
            elseif sol_item.type ~= "equals" then -- Assume it's a direct solution value AST for 'x'
                solution_ast = sol_item
            end

            if solution_ast then
                table.insert(solutions_for_x_asts, solution_ast)
            end
        end
    else
        -- Log or display solver error
        print(_G.errors.invalid("plot_intersections", "Solver failed for '" .. equation_to_solve .. "': " .. tostring(solved_result)))
        return
    end

    graphics.setColor(color_r, color_g, color_b)
    graphics.setPen(3, "solid") -- Thicker mark for intersection points

    local f1_ast = _G.parse(expr1_string) -- Parse one of the original functions to get y-values

    for _, x_sol_ast in ipairs(solutions_for_x_asts) do
        -- Numerically evaluate the x-solution for plotting
        local x_solution_numeric = _G.evaluate_ast_numeric(x_sol_ast, {})

        -- Only plot if x-solution is a valid number and within the current world X-range
        if type(x_solution_numeric) == "number" and not (x_solution_numeric ~= x_solution_numeric) and
           x_solution_numeric >= x_min_world and x_solution_numeric <= x_max_world then

            -- Numerically evaluate the corresponding y-value using one of the original functions
            local y_solution_numeric = _G.evaluate_ast_numeric(f1_ast, {x = x_solution_numeric})

            -- Only plot if y-solution is also a valid number and within world Y-range
            if type(y_solution_numeric) == "number" and not (y_solution_numeric ~= y_solution_numeric) and
               y_solution_numeric >= y_min_world and y_solution_numeric <= y_max_world then

                local screen_x = world_to_screen_x(x_solution_numeric)
                local screen_y = world_to_screen_y(y_solution_numeric)

                -- Draw a cross mark at the intersection point
                graphics.drawLine(screen_x - 5, screen_y, screen_x + 5, screen_y)
                graphics.drawLine(screen_x, screen_y - 5, screen_x, screen_y + 5)

                if display_labels then
                    -- Get exact string representation for x-coordinate
                    local x_label_exact = _G.astToString(x_sol_ast)
                    -- For y-coordinate, you'd ideally substitute x_sol_ast into f1_ast and simplify symbolically.
                    -- This is very complex. For a practical graph label, numeric y is often sufficient.
                    local y_label_numeric = string.format("%.3f", y_solution_numeric) -- Format to 3 decimal places

                    local label_text = string.format("(%s, %s)", x_label_exact, y_label_numeric)
                    graphics.drawText(label_text, screen_x + 8, screen_y - 15) -- Offset label for visibility
                end
            end
        end
    end
end

-- --- Public API for graph.lua ---
-- Export the plotting functions
_G.graphing = {
    plot_explicit_function = plot_explicit_function,
    plot_implicit_function = plot_implicit_function,
    plot_intersections = plot_intersections,
    -- Also expose coordinate helpers if the GUI needs to adjust view
    world_to_screen_x = world_to_screen_x,
    world_to_screen_y = world_to_screen_y,
    screen_to_world_x = screen_to_world_x,
    screen_to_world_y = screen_to_world_y,
    -- Expose world window for potential GUI configuration
    set_world_window = function(xmin, xmax, ymin, ymax)
        x_min_world = xmin
        x_max_world = xmax
        y_min_world = ymin
        y_max_world = ymax
    end
}
-- --- Global Graphing State ---
_G.graph_state = {
    explicit_func_expr = "x^2",
    implicit_func_expr = "x^2 + y^2 - 16",
    
}