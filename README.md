# lean-extract

Reads meaning out of Lean libraries with Lean itself, on GitHub Actions.

- **`src/Extract.lean`**: imports a library and writes one JSON line per user-facing declaration:
  name, kind, module, the constants its proof uses and the constants its statement mentions, and
  (in `full` mode) the pretty-printed statement and docstring.
- **`src/Steps.lean`**: elaborates chosen files and records every tactic step inside chosen
  declarations, with the goals before and after it. A `rw [a, b]` gives one step per rule.
- **`src/ReadOlean.lean`**: reads compiled modules one at a time, without importing anything,
  and writes only their structure: declaration names, kinds, and which names each one uses. This
  is how libraries too large to load at once are read.

| Folder | Library | Workflow | Started by pushing | Output |
|---|---|---|---|---|
| `mathlib/` | Mathlib (pinned in `mathlib/lakefile.toml`) | `extract-mathlib` | `requests/mathlib.json` | declarations in full, proof steps |
| `rh/` | leanprover-community/riemann-hypothesis, from its public cache | `extract-rh` | `requests/rh.json` | structure only |

Results are published as releases. Mathlib is © its authors under Apache-2.0; extracted
statements and steps keep that licence. The riemann-hypothesis archive has no licence, so only
its structure is extracted.
