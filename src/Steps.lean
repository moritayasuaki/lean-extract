/-
Pass 2: elaborate source files and record every tactic step inside chosen declarations:
the tactic's text and position, and the goals before and after it (pretty-printed).

Usage:  lake exe steps ROOT TARGETS.json OUT.json
  ROOT          directory the target file paths are relative to (for example the Mathlib checkout)
  TARGETS.json  [{"file": "Mathlib/Algebra/Ring/Defs.lean", "name": "two_mul", "line": 182, "n": 2}, ...]
                line = first line of the declaration (1-based), n = number of lines
  OUT.json      {"Mathlib/Algebra/Ring/Defs.lean": {"two_mul": [step, ...]}, ...}
                step = {"l": line, "c": column, "el": end line, "ec": end column, "k": syntax kind,
                        "s": tactic text, "b": [goals before], "a": [goals after]}
-/
import Lean
open Lean Elab Meta

structure Target where
  file : String
  name : String
  line : Nat
  n : Nat
  deriving FromJson, Inhabited

def ppGoals (ci : ContextInfo) (mctx : MetavarContext) (gs : List MVarId) : IO (Array String) := do
  try
    ({ ci with mctx }).runMetaM {} do
      gs.toArray.mapM fun g => return toString (← ppGoal g)
  catch _ => return #[]

def stepsOfFile (root : String) (file : String) (targets : Array Target) : IO Json := do
  let path := System.FilePath.mk root / file
  let input ← IO.FS.readFile path
  let inputCtx := Parser.mkInputContext input path.toString
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let modName := ((file.replace ".lean" "").replace "/" ".").toName
  let (env, messages) ← processHeader header {} messages inputCtx (trustLevel := 1024) (mainModule := modName)
  let cmdState := { Command.mkState env messages {} with infoState.enabled := true }
  let s ← IO.processCommands inputCtx parserState cmdState
  let fmap := inputCtx.fileMap
  -- collect every tactic node with its context
  let mut found : Array (ContextInfo × TacticInfo) := #[]
  for t in s.commandState.infoState.trees do
    found := t.foldInfo (init := found) fun ci info acc =>
      match info with
      | .ofTacticInfo ti => acc.push (ci, ti)
      | _ => acc
  let mut perTarget : Array (String × Json) := #[]
  for tg in targets do
    let mut steps : Array Json := #[]
    for (ci, ti) in found do
      let some r := ti.stx.getRange? (canonicalOnly := true) | continue
      let p := fmap.toPosition r.start
      let q := fmap.toPosition r.stop
      unless tg.line ≤ p.line && p.line < tg.line + tg.n do continue
      let text := (String.Pos.Raw.extract input r.start r.stop)
      let before ← ppGoals ci ti.mctxBefore ti.goalsBefore
      let after ← ppGoals ci ti.mctxAfter ti.goalsAfter
      steps := steps.push <| Json.mkObj [
        ("l", toJson p.line), ("c", toJson p.column), ("el", toJson q.line), ("ec", toJson q.column),
        ("k", toJson ti.stx.getKind.toString), ("s", toJson text),
        ("b", toJson before), ("a", toJson after)]
    perTarget := perTarget.push (tg.name, Json.arr steps)
  let errs := s.commandState.messages.toList.filter (·.severity == .error) |>.length
  if errs > 0 then IO.eprintln s!"{file}: {errs} errors while elaborating"
  return Json.mkObj (perTarget.toList)

unsafe def main (args : List String) : IO UInt32 := do
  let root := args.getD 0 "."
  let targetsPath := args.getD 1 "targets.json"
  let out := args.getD 2 "steps.json"
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let raw ← IO.FS.readFile targetsPath
  let targets ← IO.ofExcept <| (Json.parse raw >>= fromJson? : Except String (Array Target))
  let files := targets.foldl (init := (#[] : Array String)) fun acc t =>
    if acc.contains t.file then acc else acc.push t.file
  let mut result : Array (String × Json) := #[]
  let mut k := 0
  for f in files do
    k := k + 1
    IO.eprintln s!"[{k}/{files.size}] {f}"
    try
      let j ← stepsOfFile root f (targets.filter (·.file == f))
      result := result.push (f, j)
    catch e => IO.eprintln s!"failed {f}: {e}"
  IO.FS.writeFile out (Json.mkObj result.toList).compress
  return 0
