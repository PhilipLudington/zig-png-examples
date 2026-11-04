# Project Instructions

CarbideZig is used in this project for Zig development standards. See `carbide/CARBIDE.md` and `carbide/STANDARDS.md`.

## Building and testing

This project needs **Zig 0.15**; the machine's default `zig` is 0.16, which cannot build it
(`DEBT.md` Debt 1). Always build and test through the AirTower wrappers, which pick Zig 0.15
(`scripts/zig-path.sh`: Homebrew's `zig@0.15`, or `$ZIG` when set) and refuse any other version:

```bash
./run-build.sh   # zig build       → .build-results.json
./run-tests.sh   # zig build test  → .test-results.json
```

Do not run `zig build` directly. To run the viewer by hand, use
`/opt/homebrew/opt/zig@0.15/bin/zig build run -- <file.png>`.
