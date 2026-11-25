"""Merge steps-*.json shards into one file. Usage: merge.py OUT.json IN1.json IN2.json ..."""
import json, sys
out = {}
for p in sys.argv[2:]:
    try: out.update(json.load(open(p)))
    except Exception as e: print('skip', p, e, file=sys.stderr)
json.dump(out, open(sys.argv[1], 'w'), separators=(',', ':'), ensure_ascii=False)
print(len(out), 'files')
