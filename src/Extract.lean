/-
Pass 1: walk the Lean environment after importing a module (by default `Mathlib`) and write one JSON line
per user-facing declaration:

  {"n": name, "k": kind, "m": module, "t": statement (pretty-printed), "d": docstring or null,
   "u": constants the proof or body uses, "y": constants the statement mentions, "i": is an instance}

Usage:  lake exe extract ROOTS PREFIXES OUT.jsonl [WORKERS] [full|structure]
  ROOTS     comma-separated modules to import, for example `Mathlib`
  PREFIXES  comma-separated module prefixes whose declarations are written
  structure writes names, kinds, modules and uses only (no statements, no docstrings)
-/
import Lean
open Lean Meta

def kindOf : ConstantInfo → String
  | .thmInfo _    => "theorem"
  | .defnInfo _   => "def"
  | .axiomInfo _  => "axiom"
  | .opaqueInfo _ => "opaque"
  | .inductInfo _ => "inductive"
  | .ctorInfo _   => "constructor"
  | .recInfo _    => "recursor"
  | .quotInfo _   => "quot"

/-- Machinery: internal names, auxiliary recursors, matchers, private names. -/
def isMachinery (env : Environment) (n : Name) (ci : ConstantInfo) : Bool :=
  n.isInternalDetail || isPrivateName n || isAuxRecursor env n || isNoConfusion env n
    || Meta.isMatcherCore env n || (match ci with | .recInfo _ => true | .quotInfo _ => true | _ => false)

def visible (env : Environment) (ns : Array Name) : Array Name :=
  ns.filter fun c => match env.find? c with
    | some ci => !isMachinery env c ci
    | none => false

def moduleOf (env : Environment) (n : Name) : Name :=
  match env.getModuleIdxFor? n with
  | some i => env.header.moduleNames[i.toNat]!
  | none => .anonymous

def runMeta (env : Environment) (x : MetaM α) : IO α := do
  let opts : Options := ({} : Options)
    |>.set `format.width (100 : Nat) |>.setBool `pp.fullNames false |>.set `maxHeartbeats (0 : Nat)
  let ctx : Core.Context := { fileName := "<extract>", fileMap := default, options := opts, maxHeartbeats := 0 }
  let st : Core.State := { env }
  let (a, _) ← (x.run' {} {}).toIO ctx st
  return a

def ppType (ty : Expr) : MetaM String := do
  try
    let f ← ppExpr ty
    return toString f
  catch _ => return ""

def rowFor (env : Environment) (structureOnly : Bool) (n : Name) (ci : ConstantInfo) : MetaM Json := do
  let t ← if structureOnly then pure "" else ppType ci.type
  let doc ← if structureOnly then pure none else findDocString? env n
  let uses := match ci.value? (allowOpaque := true) with
    | some v => visible env v.getUsedConstants
    | none => #[]
  let mentions := visible env ci.type.getUsedConstants
  return Json.mkObj [
    ("n", toJson n.toString), ("k", toJson (kindOf ci)), ("m", toJson (moduleOf env n).toString),
    ("t", toJson t), ("d", match doc with | some s => toJson s | none => Json.null),
    ("u", toJson (uses.map (·.toString))), ("y", toJson (mentions.map (·.toString))),
    ("i", toJson (Meta.isInstanceCore env n))]

unsafe def main (args : List String) : IO UInt32 := do
  let roots := ((args.getD 0 "Mathlib").splitOn ",").map (·.toName)
  let pfxs := (args.getD 1 "Mathlib").splitOn ","
  let out := args.getD 2 "decls.jsonl"
  let workers := (args.getD 3 "4").toNat!
  let structureOnly := args.getD 4 "full" == "structure"
  initSearchPath (← findSysroot)
  enableInitializersExecution
  IO.eprintln s!"importing {roots}"
  let env ← importModules (roots.toArray.map fun m => { module := m }) {} (loadExts := true)
  let names := env.constants.fold (init := #[]) fun acc n ci =>
    if isMachinery env n ci then acc
    else
      let m := (moduleOf env n).toString
      if pfxs.any (fun p => m.startsWith p) then acc.push (n, ci) else acc
  IO.eprintln s!"{names.size} declarations under {pfxs}"
  let chunk := (names.size + workers - 1) / max workers 1
  let tasks ← (List.range workers).toArray.mapM fun w => IO.asTask do
    let part := names.extract (w * chunk) ((w + 1) * chunk)
    runMeta env do
      let mut lines : Array String := #[]
      for (n, ci) in part do
        lines := lines.push (← rowFor env structureOnly n ci).compress
      return lines
  let h ← IO.FS.Handle.mk out .write
  let mut total := 0
  for t in tasks do
    match ← IO.wait t with
    | .ok lines =>
      for l in lines do h.putStrLn l
      total := total + lines.size
    | .error e => IO.eprintln s!"worker failed: {e}"; return 1
  IO.eprintln s!"wrote {total} lines to {out}"
  return 0
