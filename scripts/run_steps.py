"""Run the steps reader once per file, so each file's memory is freed when its process ends.
Usage: run_steps.py STEPS_BIN ROOT TARGETS.json OUT.json [OPTIONS]  (run under `lake env`)"""
import json, os, subprocess, sys, tempfile, time
binary, root, targets_path, out_path = sys.argv[1:5]
opts = sys.argv[5] if len(sys.argv) > 5 else ""
targets = json.load(open(targets_path))
files = sorted({t["file"] for t in targets})
result, failed = {}, []
for k, f in enumerate(files, 1):
    with tempfile.TemporaryDirectory() as d:
        tin, tout = os.path.join(d, "t.json"), os.path.join(d, "o.json")
        json.dump([t for t in targets if t["file"] == f], open(tin, "w"))
        t0 = time.time()
        try:
            r = subprocess.run([binary, root, tin, tout, opts], capture_output=True, text=True, timeout=1200)
            err = (r.stderr or "").strip().splitlines()
            print(f"[{k}/{len(files)}] {f} exit={r.returncode} {time.time() - t0:.0f}s", flush=True)
            for line in err[1:4]:
                print("   ", line[:300], flush=True)
            if r.returncode == 0 and os.path.exists(tout):
                result.update(json.load(open(tout)))
            else:
                failed.append(f)
        except subprocess.TimeoutExpired:
            print(f"[{k}/{len(files)}] {f} timed out", flush=True)
            failed.append(f)
json.dump(result, open(out_path, "w"), separators=(",", ":"), ensure_ascii=False)
print(f"done: {len(result)} files, {len(failed)} failed", flush=True)
