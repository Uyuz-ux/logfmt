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
