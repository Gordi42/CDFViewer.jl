module Parsing

using DataStructures
using GLMakie

special_values = Dict(
    "true" => true,
    "false" => false,
    "nothing" => nothing,
    "identity" => identity,
    "log" => log,
    "log2" => log2,
    "log10" => log10,
    "sqrt" => sqrt,
)

"""
The module keyword values are evaluated in.

A keyword value is user input, so it never gets to touch `Main` -- it is
evaluated here and nowhere else. The `using`s are what make the names a
plot attribute usually wants resolve: `Makie.Symlog10(1e-2)`,
`Makie.automatic`, `RGBf(1, 0, 0)`, `Point2f(0, 0)`, `Day(1)`.
"""
module KwargSandbox
    using Makie
    using GLMakie
    using Colors
    using Dates
end

"""
    kwarg_entries(kw_str)

What a `key=value` line names, as the text of each key and each value.

The values come back unparsed, which is the point: reading one can
evaluate an expression, and a caller that only wants to know *which*
keywords a line mentions should not pay for that -- nor set off the
errors a bad value reports when it is finally read for real.
"""
function kwarg_entries(kw_str::AbstractString)::Vector{Pair{String, String}}
    entries = Pair{String, String}[]
    isempty(kw_str) && return entries

    # Split by commas, but be careful not to split inside parentheses, brackets, or quotes
    pairs = String[]
    current_pair = ""
    paren_count = 0
    bracket_count = 0
    in_quotes = false
    quote_char = ' '
    
    for char in kw_str
        if !in_quotes && (char == '"' || char == '\'')
            in_quotes = true
            quote_char = char
        elseif in_quotes && char == quote_char
            in_quotes = false
        elseif !in_quotes && char == '('
            paren_count += 1
        elseif !in_quotes && char == ')'
            paren_count -= 1
        elseif !in_quotes && char == '['
            bracket_count += 1
        elseif !in_quotes && char == ']'
            bracket_count -= 1
        elseif !in_quotes && char == ',' && paren_count == 0 && bracket_count == 0
            push!(pairs, current_pair)
            current_pair = ""
            continue
        end
        current_pair *= char
    end
    push!(pairs, current_pair)
    
    for pair in pairs
        parts = split(pair, '=', limit=2)
        length(parts) == 2 || continue
        push!(entries, String(strip(parts[1])) => String(strip(parts[2])))
    end
    entries
end

function parse_kwargs(kw_str::AbstractString)::OrderedDict{Symbol, Any}
    kw_dict = OrderedDict{Symbol, Any}()
    for (key, val_str) in kwarg_entries(kw_str)
        kw_dict[Symbol(key)] = parse_value(val_str)
    end
    kw_dict
end

"""
    parse_value(val_str)

Turn the right hand side of one `key=value` pair into a Julia value.

The literal forms are recognised by hand, in the order below. Whatever
no branch claims is handed to [`eval_expression`](@ref), which is what
makes values like `Makie.Symlog10(1e-2)` more than a string.
"""
function parse_value(val_str::AbstractString)
    if (startswith(val_str, '"') && endswith(val_str, '"')) ||
       (startswith(val_str, '\'') && endswith(val_str, '\''))
        # String: remove quotes
        return val_str[2:end-1]
    elseif startswith(val_str, ":")
        return Symbol(val_str[2:end])
    elseif occursin(r"^\[.*\]$", val_str)
        # Array: e.g. [1, 2, 3] or [1.0, 2.0, 3.0]
        inner = val_str[2:end-1]
        if isempty(strip(inner))
            return []
        else
            vals = [strip(v) for v in split(inner, ',')]
            return [parse_array_element(v) for v in vals]
        end
    elseif occursin(r"^\(.*\)$", val_str)
        # Tuple: e.g. (0.2, -1, 3.19)
        inner = val_str[2:end-1]
        if isempty(strip(inner))
            return ()
        else
            vals = [strip(v) for v in split(inner, ',')]
            # Handle single-element tuple with trailing comma
            if length(vals) == 1 && endswith(vals[1], ',')
                vals[1] = rstrip(vals[1], ',')
                return tuple(parse_tuple_element(vals[1]))
            else
                return tuple((parse_tuple_element(v) for v in vals)...)
            end
        end
    elseif occursin(':', val_str) && count(':', val_str) ≤ 2
        # Range: e.g. 1:10, 1:2:10, 5:15
        #
        # a colon proves nothing on its own -- `Dict(:a => 1)` carries one
        # too -- so a range that does not parse falls through to the
        # expression path rather than stopping here as a string
        rng = try
            parse_range(val_str)
        catch
            nothing
        end
        rng === nothing || return rng
    elseif occursin(r"^\d+\.?\d*[eE][+-]?\d+$", val_str) || occursin(r"^\d*\.\d+[eE][+-]?\d+$", val_str)
        # Scientific notation: e.g. 1.5e-3, 2E+5, .5e3
        return parse(Float64, val_str)
    elseif tryparse(Int, val_str) !== nothing
        return parse(Int, val_str)
    elseif tryparse(Float64, val_str) !== nothing
        return parse(Float64, val_str)
    elseif haskey(special_values, val_str)
        return special_values[val_str]
    end
    eval_expression(val_str)
