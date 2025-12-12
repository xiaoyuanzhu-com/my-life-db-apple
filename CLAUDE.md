# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MyLifeDB is an iOS/macOS SwiftUI application using SwiftData for persistence. This is a standard Xcode project with a master-detail interface for managing timestamped items.

## Build & Test Commands

### Building
```bash
# Build the app
xcodebuild -scheme MyLifeDB -configuration Debug build

# Build for specific destination
xcodebuild -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### Running Tests
```bash
# Run all tests
xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 15'

# Run only unit tests
xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyLifeDBTests

# Run only UI tests
xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyLifeDBUITests

# Run a specific test
xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyLifeDBTests/MyLifeDBTests/example
```

## Architecture

### Data Layer
- **SwiftData**: The app uses SwiftData (not Core Data) as the persistence framework
- **ModelContainer**: Created in `MyLifeDBApp.swift:13-24` with a schema containing all `@Model` classes
- **ModelContext**: Injected into the SwiftUI environment and accessed via `@Environment(\.modelContext)`
- **Models**: Located in the root `MyLifeDB/` directory (e.g., `Item.swift`)
  - Models must be decorated with `@Model` macro
  - Models must be registered in the Schema in `MyLifeDBApp.swift:14-16`

### View Layer
- **SwiftUI**: All UI is built with SwiftUI (no UIKit/AppKit)
- **@Query**: Used to fetch SwiftData models reactively (see `ContentView.swift:13`)
- **Platform Conditionals**: The app supports both iOS and macOS with `#if os()` directives for platform-specific UI

### Project Structure
```
MyLifeDB/                    # Main app target source files
  ├── MyLifeDBApp.swift     # App entry point & ModelContainer setup
  ├── ContentView.swift     # Main UI
  ├── Item.swift            # SwiftData model
  └── Assets.xcassets/      # Asset catalog
MyLifeDBTests/              # Unit tests (using Swift Testing framework)
MyLifeDBUITests/            # UI tests (using XCTest)
```

## Key Patterns

### Adding New SwiftData Models
1. Create model class with `@Model` macro
2. Register in Schema at `MyLifeDBApp.swift:14-16`
3. Access via `@Query` in views or `modelContext` for CRUD operations

### SwiftUI Data Flow
- Use `@Environment(\.modelContext)` to access the model context for inserts/deletes
- Use `@Query` property wrapper to fetch and observe model changes
- Wrap model mutations in `withAnimation { }` for smooth UI updates
