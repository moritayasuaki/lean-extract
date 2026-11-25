"""Read the structure of one share of the archive's modules, a chunk at a time:
download each module's compiled archive, check its SHA-256, unpack it with leantar,
read it with `readolean`, then delete it.
Usage: rh_shard.py MODULES.json N K LEANTAR READOLEAN OUT.jsonl"""
import hashlib, json, os, shutil, subprocess, sys, tempfile, zlib
from pathlib import Path

index = json.load(open(sys.argv[1]))
n, k = int(sys.argv[2]), int(sys.argv[3])
leantar, readolean, out = sys.argv[4], sys.argv[5], sys.argv[6]
base = index["base"]
mine = [m for m in index["modules"] if zlib.crc32(m[0].encode()) % n == k]
print(f"shard {k}/{n}: {len(mine)} modules", flush=True)
CHUNK = 1500
done = failed = 0
with open(out, "w") as sink:
    for start in range(0, len(mine), CHUNK):
        chunk = mine[start:start + CHUNK]
        work = Path(tempfile.mkdtemp(prefix="rh-", dir=os.environ.get("RUNNER_TEMP", "/tmp")))
        try:
            # download in parallel with one curl process
            cfg = work / "curl.cfg"
            with open(cfg, "w") as c:
                for i, (_name, _h, artifact, _sha) in enumerate(chunk):
                    c.write(f'url = "{base}{artifact[:-5]}.art"\noutput = "{work}/{i}.ltar"\n')
            subprocess.run(["curl", "-sSfL", "--retry", "5", "--parallel", "--parallel-max", "64",
                            "-A", "RiemannHypothesisCache/1.0", "-K", str(cfg)], check=False)
            jobs, keep = [], []
            for i, (name, input_hash, _artifact, sha) in enumerate(chunk):
                f = work / f"{i}.ltar"
                if not f.is_file() or hashlib.sha256(f.read_bytes()).hexdigest() != sha:
                    print("bad or missing archive:", name, flush=True)
                    failed += 1
                    continue
                d = work / str(i)
                jobs.append({"file": str(f), "hash": input_hash, "base": [str(d / "lib"), str(d / "ir")]})
                keep.append((i, name))
            subprocess.run([leantar, "-f", "-x", "-j", "-"], input=json.dumps(jobs), text=True, check=True)
            lines = []
            for i, name in keep:
                leaf = name.split(".")[-1] + ".olean"
                found = list((work / str(i)).rglob(leaf))
                if found:
                    lines.append(f"{name}\t{found[0]}")
                else:
                    print("no .olean in archive:", name, flush=True)
                    failed += 1
            (work / "list.tsv").write_text("\n".join(lines) + "\n")
            subprocess.run([readolean, str(work / "list.tsv"), str(work / "out.jsonl")], check=True)
            text = (work / "out.jsonl").read_text()
            sink.write(text)
            done += text.count("\n")
            print(f"  {start + len(chunk)}/{len(mine)} read, {done} written, {failed} failed", flush=True)
        finally:
            shutil.rmtree(work, ignore_errors=True)
print(f"shard {k}: {done} modules written, {failed} failed", flush=True)
