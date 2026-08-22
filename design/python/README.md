# Python package — temporary design notes

These notes plan the `cdfviewer` Python package. They are **temporary**: once
the package is implemented and working, the lasting parts move to
`docs/src/usage/python.md` and `python/README.md`, and this directory is
deleted in the same commit.

## Process

1. Settle the decisions. `decisions.md` holds what is settled; `api.md`
   holds the open API questions, each with options and a recommendation.
   A question is settled by writing its `Decision:` line.
2. Write `workplan.md`: the split into independent work packages with the
   interfaces between them fixed (module names, signatures, exceptions), a
   test plan, and the integration check.
3. Implement the packages in parallel (one agent per package, each on a
   worktree off `feat/python-bindings`), merge, run the integration check
   against the real bundle.
4. Fold the docs, delete `design/`.

## Status

| Step | State |
|---|---|
| Distribution and install decisions | settled (`decisions.md`) |
| API questions | open (`api.md`) |
| Work plan | not started |
| Implementation | not started |
