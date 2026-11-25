/-
Read compiled modules one at a time, without importing anything, and write their structure:
one JSON line per module,

  {"m": module, "i": [imported modules], "d": [[name, kind, [constants its value uses]], ...]}

No statements, proofs or docstrings are written: only names, kinds and which names use which.
For a module in Lean's module system, the `.olean.server` and `.olean.private` parts are read as
well, since the private part holds every declaration with its value.

Usage:  readolean LIST.tsv OUT.jsonl
  LIST.tsv   one line per module: `Module.Name<TAB>/path/to/Name.olean`
-/
import Lean
open Lean

def kindOf : ConstantInfo → String
  | .thmInfo _    => "theorem"
  | .defnInfo _   => "def"
  | .axiomInfo _  => "axiom"
  | .opaqueInfo _ => "opaque"
  | .inductInfo _ => "inductive"
  | .ctorInfo _   => "constructor"
  | .recInfo _    => "recursor"
  | .quotInfo _   => "quot"

def skip (ci : ConstantInfo) : Bool :=
  ci.name.isInternalDetail || (match ci with | .recInfo _ => true | .quotInfo _ => true | _ => false)

def usesOf (ci : ConstantInfo) : Array String :=
  match ci.value? (allowOpaque := true) with
  | some v => (v.getUsedConstants.filter (!·.isInternalDetail)).map (·.toString)
  | none => #[]

/-- Read one module's parts and turn what we need into one JSON line. -/
unsafe def moduleLine (mod : String) (path : String) : IO String := do
  let main ← readModuleData path
  let parts : Array (ModuleData × CompactedRegion) ← if main.1.isModule then do
      let server ← CompactedRegion.read (α := ModuleData) (path ++ ".server") #[main.2]
      let priv ← CompactedRegion.read (α := ModuleData) (path ++ ".private") #[main.2, server.2]
      pure #[main, server, priv]
    else pure #[main]
  let full := match parts.back? with
    | some p => p.1
    | none => main.1
  let imports := main.1.imports.map (·.module.toString)
  let decls := full.constants.filter (!skip ·) |>.map fun ci =>
    Json.arr #[toJson ci.name.toString, toJson (kindOf ci), toJson (usesOf ci)]
  let line := (Json.mkObj [("m", toJson mod), ("i", toJson imports), ("d", Json.arr decls)]).compress
  -- The regions are not freed: names in `line`'s inputs may share memory with them, and the
  -- pages are file-backed, so the system can reclaim them.
  return line

unsafe def main (args : List String) : IO UInt32 := do
  let listPath := args.getD 0 "modules.tsv"
  let out := args.getD 1 "structure.jsonl"
  let h ← IO.FS.Handle.mk out .write
  let mut ok := 0
  let mut failed := 0
  for raw in ← IO.FS.lines listPath do
    match raw.splitOn "\t" with
    | [mod, path] =>
      try
        h.putStrLn (← moduleLine mod path)
        ok := ok + 1
      catch e =>
        IO.eprintln s!"failed {mod}: {e}"
        failed := failed + 1
    | _ => pure ()
  IO.eprintln s!"read {ok} modules, {failed} failed"
  return 0
