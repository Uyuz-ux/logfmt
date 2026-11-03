# logfmt.nim

Encode and decode the [logfmt](https://brandur.org/logfmt) structured logging format in Nim — the compact `key=value` format popularized by Heroku and the Go ecosystem.

```nim
import logfmt

# Encode
echo encode([("level", "info"), ("msg", "user 42 logged in"), ("count", "42")])
## level=info msg="user 42 logged in" count=42

# Typed fields
echo encode([field("level", "warn"), field("disk_free", 2.5), field("critical", true)])
## level=warn disk_free=2.5 critical=true

# Decode
let fields = decode("level=info msg=\"user 42 logged in\" count=42")
echo fields.getOrDefault("msg")   # user 42 logged in
echo decodeTable("a=1 a=2")["a"]  # 2 (last wins)

# Multi-record: process a whole log file, line by line
for rec in recordsLenient(messyLogText):
  if rec.getOrDefault("level") == "error":
    echo rec
```

## Why logfmt?

Structured logs that stay readable by humans: `grep`-able, one event per line, no JSON noise. If you log `level=info msg=...` you get 90% of the benefit of structured logging with none of the ceremony.

## Features

- **Zero dependencies** — pure Nim standard library.
- **Spec-compliant quoting** — values containing whitespace, `=` or `"` are quoted; embedded quotes, backslashes and control characters are escaped, matching the behavior of Go's `go-logfmt`.
- **Strict and lenient decoding** — `decode` raises `LogfmtError` on malformed input; `decodeLenient` salvages valid pairs from mixed content such as stack traces interleaved with structured lines.
- **Multi-record processing** — iterate over a whole log file with `records` / `recordsLenient`, or collect everything eagerly with `decodeLines`. Whitespace-only lines (banners, separators, blank lines) are skipped.
- **Ordered results** — `decode` preserves key order and duplicates; `decodeTable` collapses duplicates with last-value-wins.
- **Typed fields** — the `field` helper converts ints, floats, bools and anything with a sensible `$`.

## Installation

```
nimble install logfmt
```

Or add to your `.nimble` file:

```
requires "logfmt >= 0.1.0"
```

## API

| Proc | Description |
|---|---|
| `encode(pairs: openArray[LogfmtPair]): string` | Encode pairs into one logfmt line |
| `field(key: string, value: auto): LogfmtPair` | Build a pair from any value via `$` |
| `decode(line: string): seq[LogfmtPair]` | Strict decode; raises `LogfmtError` |
| `decodeLenient(line: string): seq[LogfmtPair]` | Best-effort decode; skips malformed fragments |
| `decodeTable(line: string): OrderedTable[string, string]` | Decode with last-value-wins semantics |
| `records(text: string): iterator` | Iterate over a multi-line text, one record per line; raises on invalid lines |
| `recordsLenient(text: string): iterator` | Iterate over a multi-line text; skips invalid lines |
| `decodeLines(text: string): seq[seq[LogfmtPair]]` | Eager variant of `records` |
| `fields.getOrDefault(key, default = "")` | First value for `key`, or the default |

## Example

See [examples/server_log.nim](examples/server_log.nim):

```nim
import logfmt, std/times

proc log(level, msg: string, extra: seq[LogfmtPair] = @[]) =
  var pairs = @[
    field("time", now().format("yyyy-MM-dd'T'HH:mm:ss")),
    field("level", level),
    field("msg", msg),
  ]
  pairs.add(extra)
  echo encode(pairs)

log("info", "server started", @[field("port", 8080)])
log("error", "request failed", @[field("path", "/api/users"), field("status", 500)])
```

## Running tests

```
nimble test
```

## License

MIT
