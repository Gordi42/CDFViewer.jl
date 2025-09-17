using REPL
using REPL.LineEdit

repl = Base.active_repl;



# juliamode = repl.interface.modes[1]
shellprompt = repl.interface.modes[2]

# Disable backspace keymap in shell mode
for (key, action) in shellprompt.keymap_dict
    println("Key: ", key, " Action: ", action)
end


# newprompt = shellprompt

# function trigger(state::LineEdit.MIState, repl::LineEditREPL, char::AbstractString)
#     iobuffer = LineEdit.buffer(state)
#     if position(iobuffer) == 0
#         LineEdit.transition(state, newprompt) do
#             # Type of LineEdit.PromptState
#             prompt_state = LineEdit.state(state, newprompt)
#             prompt_state.input_buffer = copy(iobuffer)
#         end
#     else
#         LineEdit.edit_insert(state, char)
#     end
# end

# # Trigger mode transition to shell when a '6' is written
# # at the beginning of a line
# juliamode.keymap_dict['6'] = trigger

# newprompt = REPL.Prompt("[hello] ")

# for name in fieldnames(REPL.Prompt)
#     if name != :prompt
#         setfield!(newprompt, name, getfield(shellprompt, name))
#     end
# end

# push!(repl.interface.modes, newprompt);

# juliamode.keymap_dict['6'] = trigger

