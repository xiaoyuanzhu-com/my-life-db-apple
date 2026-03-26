# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MyLifeDB Apple is a **native iOS/macOS client** for the MyLifeDB personal knowledge management system. It consumes the MyLifeDB backend API (Go server) and provides a native Apple experience.

**Documentation:** All project docs live in [`../my-life-db-docs/`](../my-life-db-docs/) (Astro Starlight site). See the **Apple Client** section for architecture, hybrid UI approach, data collection, and inbox PRD.

## Design Principles

### 1. One Codebase, Multiple Platforms
- Single Xcode target builds for iPhone, iPad, Mac, and Vision Pro
- SwiftUI with `#if os()` for platform-specific code
- Goal: 80-95% shared code

### 2. Hybrid Native + WebView Architecture
- Native SwiftUI shell with WKWebView-rendered content
- Reuses 80%+ of existing web frontend code
- Web excels at rich content (Markdown, code, Mermaid)
- Backend (Go) is the source of truth

### 3. Simple API Client
- App fetches data directly via REST API
- No local database or sync

## Build & Test Commands

### Building
```bash
# Build for iOS Simulator
xcodebuild -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for macOS
xcodebuild -scheme MyLifeDB -destination 'platform=macOS' build

# Build for visionOS Simulator
xcodebuild -scheme MyLifeDB -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build
```

### Running Tests
```bash
# Run all tests
xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 15'

# Run only unit tests
xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyLifeDBTests

# Run only UI tests
xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyLifeDBUITests
```

## Project Structure

```
MyLifeDB/
├── App/
│   └── MyLifeDBApp.swift       # Entry point
├── API/                         # Backend API client
│   ├── APIClient.swift          # HTTP client with auth
│   ├── Endpoints/               # Per-resource API calls
│   └── Models/                  # Codable structs for API responses
├── Views/                       # SwiftUI views
│   ├── Inbox/
│   ├── Library/
│   ├── Search/
│   └── Shared/
└── Platform/                    # Platform-specific code
    ├── iOS/
    └── macOS/
```

## Backend API

The app consumes the MyLifeDB backend API (default: `http://localhost:12345`).

Key endpoints:
- `GET /api/inbox` — List inbox items
- `GET /api/library/tree` — Folder structure
- `GET /api/search?q=...` — Full-text search
- `GET /api/people` — People list
- `GET /raw/*path` — Serve file content
- `GET /api/notifications/stream` — SSE real-time updates

See the Apple Client section in [`../my-life-db-docs/`](../my-life-db-docs/) for full API reference.

## Data Layer

### API Models
- Simple Codable structs matching backend JSON
- No local database — fetch directly from API
- Views hold data in @State or @Observable

## Key Patterns

### Platform Conditionals
```swift
#if os(iOS)
    // iOS-specific code
#elseif os(macOS)
    // macOS-specific code
#endif
```

### API Client Usage
```swift
// Fetch inbox items
let response = try await APIClient.shared.inbox.list()
self.items = response.items
```

### SwiftUI Data Flow
- `@State` or `@Observable` for view data
- `Task { }` for async API calls
- Show loading/error states appropriately

## Git Workflow

**Local vs. remote environments (detect by platform: `darwin` = local, `linux` = remote):**
- **Local (`darwin`/macOS):** Work directly in the main repo directory. Do NOT use worktrees — the user needs to test and review changes in-place before committing.
- **Remote (`linux`/server):** Use git worktrees for isolation. Follow the worktree workflow below.

**Common rules (both environments):**

- **`git fetch origin` first — every time, no exceptions.** Branch from `origin/main`, not HEAD.
- **Never auto-commit or auto-push** — when changes are ready (tests pass, work complete), prompt: *"Ready to commit, push, and clean up?"* so the user can reply **"go"** to confirm. Consent applies to the current batch only; after each push + clean up cycle, wait for the user's next instruction.
- **Always rebase, never merge** — push `<branch>:main` directly; no PRs, no merge commits.

### Local workflow (direct changes in main repo)

    # Work directly in the repo
    cd <repo-root>
    # ... edit, build, test ...

    # When user approves commit:
    git checkout -b <branch>
    git add <files> && git commit

    # Push + clean up
    git fetch origin && git rebase origin/main
    git push origin <branch>:main
    git checkout main && git pull --rebase origin main
    git branch -d <branch>

### Remote workflow (worktrees)

Use the `using-git-worktrees` skill to set up. Create the worktree FIRST — before reading, editing, building, or running any code.

- **Main directory is off-limits** — only `git worktree add/remove` there; everything else happens inside the worktree.
- **Sub-agents get the worktree path** — never pass the main repo path.

**Each worktree has one lifecycle: create → work → push → clean up.**
A worktree may accumulate multiple commits before pushing. After every push, clean up immediately.

    # --- start of work ---
    cd <repo-root>
    git fetch origin
    git worktree add -b <branch> .worktrees/<name> origin/main

    # --- commit (repeat as needed before pushing) ---
    cd .worktrees/<name>
    # ... git add, git commit ...

    # --- push + sync + clean up (after every push) ---
    git fetch origin && git rebase origin/main
    git push origin <branch>:main
    # Sync main working directory
    cd <repo-root>
    git pull --rebase origin main
    # If dirty main dir: git checkout -- . && git pull --rebase origin main
    # Clean up
    git worktree remove .worktrees/<name>
    git branch -d <branch>

## Development Principles

### Evidence-Based Debugging (CRITICAL)

**Never treat a hypothesis as a conclusion.** The correct flow is: **observe → hypothesize → verify → fix**. Skipping verification leads to wrong fixes that waste time and erode trust.

**Rules:**
1. **Hypotheses are not assertions** — When you don't know the root cause, say "I think X might be happening" not "X is the problem". Never state a guess as fact.
2. **Verify before fixing** — If you can't prove the root cause, add instrumentation (logging, counters, traces) to gather evidence first. A 5-line log statement that confirms the theory is worth more than a 50-line fix based on a guess.
3. **Check your own pipeline before blaming externals** — Before claiming "library X has a bug" or "the SDK does Y wrong", verify that your own code isn't the cause. Trace the data flow through YOUR code first.
4. **After 2-3 failed guesses, stop guessing harder** — Step back, add observability, and let the data tell you. More guessing compounds the problem; more visibility solves it.
5. **Prove it, then fix it** — The debugging session should produce evidence (logs, repro steps, seq numbers) that clearly point to the root cause. Only then write the fix.

## Naming Conventions

| Category | Convention | Example |
|----------|-----------|---------|
| Swift files | PascalCase | `InboxView.swift` |
| API models | PascalCase | `InboxItem`, `FileRecord` |
| API endpoints | camelCase methods | `inbox.list()` |
| Views | PascalCase + View suffix | `InboxListView` |
