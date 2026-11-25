"""List the archive's compiled modules from its public CI cache, using the archive's own
cache client (scripts/ci-cache-get.py) to find and check the module manifest.
Usage: rh_modules.py ARCHIVE_CLONE OUT.json
OUT.json: [[module, input_hash, artifact, sha256], ...]"""
import importlib.util, json, sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("ci_cache_get", root / "scripts" / "ci-cache-get.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

identity = cc.current_identity(root)
record = cc.find_record(root, identity, 100)
cached = {}
if record is None:
    record, cached = cc.baseline_record(identity)
if record is None:
    sys.exit("no published cache matches the archive's current build inputs")
fetcher = lambda key, maximum=cc.MAX_JSON: cached[key] if key in cached else cc.fetch(key, maximum)
_contents, shas, modules = cc.validated_blobs(record, identity, fetcher)
rows = [[name, input_hash, artifact, shas[artifact]] for name, input_hash, artifact in modules]
json.dump({"repository": cc.REPOSITORY, "base": f"{cc.PUBLIC_BASE}/artifacts/{cc.REPOSITORY}/",
           "candidate_head": record.get("candidate_head"), "toolchain": identity["toolchain"],
           "modules": rows}, open(sys.argv[2], "w"))
print(len(rows), "modules; cache record for", record.get("candidate_head"))
