# lean-extract

Reads meaning out of Lean libraries with Lean itself, on GitHub Actions.

- **`src/Extract.lean`**: imports a library and writes one JSON line per user-facing declaration:
  name, kind, module, the constants its proof uses and the constants its statement mentions, and
  (in `full` mode) the pretty-printed statement and docstring. Internal names, auxiliary
  recursors and matchers are skipped.
- **`src/Steps.lean`**: elaborates chosen files and records every tactic step inside chosen
  declarations, with the goals before and after it. A `rw [a, b]` gives one step per rule, so a
  rewrite chain becomes a chain of goals.

Each library has its own folder with its own Lean version: `mathlib/` (Mathlib, pinned in
`mathlib/lakefile.toml`). Run a workflow from the Actions tab, or with
`gh workflow run extract-mathlib -f pass=both`. Results are published as releases.

Mathlib is © its authors under Apache-2.0; extracted statements and steps keep that licence.
