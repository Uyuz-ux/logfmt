# Copyright 2026 Uyuz-ux
# Licensed under the MIT License.

# Author: Uyuz-ux
# date  : 2026-11-03

## logfmt — encode and decode the logfmt format (key=value pairs) in Nim.
##
## Logfmt is a compact, human-readable structured logging format popularized
## by Heroku and the Go community (`github.com/go-logfmt/logfmt`). Each record
## is a single line of `key=value` pairs:
##
##   level=info msg="user 42 logged in" count=42 duration=0.125
##
## Basic usage:
##
##   import logfmt
##
##   # Encode
##   echo encode([("level", "info"), ("msg", "user 42 logged in"), ("count", "42")])
##   ## level=info msg="user 42 logged in" count=42
##
##   # Decode
##   let fields = decode("level=info msg=\"user 42 logged in\" count=42")
##   assert fields == @[("level", "info"), ("msg", "user 42 logged in"), ("count", "42")]
##
##   # Typed convenience encoding
##   echo encodeTyped([("level", "info"), ("count", 42), ("ok", true)])

import std/[strutils, tables, unicode]

type
  LogfmtError* = object of CatchableError
    ## Raised by `decode` when the input is not valid logfmt.

  LogfmtPair* = tuple[key: string, value: string]
    ## A single key=value pair. Keys and values keep their decoded form.

const
  whitespace = {' ', '\t', '\v', '\r', '\f'}
  needsQuotingExtra = {'=', '"', '\n', '\t'}

proc needsQuoting(s: string): bool =
  ## A token is quoted when it is empty, contains whitespace or any
  ## character that would make the pair ambiguous.
  if s.len == 0:
    return true
  for c in s:
    if c in whitespace or c in needsQuotingExtra:
      return true
  result = false

proc escapeValue(s: string): string =
  ## Escape a value for placement inside double quotes.
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\t': result.add("\\t")
    of '\r': result.add("\\r")
    else: result.add(c)

proc encodeToken(s: string): string =
  ## Render a single key or value as a logfmt token, quoting when needed.
  if needsQuoting(s):
    result = "\"" & escapeValue(s) & "\""
  else:
    result = s

proc encode*(pairs: openArray[LogfmtPair]): string =
  ## Encode key/value pairs into a single logfmt line.
  ##
  ## Values that contain whitespace, `=`, `"` or are empty are quoted, and
  ## embedded quotes, backslashes and newlines are escaped.
  ##
  ##   encode([("msg", "hello world")])  # -> msg="hello world"
  result = newStringOfCap(64)
  for i, pair in pairs:
    if i > 0:
      result.add(' ')
    if pair.key.len == 0:
      raise newException(LogfmtError, "cannot encode an empty key")
    result.add(encodeToken(pair.key))
    result.add('=')
    result.add(encodeToken(pair.value))

proc field*(key: string, value: auto): LogfmtPair =
  ## Build a logfmt pair from any value; it is converted with `$`.
  ## Combine with `encode` for typed logging:
  ##
  ##   encode([field("level", "info"), field("count", 42), field("ok", true)])
  ##   ## level=info count=42 ok=true
  (key: key, value: $value)

proc decode*(line: string): seq[LogfmtPair] {.raises: [LogfmtError].} =
  ## Decode a logfmt line into an ordered sequence of key/value pairs.
  ##
  ## Duplicate keys are preserved in order; use `decodeTable` when the last
  ## occurrence should win. Raises `LogfmtError` on structurally invalid
  ## input, e.g. a token without `=` or an unterminated quoted value.
  result = @[]
  var
    i = 0
    n = line.len

  proc skipWhitespace() =
    while i < n and line[i] in whitespace:
      inc i

  proc parseToken(): string =
    ## Parse one bare or quoted token starting at `i`.
    result = ""
    if i < n and line[i] == '"':
      inc i
      while true:
        if i >= n:
          raise newException(LogfmtError, "unterminated quoted value")
        let c = line[i]
        if c == '\\':
          if i + 1 >= n:
            raise newException(LogfmtError, "dangling escape character")
          let nxt = line[i + 1]
          case nxt
          of 'n': result.add('\n')
          of 't': result.add('\t')
          of 'r': result.add('\r')
          of '"': result.add('"')
          of '\\': result.add('\\')
          else:
            raise newException(LogfmtError, "invalid escape sequence: \\" & nxt)
          inc i, 2
        elif c == '"':
          inc i
          break
        else:
          result.add(c)
          inc i
    else:
      while i < n and line[i] notin whitespace and line[i] != '=':
        result.add(line[i])
        inc i

  skipWhitespace()
  while i < n:
    let key = parseToken()
    if key.len == 0:
      raise newException(LogfmtError, "expected a key at position " & $i)
    if i >= n or line[i] != '=':
      raise newException(LogfmtError, "expected '=' after key \"" & key & "\"")
    inc i
    let value = parseToken()
    result.add((key: key, value: value))
    skipWhitespace()

