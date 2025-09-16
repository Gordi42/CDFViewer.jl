module Output

using Logging
using ProgressMeter
using GLMakie

using ..Constants
using ..Parsing

mutable struct OutputSettings
    filename::String
    framerate::Int
    px_per_unit::Int
    range::Union{Nothing, StepRange{Int64}, UnitRange{Int64}}
    work_dir::String
end

function OutputSettings(filename::String;
    framerate::Int=30,
    px_per_unit::Int=1,
    range::Union{Nothing, StepRange{Int64}, UnitRange{Int64}}=nothing,
    work_dir::String=pwd(),
    )
    OutputSettings(filename, framerate, px_per_unit, range, work_dir)
end

# ============================================================
#  Argument Parsing
# ============================================================
function apply_settings_string!(settings::OutputSettings, settings_str::AbstractString)::OutputSettings
    isempty(settings_str) && return settings

    kw_dict = Parsing.parse_kwargs(settings_str)
    for (k, v) in kw_dict
        if hasproperty(settings, k)
            try
                setproperty!(settings, k, v)
            catch e
                @warn "Failed to set OutputSettings.$k with value $v: $e"
            end
        else
            fields = fieldnames(typeof(settings))
            @warn "Unknown OutputSettings property: $k. Available fields: $fields"
            continue
        end
    end
    settings
end

# ============================================================
#  Directory Management
# ============================================================

macro cd(settings, expr)
    return quote
        old_dir = pwd()
        try
            cd($(esc(settings)).work_dir)
            $(esc(expr))
        finally
            cd(old_dir)
        end
    end
end

# ============================================================
#  File Writing
# ============================================================
function savefig(fig::Figure, settings::OutputSettings)::Nothing
    filename, tmp_file = @cd settings get_filenames(settings, Constants.IMAGE_FILE_FORMATS)
    save(tmp_file, fig, px_per_unit=settings.px_per_unit)
    @cd settings mv(tmp_file, filename)
    @info "Saved figure to $filename"
    nothing
end

function record_scene(fig::Figure, settings::OutputSettings, slider::Slider)::Nothing
    filename, tmp_file = @cd settings get_filenames(settings, Constants.VIDEO_FILE_FORMATS)

    # Get the range of the slider
    its = isnothing(settings.range) ? slider.range[] : settings.range
    
    # Make a Progress Bar
    p = Progress(length(its); desc="Recording", 
        barglyphs=BarGlyphs('|','█', ['▁' ,'▂' ,'▃' ,'▄' ,'▅' ,'▆', '▇'],' ','|',),
        barlen=10)

    record(fig, tmp_file, its; framerate=settings.framerate) do it
        slider.value[] = it
        next!(p)
    end
    @info "Finished recording. Saving ..."
    @cd settings mv(tmp_file, filename)
    @info "Saved animation to $filename"
    nothing
end


# ============================================================
#  File Operations
# ============================================================

function get_filenames(settings::OutputSettings, available_exts::Vector{String})::Tuple{String,String}
    filename = settings.filename
    filename = check_extension(filename, available_exts)
    filename = check_filename(filename)
    # We first write the file into a temporary file and then move it to the final
    # destination to avoid partial files in case of errors
    # (also avoids issues on remote filesystems)
    tmp_file = tempname() * splitext(filename)[2]
    (filename, tmp_file)
end

function check_extension(filename::String, available_exts::Vector{String})::String
    for ext in available_exts
        endswith(filename, ext) && return filename
    end
    base, ext = splitext(filename)
    fallback = available_exts[1]
    isempty(ext) && return base * fallback
    @warn "File extension $ext not recognized. Using $fallback instead."
    return base * fallback
end

function rename_filename(filename::String)::String
    base, ext = splitext(filename)
    # We need to remove a possible (n) at the end of the base
    r = r"\(\d+\)$"
    base = replace(base, r => "")
    idx = 1
    while isfile("$base($idx)$ext")
        idx += 1
    end
    @info "Renaming to $base($idx)$ext"
    "$base($idx)$ext"
end

function check_filename(filename::String)::String
    !isfile(filename) && return filename
    @warn "File $filename already exists. Rename to avoid overwriting."
    rename_filename(filename)
end
        
function move_file(src::String, dest::String)::Nothing
    dest = check_filename(dest)
    mv(src, dest)
    nothing
end

end