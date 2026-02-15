# Native Inbox Page — Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the WebView-based Inbox tab with a native SwiftUI implementation matching the web UI layout, with iOS-idiomatic performance patterns.

**Architecture:** New native inbox views under `Views/Inbox/`, replacing the WebView tab content in `MainTabView`. Reuse existing `InboxAPI`, `InboxItem` models, `FileViewerView`, and `Color+Platform` helpers. Remove `#if LEGACY_NATIVE_VIEWS` guards from reusable components (cards, input bar, pinned bar, feed) and update them. Legacy views that are fully replaced get deleted.

**Tech Stack:** SwiftUI, async/await, existing `APIClient` + `InboxAPI` + `SearchAPI`

---

## Phase 1 Scope

**In scope:**
- A: Item display & feed (all)
- B: Pagination & scroll (all — cursor-based, infinite scroll, stick-to-bottom, pin navigation)
- C: Item actions (delete with optimistic UI + animation, pin/unpin, selection mode) — NO "open in library" or "copy text"
- D: File upload/creation (text + files + multi-file + pending queue)
- E: Item detail — use existing `FileViewerView` (native file preview, same as library tab)
- G: Real-time updates (SSE notifications, auto-refresh, new item animation)
- H: Pinned items (list + navigate to pinned)
- I: Search (full-text keyword search, NO semantic search)
- J: Performance (lazy images, idiomatic iOS patterns)

**Out of scope:** Digest/AI processing, semantic search, "open in library", "copy text" context menu actions.

---

## Doubts Log

> Implementor: record any doubts/questions here during implementation. The user will review at the end.

- [ ] _Empty — add doubts as they arise_

---

## Task 1: Scaffold native inbox root + wire into MainTabView

**Files:**
- Create: `MyLifeDB/Views/Inbox/NativeInboxView.swift`
- Modify: `MyLifeDB/Views/MainTabView.swift`

**What to do:**

1. Create `NativeInboxView.swift` — the root view for the Inbox tab. Structure:
   - `NavigationStack` with `@State private var navigationPath = NavigationPath()`
   - Contains the `InboxFeedContainerView` (created in Task 2) as root content
   - Navigation destination for file detail: `.file(path:, name:)` → `FileViewerView(filePath:, fileName:)`
   - `.navigationTitle("Inbox")` with `.navigationBarTitleDisplayMode(.large)` on iOS
   - Toolbar: refresh button (calls reload on feed)

2. In `MainTabView.swift`:
   - Replace the Inbox tab's `tabContent(viewModel: inboxVM)` (WebView) with `NativeInboxView()`
   - Remove `inboxVM` (the `TabWebViewModel` for inbox) since it's no longer needed
   - Update `allViewModels` to only contain `claudeVM`
   - Update deep link handling: inbox deep links now just switch to the inbox tab (native handles its own state)

**Commit:** `feat(inbox): scaffold native inbox root and wire into tab bar`

---

## Task 2: Inbox feed container with data loading + pagination

**Files:**
- Create: `MyLifeDB/Views/Inbox/InboxFeedContainerView.swift`

**What to do:**

Build the main data-owning container that manages:

**State:**
```swift
@State private var items: [InboxItem] = []
@State private var pinnedItems: [PinnedItem] = []
@State private var isLoading = false
@State private var isLoadingMore = false
@State private var error: APIError?
@State private var cursors: InboxCursors?
@State private var hasMore = InboxHasMore(older: false, newer: false)
```

**Data loading functions:**
- `loadInitialData()` — parallel fetch of items + pinned items
- `loadItems()` — `APIClient.shared.inbox.list()`, store items/cursors/hasMore
- `loadPinnedItems()` — `APIClient.shared.inbox.listPinned()`
- `refresh()` — reload both in parallel
- `loadOlderItems()` — `APIClient.shared.inbox.fetchOlder(cursor:)`, append to items
- `loadNewerItems()` — `APIClient.shared.inbox.fetchNewer(cursor:)`, prepend to items

