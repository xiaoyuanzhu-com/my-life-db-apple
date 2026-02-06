# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MyLifeDB Apple is a **native iOS/macOS client** for the MyLifeDB personal knowledge management system. It consumes the MyLifeDB backend API (Go server) and provides a native Apple experience.

**Key architecture documents:**
- See Apple Client section in `../my-life-db-docs/` — High-level architecture, API mapping, data flow

## Design Principles

### 1. One Codebase, Multiple Platforms
- Single Xcode target builds for iPhone, iPad, Mac, and Vision Pro
- SwiftUI with `#if os()` for platform-specific code
- Goal: 80-95% shared code

### 2. Client-Server Architecture
- Backend (Go) is the source of truth
- App fetches data directly via REST API
- No local database or sync — simple API client

### 3. Native Experience
- SwiftUI for all UI
- SwiftData for persistence
- Platform-appropriate navigation and controls

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

See Apple Client section in `../my-life-db-docs/` for full API reference.

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

## Naming Conventions

| Category | Convention | Example |
|----------|-----------|---------|
| Swift files | PascalCase | `InboxView.swift` |
| API models | PascalCase | `InboxItem`, `FileRecord` |
| API endpoints | camelCase methods | `inbox.list()` |
| Views | PascalCase + View suffix | `InboxListView` |
