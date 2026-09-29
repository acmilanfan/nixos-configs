"""firefox: fix the History command's date range.

The extension only queries visits from the *previous calendar month*
(`start of month, -1 month` .. `start of month`), so on e.g. 2026-09-29 no
history after 2026-08-31 is ever shown. Widen it to the last 30 days.
"""

import sys

PATH = "src/history.tsx"

old = (
    "AND moz_historyvisits.visit_date >= ((julianday('now', 'start of month', '-1 month') - 2440587.5) * 86400000000) "
    "AND moz_historyvisits.visit_date < ((julianday('now', 'start of month') - 2440587.5) * 86400000000)"
)
new = "AND moz_historyvisits.visit_date >= ((julianday('now', '-30 days') - 2440587.5) * 86400000000)"

src = open(PATH).read()

if old not in src:
    sys.exit("history date range not found in " + PATH)

open(PATH, "w").write(src.replace(old, new, 1))
print("patched history date range to last 30 days")