**State dispatch (same pattern as LibraryFolderView):**
- Loading + empty → `ProgressView("Loading inbox...")`
- Error + empty → error view with Retry
- Empty → `ContentUnavailableView("No Items", systemImage: "tray")`
- Content → render the feed (Task 3)

**Lifecycle:**
- `.task { await loadInitialData() }`
- `.refreshable { await refresh() }`

**Commit:** `feat(inbox): add feed container with data loading and pagination`

---

## Task 3: Feed view — item list with cards

**Files:**
- Create: `MyLifeDB/Views/Inbox/InboxFeedView.swift`
- Create: `MyLifeDB/Views/Inbox/Cards/InboxItemCard.swift`
- Create: `MyLifeDB/Views/Inbox/Cards/InboxTextCard.swift`
- Create: `MyLifeDB/Views/Inbox/Cards/InboxImageCard.swift`
- Create: `MyLifeDB/Views/Inbox/Cards/InboxVideoCard.swift`
- Create: `MyLifeDB/Views/Inbox/Cards/InboxAudioCard.swift`
- Create: `MyLifeDB/Views/Inbox/Cards/InboxDocumentCard.swift`
- Create: `MyLifeDB/Views/Inbox/Cards/InboxFallbackCard.swift`

**What to do:**

Build the scrollable feed. Port the legacy cards out of `#if LEGACY_NATIVE_VIEWS`, placing them in the new `Views/Inbox/Cards/` directory.

**InboxFeedView layout** — aligned with web UI:
- `ScrollViewReader` wrapping `ScrollView`
- `LazyVStack(alignment: .trailing, spacing: 16)` — items right-aligned like chat bubbles
- Each item: timestamp above card, card below
- Items displayed oldest-first (reverse API order) so newest is at bottom
- "Load older" section at top when `hasMore.older`
- Auto-scroll to bottom on initial load + when new items arrive

**Card components** — port from legacy with these changes:
- Remove `#if LEGACY_NATIVE_VIEWS` guards
- `InboxItemCard` dispatches to type-specific card based on MIME type (same logic as legacy `InboxItemCard`)
- Card styling: `.background(Color.platformBackground)`, `.clipShape(RoundedRectangle(cornerRadius: 12))`, `.shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)`
- `InboxTextCard`: text preview (max 20 lines), file extension badge, size
- `InboxImageCard`: `AsyncImage` from `APIClient.shared.rawFileURL(path:)`, max 320pt, filename + size footer
- `InboxVideoCard`: play icon thumbnail + name + size
- `InboxAudioCard`: play icon + waveform placeholder + name + size
- `InboxDocumentCard`: screenshot thumbnail (if available via `screenshotSqlar`) or document icon, name + size
- `InboxFallbackCard`: icon + name + size

**Commit:** `feat(inbox): add feed view with type-specific item cards`

---

## Task 4: Item actions — delete (optimistic) + pin/unpin + context menu

**Files:**
- Modify: `MyLifeDB/Views/Inbox/InboxFeedContainerView.swift`
- Modify: `MyLifeDB/Views/Inbox/InboxFeedView.swift`

**What to do:**

Add item actions to the feed:

**Delete:**
- Context menu "Delete" button (role: .destructive)
- Swipe-to-delete on iOS
- Confirmation alert before deleting
- Optimistic removal with `withAnimation(.easeOut(duration: 0.3))`
- On failure: reload items to restore
- API: `APIClient.shared.inbox.delete(id: InboxAPI.idFromPath(item.path))`

**Pin/Unpin:**
- Context menu "Pin" / "Unpin" toggle
- Pin: `APIClient.shared.library.pin(path: item.path)` → refresh both lists
- Unpin: `APIClient.shared.library.unpin(path: item.path)` → optimistic remove from pinned + refresh

**Selection mode:**
- `@State private var selectionMode = false`
- `@State private var selectedItems: Set<String> = []` (set of item paths)
- Context menu "Select" action enters selection mode
- In selection mode: show circle checkboxes on left of each card
- Tapping card toggles selection
- Toolbar shows "Cancel" to exit selection mode + count of selected items
- (Batch actions like bulk delete can be added later — just wire up the selection UI for now)