proc decodeLenient*(line: string): seq[LogfmtPair] =
  ## Best-effort decoder: skips malformed fragments instead of raising.
  ##
  ## Useful for tailing logs that may contain non-logfmt lines (stack traces,
  ## banners). Each valid `key=value` fragment is returned; anything else is
  ## ignored silently.
  result = @[]
  try:
    result = decode(line)
  except LogfmtError:
    # Fall back to scanning pair by pair.
    result = @[]
    var
      start = 0
      n = line.len
    while start < n:
      var eq = find(line, '=', start)
      if eq < 0:
        break
      # find key start: last whitespace before eq
      var keyStart = eq
      while keyStart > start and line[keyStart - 1] notin whitespace:
        dec keyStart
      let key = line[keyStart ..< eq]
      # value: quoted or bare
      var value = ""
      var next = eq + 1
      var consumed = next
      if next < n and line[next] == '"':
        var j = next + 1
        var ok = false
        while j < n:
          if line[j] == '\\':
            inc j, 2
            continue
          if line[j] == '"':
            ok = true
            consumed = j + 1
            break
          inc j
        if ok:
          try:
            value = decode(line[next ..< consumed] & "")[0].value
          except LogfmtError:
            value = ""
          result.add((key: key, value: value))
          start = consumed
          continue
      # bare value
      var j = next
      while j < n and line[j] notin whitespace:
        inc j
      value = line[next ..< j]
      result.add((key: key, value: value))
      start = j

proc decodeTable*(line: string): OrderedTable[string, string] {.raises: [LogfmtError].} =
  ## Decode a logfmt line into an `OrderedTable`. When a key appears more
  ## than once, the last value wins.
  result = initOrderedTable[string, string]()
  for pair in decode(line):
    result[pair.key] = pair.value

proc getOrDefault*(fields: seq[LogfmtPair], key: string, default = ""): string =
  ## Return the first value stored under `key`, or `default` when missing.
  for pair in fields:
    if pair.key == key:
      return pair.value
  result = default

iterator records*(text: string): seq[LogfmtPair] {.raises: [LogfmtError].} =
  ## Iterate over a multi-line logfmt text, decoding every non-empty line
  ## into one record (a `seq[LogfmtPair]`). Whitespace-only lines are
  ## skipped. Raises `LogfmtError` on the first structurally invalid line —
  ## use `recordsLenient` to skip bad lines instead.
  ##
  ##   for rec in records(logFileText):
  ##     echo rec.getOrDefault("level")
  for line in text.splitLines():
    if strutils.strip(line).len == 0:
      continue
    yield decode(line)

iterator recordsLenient*(text: string): seq[LogfmtPair] =
  ## Like `records`, but silently skips lines that are not valid logfmt.
  ## Useful for real-world log files that mix records with banners, stack
  ## traces or separator lines. Valid `key=value` fragments inside a broken
  ## line are still recovered (see `decodeLenient`).
  ##
  ##   for rec in recordsLenient(messyLogText):
  ##     if rec.getOrDefault("level") == "error":
  ##       echo rec
  for line in text.splitLines():
    if strutils.strip(line).len == 0:
      continue
    yield decodeLenient(line)

proc decodeLines*(text: string): seq[seq[LogfmtPair]] {.raises: [LogfmtError].} =
  ## Eager variant of `records`: decode every non-empty line of a multi-line
  ## text and return all records. Raises `LogfmtError` on invalid input.
  result = @[]
  for rec in records(text):
    result.add(rec)

proc encodeLines*(records: openArray[seq[LogfmtPair]]): string =
  ## Encode multiple records into a multi-line logfmt text — the inverse of
  ## `decodeLines`. Each record becomes one line, joined with newlines (no
  ## trailing newline); empty records are skipped, so the round trip
  ## `decodeLines(encodeLines(recs)) == recs` holds whenever `recs` contains
  ## no empty records. Raises `LogfmtError` if any pair has an empty key
  ## (see `encode`).
  ##
  ##   let text = encodeLines([@[field("level", "info")],
  ##                           @[field("level", "error"), field("retries", 3)]])
  ##   ## level=info\nlevel=error retries=3
  result = newStringOfCap(64)
  var first = true
  for rec in records:
    if rec.len == 0:
      continue
    if not first:
      result.add('\n')
    first = false
    result.add(encode(rec))
