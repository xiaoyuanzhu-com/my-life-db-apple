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

**Always use worktrees for ANY task involving code.** Create the worktree FIRST — before reading, editing, building, or running any code. The main directory's files may be stale; never read or act on them. Use the `using-git-worktrees` skill to set one up — it handles directory selection, `.gitignore` verification, project setup, and baseline tests.

**Project-specific rules that extend the skill:**

- **`git fetch origin` first — every time, no exceptions.** Branch from `origin/main`, not HEAD:
  `git worktree add -b <branch> .worktrees/<name> origin/main`
- **Main directory is off-limits** — only `git worktree add/remove` there; everything else (reads, edits, builds) happens inside the worktree.
- **Sub-agents get the worktree path** — never pass the main repo path.
- **Never auto-commit or auto-push** — wait for explicit user instruction.
- **Always rebase, never merge** — push `<branch>:main` directly; no PRs, no merge commits.

**Each worktree has one lifecycle: create → work → push → clean up.**
A worktree may accumulate multiple commits before pushing. After every push, clean up immediately.
If continuing work in the same session, create a new worktree and repeat.

**Workflow (commit only when user asks; push + sync + clean up after every push):**

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

## Naming Conventions

| Category | Convention | Example |
|----------|-----------|---------|
| Swift files | PascalCase | `InboxView.swift` |
| API models | PascalCase | `InboxItem`, `FileRecord` |
| API endpoints | camelCase methods | `inbox.list()` |
| Views | PascalCase + View suffix | `InboxListView` |
