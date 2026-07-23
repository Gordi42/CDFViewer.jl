# The Command REPL

When you open a file interactively, CDFViewer presents a `CDFViewer>`
prompt. It is a full line-editing REPL, so history, completion, and reverse
search work just like in the Julia REPL or your shell, and it is the fastest
way to drive the viewer. Everything shown here can also be done with the
mouse in [the menu window](menu.md). Both interfaces control the same state.

## Commands at a glance

Type `help` to list every command.

```@example repl
using Main.DocHelpers # hide
session = open_viewer(demo_file("demo.nc")) # hide
repl(session, "help") # hide
```

In the usage strings, `<argument>` is required and `[argument]` is optional.
If you omit an optional argument of a selection command (for example plain
`v` or `p`), an interactive picker opens in the terminal where you choose
from a list with the arrow keys.

A full reference of all commands is available in
[REPL Commands](../reference/commands.md).

## Setting keyword arguments directly

Any input line that contains a `=` and does not start with a command name is
interpreted as plot keyword arguments.

```@example repl
run!(session, "v temperature", "x lon", "y lat", "p heatmap") # hide
repl(session, "colormap=:plasma, title=\"My Temperature Map\"") # hide
close_viewer!(session) # hide
```

This is the main mechanism for customizing plots.
[Customizing Plots](customization.md) has the details.

## History

Every committed line is stored persistently in `~/.cdfviewer_history`
(override the location with the `CDFVIEWER_HISTORY` environment variable),
so your commands survive across sessions.

- **Up/Down arrows** walk through the history. If you already typed the
  beginning of a command, only matching entries are shown (prefix search).
- **Ctrl-R** starts a reverse incremental search through the history,
  exactly like in a shell.

## Tab completion

TAB completes contextually at any point of the line. It completes

- command names at the start of the line,
- variable names after `v`, `varinfo`, and `dims`,
- dimension names after `x`, `y`, `z`, `isel`, `sel`, `pdim`, and `play`,
- plot types after `p`,
- keyword argument names after `get` and `del`, in `key=` position, and
  after a comma in a multi-argument line.

## Exiting

Leave the application with `exit`, `quit`, or just `q`.
