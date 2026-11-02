# Copyright 2026 Uyuz-ux
# Licensed under the MIT License.

# A tiny demo: structured server logging with logfmt.

import logfmt
import std/times

proc log(level, msg: string, extra: seq[LogfmtPair] = @[]) =
  var pairs = @[
    field("time", now().format("yyyy-MM-dd'T'HH:mm:ss")),
    field("level", level),
    field("msg", msg),
  ]
  pairs.add(extra)
  echo encode(pairs)

log("info", "server started", @[field("port", 8080)])
log("info", "request handled", @[field("path", "/api/users"), field("status", 200), field("ms", 3)])
log("error", "request failed", @[field("path", "/api/users"), field("status", 500), field("err", "db timeout")])

# Parsing someone else's logfmt output:
let line = "level=warn msg=\"disk almost full\" free_mb=512"
let fields = decode(line)
echo "Level: ", fields.getOrDefault("level")
echo "Free MB: ", fields.getOrDefault("free_mb")
