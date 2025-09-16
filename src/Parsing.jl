module Parsing

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

function parse_kwargs(kw_str::AbstractString)::Dict{Symbol, Any}
    kw_dict = Dict{Symbol, Any}()
    isempty(kw_str) && return kw_dict
    
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
        key = Symbol(strip(parts[1]))
        val_str = strip(parts[2])

        
        # Parse the value
        if (startswith(val_str, '"') && endswith(val_str, '"')) || 
           (startswith(val_str, '\'') && endswith(val_str, '\''))
            # String: remove quotes
            val = val_str[2:end-1]
        elseif startswith(val_str, ":")
            val = Symbol(val_str[2:end])
        elseif occursin(r"^\[.*\]$", val_str)
            # Array: e.g. [1, 2, 3] or [1.0, 2.0, 3.0]
            inner = val_str[2:end-1]
            if isempty(strip(inner))
                val = []
            else
                vals = [strip(v) for v in split(inner, ',')]
                val = [parse_array_element(v) for v in vals]
            end
        elseif occursin(r"^\(.*\)$", val_str)
            # Tuple: e.g. (0.2, -1, 3.19)
            inner = val_str[2:end-1]
            if isempty(strip(inner))
                val = ()
            else
                vals = [strip(v) for v in split(inner, ',')]
                # Handle single-element tuple with trailing comma
                if length(vals) == 1 && endswith(vals[1], ',')
                    vals[1] = rstrip(vals[1], ',')
                    val = tuple(parse_tuple_element(vals[1]))
                else
                    val = tuple((parse_tuple_element(v) for v in vals)...)
                end
            end
        elseif occursin(':', val_str) && count(':', val_str) ≤ 2
            # Range: e.g. 1:10, 1:2:10, 5:15
            val = try
                parse_range(val_str)
            catch
                val_str
            end
        elseif occursin(r"^\d+\.?\d*[eE][+-]?\d+$", val_str) || occursin(r"^\d*\.\d+[eE][+-]?\d+$", val_str)
            # Scientific notation: e.g. 1.5e-3, 2E+5, .5e3
            val = parse(Float64, val_str)
        elseif tryparse(Int, val_str) !== nothing
            val = parse(Int, val_str)
        elseif tryparse(Float64, val_str) !== nothing
            val = parse(Float64, val_str)
        elseif haskey(special_values, val_str)
            val = special_values[val_str]
        else
            val = val_str
        end
        kw_dict[key] = val
    end
    kw_dict
end

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