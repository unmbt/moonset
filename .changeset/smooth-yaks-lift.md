---
"moonbit:unmbt/moonset": patch
---

Fix Cargo registry lookup matching local workspace crates by always passing --registry crates-io, and batch multi-tag git push with a transient retry.
