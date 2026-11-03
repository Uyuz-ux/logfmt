# Parse a whole log file (or stdin) record by record.
#
#   echo 'level=info msg=started port=8080
#   not a logfmt line
#   level=error msg=failed' | nim r examples/parse_log_file.nim

import logfmt, std/os

let text =
  if paramCount() >= 1:
    readFile(paramStr(1))
  else:
    readAll(stdin)

# recordsLenient skips lines that are not valid logfmt (banners, stack
# traces, free-form text) and keeps decoding the rest.
var
  total = 0
  errors = 0
for rec in recordsLenient(text):
  inc total
  if rec.getOrDefault("level") == "error":
    inc errors
    echo rec

echo "total records: ", total, ", errors: ", errors
