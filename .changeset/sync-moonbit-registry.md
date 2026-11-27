---
"moonbit:unmbt/moonset": patch
---

Refresh the MoonBit registry index (`moon update` after polling `moon view`) and retry registry propagation misses between same-batch MoonBit workspace publishes, and print failed/blocked publish target summaries in `action.yml` on non-zero exit.