**Context menu per item:**
- Pin / Unpin
- Select
- Divider
- Delete (destructive)

**Commit:** `feat(inbox): add delete, pin/unpin, selection mode, and context menus`

---

## Task 5: File upload and text creation — input bar

**Files:**
- Create: `MyLifeDB/Views/Inbox/InboxInputBar.swift`
- Modify: `MyLifeDB/Views/Inbox/InboxFeedContainerView.swift`
- Create: `MyLifeDB/Views/Inbox/PendingItemView.swift`

**What to do:**

Port the legacy `InboxInputBar` (remove `#if LEGACY_NATIVE_VIEWS` guard) into the new location. Wire it into `InboxFeedContainerView`.

**Input bar features:**
- Text field with "What's up?" placeholder, multi-line (1-6 lines)
- Attach button (Menu) → Photo Library picker or Files picker
- Send button (enabled when text or attachments present)
- Attachments preview strip (horizontal scroll of chips with remove button)

**Pending items queue:**
- `@State private var pendingItems: [PendingInboxItem] = []`
- Model: `PendingInboxItem` with id, text, files, status (uploading/failed/queued), error, retryAt
- Show pending items at bottom of feed (newest)
- Spinner after 3s of uploading
- Failed items show error + retry countdown
- On success: remove from pending, refresh feed
- On failure: mark as failed, schedule retry with exponential backoff (max 3 retries)

**Upload logic:**
- Text-only: `APIClient.shared.inbox.createText(text)`
- With files: `APIClient.shared.inbox.uploadFiles(files, text:)`
- On success: clear input, remove pending item, refresh feed

**Layout in container:**
```
VStack(spacing: 0) {
    mainContent  // feed or loading/error/empty
    Divider()
    pinnedItemsBar  // (Task 6)
    InboxInputBar(...)
}
```

**Commit:** `feat(inbox): add input bar with text creation and file upload`

---

## Task 6: Pinned items bar

**Files:**
- Create: `MyLifeDB/Views/Inbox/InboxPinnedBar.swift`
- Modify: `MyLifeDB/Views/Inbox/InboxFeedContainerView.swift`

**What to do:**

Port the legacy `PinnedItemsBar` + `PinnedTag` into `InboxPinnedBar.swift`.

**Features:**
- Horizontal scrolling bar of pinned item capsules
- Each capsule: pin icon (orange) + display text + optional X button on hover/tap
- Tap capsule → navigate to item in feed (scroll to it using `around` cursor)
- Context menu → Unpin
- Hidden when no pinned items

**Pin navigation flow:**
1. User taps pinned tag
2. Call `APIClient.shared.inbox.list(around: pinnedItem.cursor)`
3. Replace feed items with response
4. Scroll to the target item (use `response.targetIndex`)
5. Highlight the item briefly (e.g., flash background)

**Commit:** `feat(inbox): add pinned items bar with navigation`

---

## Task 7: Real-time updates via SSE

**Files:**
- Create: `MyLifeDB/Views/Inbox/InboxSSEManager.swift`
- Modify: `MyLifeDB/Views/Inbox/InboxFeedContainerView.swift`

**What to do:**

Implement Server-Sent Events listener for inbox real-time updates.

**InboxSSEManager:**
- Connects to `GET /api/notifications/stream` via `URLSession` with streaming
- Parses SSE format: `event: <name>\ndata: <json>\n\n`
- Listens for events:
  - `inbox-changed` → callback to refresh feed
  - `pin-changed` → callback to refresh pinned items
- Auto-reconnect on disconnect (with backoff)
- Auth header: same Bearer token as APIClient
- Lifecycle: start on appear, stop on disappear

**Integration in InboxFeedContainerView:**
- `.task { sseManager.start() }`
- `.onDisappear { sseManager.stop() }`
- On `inbox-changed`: call `loadNewerItems()` if stick-to-bottom, else show "new items" indicator
- On `pin-changed`: call `loadPinnedItems()`

