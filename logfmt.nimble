version       = "0.3.0"
author        = "Uyuz-ux"
description   = "Encode and decode the logfmt (key=value) structured logging format."
license       = "MIT"
srcDir        = "src"

# Deps

requires "nim >= 1.6.0"

task test, "Run the test suite":
  exec "nim c -r --hints:off --path:src -o:nimcache/tlogfmt tests/tlogfmt.nim"
