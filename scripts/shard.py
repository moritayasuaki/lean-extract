"""Split targets.json into N shards by file (all targets of a file stay together). Usage: shard.py targets.json N K > out.json"""
import json, sys, zlib
targets, n, k = json.load(open(sys.argv[1])), int(sys.argv[2]), int(sys.argv[3])
json.dump([t for t in targets if zlib.crc32(t['file'].encode()) % n == k], sys.stdout)
