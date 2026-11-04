# Project Debt

## [ ] Debt 1: Build does not work on Zig 0.16, the machine's default zig

**Status:** Open
**Kind:** tooling
**Where:** `build.zig:33`, `build.zig.zon`
**Due when:** touching `build.zig` · when Zig 0.15 is removed from Homebrew on this machine

**Description:** The project builds only with `/opt/homebrew/opt/zig@0.15/bin/zig`. Plain `zig` is
0.16.0 and fails two ways: `exe.linkLibrary` no longer exists on `Build.Step.Compile`
(`build.zig:33`, `:58`), and the pinned SDL dependency (castholm/SDL `887fa80`) calls
`ArrayHashMap.put` without the allocator argument 0.16 requires. Zig 0.16 also writes fetched
packages into a `zig-pkg/` folder at the repo root, which `.gitignore` does not list. Found while
applying zig-png's getSample mail on `mail/2026-11-03-getsample-subbyte`; not paid there because
porting the build and moving SDL to a 0.16-ready release is larger than that change. The repo also
declares no AirTower gates (`.airtower.json` is absent), so `verify` cannot check either toolchain.

**Payment:** Move SDL to a castholm/SDL release that builds on 0.16, replace `linkLibrary` with the
0.16 module API (`root_module.linkLibrary`), add `zig-pkg/` to `.gitignore`, raise
`minimum_zig_version`, and add `.airtower.json` with build and test wrappers.

**Verified by:** `zig build` and `zig build test` with Zig 0.16.0 exit 0 — answer key: the Zig
0.16.0 release notes' build-system changes.

**Found by:** /mail on `mail/2026-11-03-getsample-subbyte`, 2026-11-03 — Claude.
