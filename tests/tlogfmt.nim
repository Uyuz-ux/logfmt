# Copyright 2026 Uyuz-ux
# Licensed under the MIT License.

import unittest
import std/[tables, unicode]
import logfmt

suite "encode":
  test "simple pairs":
    check(encode([("level", "info"), ("msg", "started")]) == "level=info msg=started")

  test "quotes values with spaces":
    check(encode([("msg", "hello world")]) == "msg=\"hello world\"")

  test "quotes empty values":
    check(encode([("note", "")]) == "note=\"\"")

  test "escapes quotes and backslashes":
    check(encode([("msg", "he said \"hi\"")]) == "msg=\"he said \\\"hi\\\"\"")
    check(encode([("path", "C:\\tmp")]) == "path=C:\\tmp")
    check(encode([("path", "C:\\tmp with space")]) == "path=\"C:\\\\tmp with space\"")

  test "escapes newlines and tabs":
    check(encode([("msg", "a\nb")]) == "msg=\"a\\nb\"")
    check(encode([("msg", "a\tb")]) == "msg=\"a\\tb\"")

  test "quotes values containing equals":
    check(encode([("expr", "a=b")]) == "expr=\"a=b\"")

  test "rejects empty keys":
    expect LogfmtError:
      discard encode([("", "x")])

suite "field":
  test "converts typed values":
    check(encode([field("level", "info"), field("count", 42), field("ok", true), field("ratio", 0.5)]) ==
      "level=info count=42 ok=true ratio=0.5")

suite "decode":
  test "simple pairs":
    check(decode("level=info msg=started") ==
      @[("level", "info"), ("msg", "started")])

  test "quoted values with spaces":
    check(decode("msg=\"hello world\" level=info") ==
      @[("msg", "hello world"), ("level", "info")])

  test "escape sequences":
    check(decode("msg=\"a\\nb\\tc\\\"d\"") == @[("msg", "a\nb\tc\"d")])

  test "extra whitespace is ignored":
    check(decode("  a=1   b=2  ") == @[("a", "1"), ("b", "2")])

  test "duplicate keys are preserved in order":
    check(decode("k=1 k=2") == @[("k", "1"), ("k", "2")])

  test "rejects token without equals":
    expect LogfmtError:
      discard decode("levelinfo")

  test "rejects unterminated quote":
    expect LogfmtError:
      discard decode("msg=\"unterminated")

  test "rejects invalid escape":
    expect LogfmtError:
      discard decode("msg=\"bad\\xescape\"")

suite "decodeTable":
  test "last value wins":
    let t = decodeTable("k=1 k=2 other=x")
    check(t["k"] == "2")
    check(t["other"] == "x")
    check(t.len == 2)

suite "decodeLenient":
  test "recovers valid pairs from mixed content":
    let pairs = decodeLenient("panic: runtime error level=error goroutine=1")
    check(pairs.getOrDefault("level") == "error")
    check(pairs.getOrDefault("goroutine") == "1")

suite "getOrDefault":
  test "first match wins":
    let fields = decode("k=first k=second")
    check(fields.getOrDefault("k") == "first")
    check(fields.getOrDefault("missing", "fallback") == "fallback")

suite "roundtrip":
  test "encode then decode preserves data":
    let original: seq[LogfmtPair] = @[("level", "warn"), ("msg", "disk almost full"),
        ("path", "C:\\var\\log"), ("note", "")]
    check(decode(encode(original)) == original)

suite "records":
  test "decodes each non-empty line":
    let text = "level=info msg=started count=1\nlevel=error msg=failed count=2"
    var levels: seq[string] = @[]
    var counts: seq[string] = @[]
    for rec in records(text):
      levels.add(rec.getOrDefault("level"))
      counts.add(rec.getOrDefault("count"))
    check(levels == @["info", "error"])
    check(counts == @["1", "2"])

  test "skips empty and whitespace-only lines":
    let text = "\nlevel=info\n   \nlevel=warn\n\n"
    var n = 0
    for rec in records(text):
      inc n
      check(rec.len == 1)
    check(n == 2)

  test "preserves quoted values per record":
    let text = "msg=\"hello world\" ok=true\nmsg=\"bye now\""
    var msgs: seq[string] = @[]
    for rec in records(text):
      msgs.add(rec.getOrDefault("msg"))
    check(msgs == @["hello world", "bye now"])

  test "handles CRLF line endings":
    let text = "level=info\r\nlevel=warn\r\n"
    var n = 0
    for rec in records(text):
      inc n
      check(rec.len == 1)
    check(n == 2)

  test "raises on the first invalid line":
    expect LogfmtError:
      for rec in records("level=info\nnotapair\n"):
        discard rec

  test "single-line text behaves like decode":
    var n = 0
    for rec in records("a=1 b=2"):
      check(rec == @[("a", "1"), ("b", "2")])
      inc n
    check(n == 1)

suite "recordsLenient":
  test "skips invalid lines but recovers pairs within them":
    let text = "level=info msg=ok\npanic: runtime error level=error\nlevel=warn msg=done"
    var levels: seq[string] = @[]
    for rec in recordsLenient(text):
      let lvl = rec.getOrDefault("level")
      if lvl != "":
        levels.add(lvl)
    check(levels == @["info", "error", "warn"])

  test "handles a realistic mixed log file":
    let text = """
2026-11-03 starting service v0.2.0
level=info msg="service started" port=8080
---- healthcheck ----
level=error msg="db unreachable" host=postgres-1 retry=3
level=info msg="shutting down"
"""
    var records: seq[seq[LogfmtPair]] = @[]
    for rec in recordsLenient(text):
      records.add(rec)
    check(records.len == 5)
    check(records[1].getOrDefault("msg") == "service started")
    check(records[3].getOrDefault("host") == "postgres-1")
    check(records[3].getOrDefault("retry") == "3")

suite "decodeLines":
  test "matches records output":
    let text = "a=1\nb=2\nc=3"
    let eager = decodeLines(text)
    var lazy: seq[seq[LogfmtPair]] = @[]
    for rec in records(text):
      lazy.add(rec)
    check(eager == lazy)
    check(eager.len == 3)

  test "raises on invalid input":
    expect LogfmtError:
      discard decodeLines("a=1\nbroken\n")