**New item animation:**
- Items arriving via SSE get `.transition(.move(edge: .bottom).combined(with: .opacity))`
- Wrapped in `withAnimation(.easeOut(duration: 0.35))`

**Commit:** `feat(inbox): add SSE real-time updates with auto-refresh`

---

## Task 8: Search integration

**Files:**
- Create: `MyLifeDB/Views/Inbox/InboxSearchView.swift`
- Modify: `MyLifeDB/Views/Inbox/NativeInboxView.swift`

**What to do:**

Add searchable inbox with full-text keyword search.

**Search UI:**
- `.searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always))`
- Debounce input (300ms)
- Show `InboxSearchView` when search is active
- Search results rendered as same card style as feed
- Each result shows snippet/match context below the card
- Pagination: load more on scroll

**InboxSearchView:**
- `@State private var results: [SearchResultItem] = []`
- `@State private var isSearching = false`
- `@State private var pagination: SearchPagination?`
- Fetch: `APIClient.shared.search.search(query:, limit: 20, offset:)`
- Results displayed in `LazyVStack` similar to feed
- Each result card reuses `InboxItemCard` pattern but with search context

**Integration:**
- In `NativeInboxView`, add `.searchable` modifier
- When search query is non-empty, overlay search results on top of feed

**Commit:** `feat(inbox): add full-text search with results display`

---

## Task 9: Infinite scroll + stick-to-bottom + scroll performance

**Files:**
- Modify: `MyLifeDB/Views/Inbox/InboxFeedView.swift`
- Modify: `MyLifeDB/Views/Inbox/InboxFeedContainerView.swift`

**What to do:**

Polish the scroll behavior for production quality.

**Infinite scroll:**
- Use `.onAppear` on sentinel views (first and last items)
- When top sentinel appears → `loadOlderItems()` (if `hasMore.older`)
- When bottom sentinel appears → `loadNewerItems()` (if `hasMore.newer`)
- Show `ProgressView` at top/bottom while loading

**Stick-to-bottom:**
- Track if user is near bottom via `ScrollView` + `GeometryReader` or `ScrollPosition` (iOS 17+)
- When at bottom and new items arrive → auto-scroll to newest
- When user scrolls up → disable auto-scroll
- When user scrolls back to bottom → re-enable

**Performance:**
- `LazyVStack` already handles lazy rendering
- Images: `AsyncImage` with `.priority(.low)` for off-screen, `.priority(.high)` for newest
- Ensure item IDs are stable (path-based) for efficient diffing

**Commit:** `feat(inbox): polish infinite scroll and stick-to-bottom behavior`

---

## Task 10: Clean up legacy views + test build

**Files:**
- Delete or archive: `MyLifeDB/Views/Inbox/InboxView_Native.swift`
- Delete: `MyLifeDB/Views/Inbox/Legacy/` (entire directory)

**What to do:**

1. Delete `InboxView_Native.swift` (old legacy wrapper)
2. Delete `Views/Inbox/Legacy/` directory entirely — all functionality has been ported to new files
3. Run `xcodebuild -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' build` to verify clean build
4. Fix any compile errors
5. Review doubts log and document any remaining items

**Commit:** `chore(inbox): remove legacy inbox views and clean up`

---

## Summary

| Task | Description | Key Files |
|------|------------|-----------|
| 1 | Scaffold root + wire tab | `NativeInboxView.swift`, `MainTabView.swift` |
| 2 | Data loading + pagination | `InboxFeedContainerView.swift` |
| 3 | Feed + cards | `InboxFeedView.swift`, `Cards/*.swift` |
| 4 | Delete, pin, selection | Container + Feed modifications |
| 5 | Input bar + upload | `InboxInputBar.swift`, `PendingItemView.swift` |
| 6 | Pinned items bar | `InboxPinnedBar.swift` |
| 7 | SSE real-time | `InboxSSEManager.swift` |
| 8 | Search | `InboxSearchView.swift` |
| 9 | Scroll polish | Feed modifications |
| 10 | Cleanup + build test | Delete legacy files |
