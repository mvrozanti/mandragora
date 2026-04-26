---
type: package
tags: [package, ai, tooling]
path: pkgs/rtk/
---

# rtk

Token-reduction proxy for dev commands — strips banners, progress bars, ASCII tables. 60–90% fewer tokens on the same output.

Statically linked musl binary. Used as a thin wrapper around `git`, `grep`, `cargo`, `kubectl`, etc. when piping into AI agent context.

Consumed by: [[../modules/user/home]] (system path)
Touches: [[../concepts/ai-stack]]