end

"""
    eval_expression(val_str)

Evaluate `val_str` as a Julia expression, or hand it back unchanged.

Only a genuine `Expr` is evaluated. A bare word parses to a `Symbol`, and
a bare word is meant as a word: `title=Foo` is the string `"Foo"`, and a
save option `filename=output` is a file name, not a global to look up.
"""
function eval_expression(val_str::AbstractString)
    expr = try
        Meta.parse(val_str)
    catch
        # not Julia at all -- e.g. an absolute path like /tmp/plot.png
        return val_str
    end
    expr isa Expr || return val_str
    expr.head === :incomplete && return val_str
    try
        return Core.eval(KwargSandbox, expr)
    catch e
        # a call that fails is nearly always a typo, and left as a string
        # it dies much later inside `setproperty!` with a `MethodError`
        # that names nothing the user wrote -- so say so here, while the
        # expression is still in hand. Anything else stays quiet: a file
        # name like `output.png` parses as an expression too, and every
        # save options line would shout.
        is_call(val_str, expr) &&
            @error "Failed to evaluate keyword value '$val_str': $e"
        return val_str
    end
end

"""
    is_call(val_str, expr)

Whether the value was written as a call, e.g. `Makie.Symlog10(1e-2)`.

The parentheses are checked on the string, not on `expr`: an operator
like the `:` in `1:foo` also parses to a `:call`, and a word with a colon
in it is a plain string, not a mistake worth an error message.
"""
is_call(val_str::AbstractString, expr::Expr)::Bool =
    occursin('(', val_str) && has_call_node(expr)

"Whether `expr` contains a call anywhere in its tree."
has_call_node(expr)::Bool =
    expr isa Expr && (expr.head === :call || any(has_call_node, expr.args))

# Helper function to parse array elements
function parse_array_element(v::Union{String, SubString{String}})
    v = strip(v)
    if tryparse(Int, v) !== nothing
        return parse(Int, v)
    elseif tryparse(Float64, v) !== nothing
        return parse(Float64, v)
    elseif startswith(v, ":")
        return Symbol(v[2:end])
    elseif haskey(special_values, v)
        return special_values[v]
    elseif (startswith(v, '"') && endswith(v, '"')) || 
           (startswith(v, '\'') && endswith(v, '\''))
        return v[2:end-1]  # Remove quotes
    else
        return v
    end
end

# Helper function to parse tuple elements
function parse_tuple_element(v::Union{String, SubString})
    v = strip(v)
    if tryparse(Int, v) !== nothing
        return parse(Int, v)
    elseif tryparse(Float64, v) !== nothing
        return parse(Float64, v)
    elseif startswith(v, ":")
        return Symbol(v[2:end])
    elseif haskey(special_values, v)
        return special_values[v]
    elseif (startswith(v, '"') && endswith(v, '"')) || 
           (startswith(v, '\'') && endswith(v, '\''))
        return v[2:end-1]  # Remove quotes
    else
        return v
    end
end

# Helper function to parse ranges
function parse_range(range_str::Union{String, SubString{String}})
    parts = split(range_str, ':')
    if length(parts) == 2
        # start:stop format
        start = parse_number(parts[1])
        stop = parse_number(parts[2])
        return start:stop
    elseif length(parts) == 3
        # start:step:stop format
        start = parse_number(parts[1])
        step = parse_number(parts[2])
        stop = parse_number(parts[3])
        return start:step:stop
    else
        throw(ArgumentError("Invalid range format: $range_str"))
    end
end

function parse_number(num_str::Union{String, SubString{String}})
    if tryparse(Int, num_str) !== nothing
        return parse(Int, num_str)
    elseif tryparse(Float64, num_str) !== nothing
        return parse(Float64, num_str)
    else
        throw(ArgumentError("Cannot parse number from string: $num_str"))
    end

end

end