# CDFViewer documentation

The manual is built with [Documenter.jl](https://documenter.juliadocs.org)
and deployed to GitHub Pages by the `docs` job in `.github/workflows/CI.yml`.

Screenshots and REPL transcripts are **generated at build time**: the
`@example` blocks in the pages drive the real application headlessly (via
`doc_helpers.jl`) against small synthetic datasets (`demo_data.jl`). Nothing
is checked in as an image, so the docs cannot go stale — if a page's example
breaks, the docs build fails.

## Building locally

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Then open `docs/build/index.html`. A display (or `xvfb-run`) is required
because GLMakie renders the figures.
