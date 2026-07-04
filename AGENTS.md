# AGENTS.md

This file provides guidance to coding agents (Claude Code, Cursor, Codex) when working in this repository.

## Repository layout

This is a monorepo with one native app and three web deliverables that are otherwise independent:

- **Root (Swift)** — `Sources/`, `Tests/`, `Package.swift`: the AgentPet macOS menu-bar app + CLI. This is the primary product.
- **`web/`** — Astro site on Cloudflare (the pet library / gallery / submissions). Has its own `package.json`, build, and deploy.
- **`cdn-proxy/`** — a standalone Cloudflare Worker that mirrors upstream pet libraries (OpenPets, Petdex) into R2 and serves a unified manifest.
- **`landing/`** — a static one-page landing site (plain `index.html`).
- **`data/`** — checked-in manifest snapshots (`merged-manifest.json`, etc.).
- **`docs/specs/`** — the design spec (written in Vietnamese; the author's primary language).

When asked to work on "the app" assume the Swift target; "the site"/"gallery"/"pets" means `web/`.

## Swift app (root)

### Commands
```bash
swift build                         # debug build (what CI runs)
swift test                          # full test suite (what CI runs)
swift test --filter QuestionDetectorTests          # one test class
swift test --filter QuestionDetectorTests/testFoo  # one test method
./scripts/build-app.sh release      # assemble a runnable AgentPet.app into build/ (universal, ad-hoc signed)
./scripts/release.sh                # Developer ID sign + notarize + staple a distributable DMG (needs Apple creds)
```
CI (`.github/workflows/ci.yml`) runs `swift build` + `swift test` on macOS 15 / Xcode 16 (Swift 6). Tagging `v*` triggers `release.yml`.

`swift build` produces a bare binary that is **not** a proper menu-bar app (no bundle id / `LSUIElement` / notifications). To actually run the UI you must assemble the `.app` via `build-app.sh`, which also copies `Localizations/*.lproj` and bundles `Sparkle.framework`.

### Architecture

**One binary, three roles**, dispatched by the first argument in `Sources/App/AppEntry.swift`:
- `agentpet hook ...` → `HookCLI` (lightweight event sender called from agent hooks)
- `agentpet run -- <cmd>` → `RunCLI` (universal wrapper that reports working/done around any command)
- no arguments → `AgentPetApp` (the SwiftUI menu-bar app)

**Two SwiftPM targets** (keep the split intentional):
- `AgentPetCore` (`Sources/AgentPetCore`) — pure, testable domain logic: event model, state machine, hook payload decoding, hook install/uninstall transforms, transcript reading. No AppKit/SwiftUI. Most tests live here.
- `agentpet` / `App` (`Sources/App`) — the SwiftUI/AppKit shell: menu bar, floating pet `NSPanel`, settings, notifications, Sparkle updater.

**Event flow** (the core mental model):
```
agent → its hook → `agentpet hook` (HookCLI) → EventSender
      → Unix socket (~/.agentpet/agentpet.sock)  [if app running]
      → file queue (~/.agentpet/queue/)           [fallback if not]
      → EventSocketServer / queue drain → SessionStore → AppDaemon (@MainActor) → SwiftUI
```
Paths live in `EventCoding.swift` (`AgentPetPaths`). `AppDaemon` (`Sources/App/AppDaemon.swift`) owns live state on the main actor, drains the queue on launch *using each event's original timestamp* (so dead sessions prune instead of resurrecting), and prunes stale sessions on a timer.

**Normalised state model** (`AgentState.swift`): every agent maps to `registered / working / waiting / done / idle`, regardless of `AgentKind` (claude, codex, gemini, cursor, opencode, windsurf, antigravity, cli, unknown) and `AgentSource` (`hook` = precise, `passive` = process-scan, on/off only). `StateMapper` does the per-agent mapping; `PetMood` derives the aggregate pet mood (waiting > celebrate/done > working > idle).

**Per-agent integration** is data-driven via `AgentCatalog.all` (drives the Settings list). Each agent's hook payload has its own decoder (`ClaudeHookPayload`, `AntigravityHookPayload`, `CodexHookConfig`, …); `HookPayload.event(forAgent:stdin:now:)` picks the right one. Explicit CLI flags (`--event/--session/...`) win over stdin payloads.

**HookInstaller** (`HookInstaller.swift`) installs/removes AgentPet's hook entries in each agent's own config file. Transforms are **pure and idempotent** — AgentPet's entries are identified by the command string containing `agentpet` + `hook`, so foreign hooks are never touched and re-install is safe. Claude/Codex/Gemini share the nested `{"hooks": {...}}` shape; Cursor/Windsurf use flatter shapes; opencode uses a JS plugin file.

## Web site (`web/`)

Astro 6 + Tailwind 4 on the Cloudflare adapter. Run all commands from `web/` (Node ≥ 22.12).
```bash
npm install
npm run dev          # astro dev (localhost:4321) — D1/R2 work via wrangler platformProxy
npm run build        # build to ./dist
npm run preview
npm run generate-types   # wrangler types (regen after editing wrangler.jsonc bindings)
```

Cloudflare bindings (`web/wrangler.jsonc`): `DB` (D1 — schema is bootstrapped idempotently in `src/lib/db.ts:ensureSchema`, no migration step), `PETS` (R2), `ASSETS`. Pet data is **not** read from `/data/`; the gallery fetches the live manifest from the mirror origin (`PETS_ORIGIN`, served by `cdn-proxy`) — see `src/lib/pets.ts`. `data/` snapshots are for tooling/reference only.

**Pages**: `src/pages/*.astro` are routes; `src/pages/api/**` are JSON/action endpoints (auth via GitHub OAuth in `lib/auth.ts`, admin gating in `lib/admin.ts`). GitHub-login + likes/submissions/collections/requests are stored in D1.

> ⚠️ **Maintenance mode is currently ON.** `src/middleware.ts` (`MAINTENANCE = true`) serves a self-contained "coming soon" page for *every* route, and `astro.config.mjs` was switched to `output: 'server'` so the middleware can intercept static routes. To restore the real site: set `MAINTENANCE = false` and remove the `output: 'server'` line, then redeploy. `/api/*` is intentionally kept alive so the running app keeps working.

## Other web pieces

- **`cdn-proxy/`** — Cloudflare Worker (`worker.js`, deploy with `wrangler` using `wrangler.toml`). Mirrors OpenPets + Petdex pets into R2 and exposes `/manifest`, `/a/<key>`, and admin `/mirror/run`/`/mirror/status`. Assets are served from the R2 public domain, not through the Worker.
- **`landing/`** — static HTML, no build step.

## Conventions

- Pets use the open **Codex pet-pack format** (`pet.json` + an 8×9 spritesheet). The repo bundles no pet art; packs are downloaded at runtime. Be careful not to commit third-party pet assets (IP concerns — the maintenance page exists partly for this reason).
- Comments in this codebase explain *why*, often with the original reasoning and issue numbers — match that density and keep the rationale when editing.
- The design spec (`docs/specs/2026-05-29-agentpet-design.md`) is in Vietnamese.
