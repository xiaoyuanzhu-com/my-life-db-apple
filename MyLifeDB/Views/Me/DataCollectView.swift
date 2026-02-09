//
//  DataCollectView.swift
//  MyLifeDB
//
//  Data collection settings. Each category can be toggled on/off.
//  Toggles are stored in UserDefaults via @AppStorage.
//

import SwiftUI

// MARK: - Data Source Model

struct DataSource: Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let platform: Platform
    let status: SourceStatus

    enum Platform: String {
        case iOS = "iPhone"
        case mac = "Mac"
        case watch = "Watch"
        case iOSWatch = "iPhone, Watch"
        case iOSMac = "iPhone, Mac"
        case all = "All"
    }

    enum SourceStatus: String {
        case available = "Available"
        case limited = "Limited"
        case manual = "Manual"
        case future = "Future"
    }
}

// MARK: - Categories

struct DataCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let sources: [DataSource]
}

private let dataCategories: [DataCategory] = [
    DataCategory(
        id: "health",
        name: "Health & Body",
        icon: "heart.fill",
        sources: [
            DataSource(id: "steps", name: "Steps", icon: "figure.walk", description: "Daily step count", platform: .iOSWatch, status: .available),
            DataSource(id: "distance", name: "Distance", icon: "point.topleft.down.to.point.bottomright.curvepath", description: "Walking + running distance", platform: .iOSWatch, status: .available),
            DataSource(id: "flights", name: "Flights Climbed", icon: "figure.stairs", description: "Floors ascended", platform: .iOSWatch, status: .available),
            DataSource(id: "active_energy", name: "Active Energy", icon: "flame.fill", description: "Calories burned through activity", platform: .iOSWatch, status: .available),
            DataSource(id: "exercise_min", name: "Exercise Minutes", icon: "figure.run", description: "Time spent exercising", platform: .iOSWatch, status: .available),
            DataSource(id: "stand_hours", name: "Stand Hours", icon: "figure.stand", description: "Hours with standing activity", platform: .watch, status: .available),
            DataSource(id: "heart_rate", name: "Heart Rate", icon: "heart.fill", description: "Resting, walking, and workout HR", platform: .iOSWatch, status: .available),
            DataSource(id: "hrv", name: "Heart Rate Variability", icon: "waveform.path.ecg", description: "HRV — stress and recovery indicator", platform: .watch, status: .available),
            DataSource(id: "blood_oxygen", name: "Blood Oxygen", icon: "lungs.fill", description: "SpO2 saturation level", platform: .watch, status: .available),
            DataSource(id: "respiratory_rate", name: "Respiratory Rate", icon: "wind", description: "Breaths per minute during sleep", platform: .watch, status: .available),
            DataSource(id: "vo2max", name: "VO2 Max", icon: "bolt.heart.fill", description: "Cardio fitness level", platform: .watch, status: .available),
            DataSource(id: "body_weight", name: "Body Weight", icon: "scalemass.fill", description: "Weight measurements", platform: .iOS, status: .available),
            DataSource(id: "walking_steadiness", name: "Walking Steadiness", icon: "figure.walk.motion", description: "Fall risk assessment", platform: .iOS, status: .available),
        ]
    ),
    DataCategory(
        id: "sleep",
        name: "Sleep",
        icon: "bed.double.fill",
        sources: [
            DataSource(id: "sleep_duration", name: "Sleep Duration", icon: "moon.fill", description: "Total time asleep", platform: .iOSWatch, status: .available),
            DataSource(id: "sleep_stages", name: "Sleep Stages", icon: "chart.bar.fill", description: "REM, deep, core, awake breakdown", platform: .watch, status: .available),
            DataSource(id: "bedtime", name: "Bedtime & Wake Time", icon: "alarm.fill", description: "Sleep schedule tracking", platform: .iOSWatch, status: .available),
            DataSource(id: "sleep_consistency", name: "Sleep Consistency", icon: "calendar.badge.clock", description: "Schedule regularity score", platform: .iOS, status: .available),
        ]
    ),
    DataCategory(
        id: "fitness",
        name: "Fitness & Sports",
        icon: "figure.run",
        sources: [
            DataSource(id: "workouts", name: "Workouts", icon: "figure.mixed.cardio", description: "All workout types with duration and calories", platform: .iOSWatch, status: .available),
            DataSource(id: "workout_routes", name: "Workout Routes", icon: "map.fill", description: "GPS tracks for outdoor workouts", platform: .iOSWatch, status: .available),
            DataSource(id: "running", name: "Running Metrics", icon: "figure.run", description: "Pace, cadence, stride length, power", platform: .watch, status: .available),
            DataSource(id: "swimming", name: "Swimming", icon: "figure.pool.swim", description: "Laps, strokes, distance, SWOLF", platform: .watch, status: .available),
            DataSource(id: "cycling", name: "Cycling", icon: "figure.outdoor.cycle", description: "Distance, speed, power", platform: .iOSWatch, status: .available),
        ]
    ),
    DataCategory(
        id: "nutrition",
        name: "Nutrition & Intake",
        icon: "fork.knife",
        sources: [
            DataSource(id: "water", name: "Water Intake", icon: "drop.fill", description: "Daily water consumption", platform: .iOS, status: .available),
            DataSource(id: "caffeine", name: "Caffeine", icon: "cup.and.saucer.fill", description: "Coffee and tea consumption", platform: .iOS, status: .available),
            DataSource(id: "meals", name: "Meals", icon: "fork.knife", description: "What you ate, when, photos", platform: .all, status: .manual),
            DataSource(id: "calories_in", name: "Calories Consumed", icon: "flame", description: "Dietary energy intake", platform: .iOS, status: .available),
            DataSource(id: "alcohol", name: "Alcohol", icon: "wineglass.fill", description: "Drinks consumed", platform: .all, status: .manual),
            DataSource(id: "supplements", name: "Supplements", icon: "pills.fill", description: "Vitamins and medications", platform: .all, status: .manual),
        ]
    ),
    DataCategory(
        id: "mindfulness",
        name: "Mindfulness & Mental Health",
        icon: "brain.head.profile.fill",
        sources: [
            DataSource(id: "mindful_min", name: "Mindful Minutes", icon: "figure.mind.and.body", description: "Meditation session duration", platform: .iOSWatch, status: .available),
            DataSource(id: "mood", name: "Mood", icon: "face.smiling.fill", description: "Emotional state logging", platform: .iOS, status: .available),
            DataSource(id: "mood_journal", name: "Mood Journal", icon: "note.text", description: "Free-text mood entries", platform: .all, status: .manual),
            DataSource(id: "gratitude", name: "Gratitude Log", icon: "sparkles", description: "Things you're grateful for", platform: .all, status: .manual),
            DataSource(id: "journal", name: "Journal Entries", icon: "book.fill", description: "Diary and free writing", platform: .all, status: .manual),
        ]
    ),
    DataCategory(
        id: "screen_time",
        name: "Screen Time & Digital",
        icon: "iphone",
        sources: [
            DataSource(id: "screen_total", name: "Total Screen Time", icon: "hourglass", description: "Daily screen usage duration", platform: .iOS, status: .available),
            DataSource(id: "app_usage", name: "Per-App Usage", icon: "square.grid.2x2.fill", description: "Time spent in each app", platform: .iOS, status: .available),
            DataSource(id: "app_category", name: "App Category Usage", icon: "square.stack.fill", description: "Time by category (social, productivity…)", platform: .iOS, status: .available),
            DataSource(id: "pickups", name: "Phone Pickups", icon: "hand.raised.fill", description: "How often you pick up your phone", platform: .iOS, status: .available),
            DataSource(id: "notifications", name: "Notifications", icon: "bell.fill", description: "Notification count by app", platform: .iOS, status: .available),
            DataSource(id: "focus_mode", name: "Focus Mode", icon: "moon.circle.fill", description: "Active focus mode and schedule", platform: .iOSMac, status: .limited),
        ]
    ),
    DataCategory(
        id: "productivity",
        name: "Productivity",
        icon: "checkmark.circle.fill",
        sources: [
            DataSource(id: "calendar", name: "Calendar Events", icon: "calendar", description: "Meetings, appointments, time blocks", platform: .all, status: .available),
            DataSource(id: "meeting_time", name: "Meeting Time", icon: "person.2.fill", description: "Hours in meetings per day/week", platform: .all, status: .available),
            DataSource(id: "reminders", name: "Reminders Completed", icon: "checkmark.circle", description: "Tasks checked off", platform: .all, status: .available),
            DataSource(id: "active_app", name: "Active App Time", icon: "macwindow", description: "Time per application on Mac", platform: .mac, status: .limited),
            DataSource(id: "deep_work", name: "Deep Work Sessions", icon: "brain", description: "Focused uninterrupted work blocks", platform: .all, status: .manual),
        ]
    ),
    DataCategory(
        id: "developer",
        name: "Developer & Knowledge Work",
        icon: "terminal.fill",
        sources: [
            DataSource(id: "claude_sessions", name: ".claude Sessions", icon: "bubble.left.and.text.bubble.right.fill", description: "Claude Code session history", platform: .mac, status: .available),
            DataSource(id: "git_commits", name: "Git Commits", icon: "arrow.triangle.branch", description: "Commit frequency, repos, LOC changed", platform: .mac, status: .available),
            DataSource(id: "git_activity", name: "Git Activity", icon: "arrow.triangle.pull", description: "Branches, PRs, code review", platform: .mac, status: .available),
            DataSource(id: "terminal_history", name: "Terminal History", icon: "apple.terminal.fill", description: "Shell commands executed", platform: .mac, status: .available),
            DataSource(id: "code_written", name: "Code Written", icon: "chevron.left.forwardslash.chevron.right", description: "Lines of code by language", platform: .mac, status: .available),
            DataSource(id: "ide_usage", name: "IDE Usage", icon: "hammer.fill", description: "Time in Xcode, VS Code, etc.", platform: .mac, status: .limited),
            DataSource(id: "browser_tabs", name: "Browser Tabs", icon: "square.on.square", description: "Open tab count over time", platform: .mac, status: .future),
        ]
    ),
    DataCategory(
        id: "communication",
        name: "Communication",
        icon: "message.fill",
        sources: [
            DataSource(id: "imessage", name: "iMessage", icon: "message.fill", description: "Message count and conversations", platform: .iOSMac, status: .future),
            DataSource(id: "phone_calls", name: "Phone Calls", icon: "phone.fill", description: "Call frequency and duration", platform: .iOS, status: .limited),
            DataSource(id: "email", name: "Email Volume", icon: "envelope.fill", description: "Emails sent and received per day", platform: .all, status: .limited),
            DataSource(id: "chat_logs", name: "Chat Logs", icon: "text.bubble.fill", description: "WhatsApp, Telegram, Discord, Slack", platform: .all, status: .future),
            DataSource(id: "social_posts", name: "Social Media", icon: "person.2.wave.2.fill", description: "Posts, comments, likes", platform: .all, status: .future),
            DataSource(id: "video_calls", name: "Video Calls", icon: "video.fill", description: "FaceTime, Zoom, Meet duration", platform: .all, status: .limited),
        ]
    ),
    DataCategory(
        id: "media",
        name: "Media & Culture",
        icon: "play.circle.fill",
        sources: [
            DataSource(id: "music", name: "Music Listening", icon: "music.note", description: "Songs, artists, genres, duration", platform: .all, status: .available),
            DataSource(id: "podcasts", name: "Podcasts", icon: "antenna.radiowaves.left.and.right", description: "Episodes listened, duration, shows", platform: .iOS, status: .limited),
            DataSource(id: "books", name: "Books & Reading", icon: "book.fill", description: "Titles, reading time, progress", platform: .iOS, status: .limited),
            DataSource(id: "movies_tv", name: "Movies & TV", icon: "tv.fill", description: "What you watched, ratings", platform: .all, status: .manual),
            DataSource(id: "youtube", name: "YouTube History", icon: "play.rectangle.fill", description: "Videos watched, channels, time", platform: .all, status: .future),
            DataSource(id: "articles", name: "Articles Read", icon: "doc.text.fill", description: "Web articles and blog posts", platform: .all, status: .future),
            DataSource(id: "photos_taken", name: "Photos Taken", icon: "camera.fill", description: "Photo count per day", platform: .iOS, status: .available),
            DataSource(id: "screenshots", name: "Screenshots", icon: "rectangle.dashed.and.paperclip", description: "Screenshot frequency", platform: .iOS, status: .available),
        ]
    ),
    DataCategory(
        id: "location",
        name: "Location & Travel",
        icon: "location.fill",
        sources: [
            DataSource(id: "locations", name: "Significant Locations", icon: "mappin.and.ellipse", description: "Places visited with time spent", platform: .iOS, status: .available),
            DataSource(id: "home_work", name: "Home / Work Time", icon: "house.fill", description: "Time at home vs office vs other", platform: .iOS, status: .available),
            DataSource(id: "commute", name: "Commute", icon: "car.fill", description: "Travel time and route to work", platform: .iOS, status: .available),
            DataSource(id: "trips", name: "Trips & Travel", icon: "airplane", description: "Multi-day trips, destinations", platform: .iOS, status: .available),
            DataSource(id: "places", name: "Places Visited", icon: "fork.knife", description: "Restaurants, shops, venues", platform: .iOS, status: .available),
            DataSource(id: "countries", name: "Countries Visited", icon: "globe", description: "International travel log", platform: .iOS, status: .available),
        ]
    ),
    DataCategory(
        id: "environment",
        name: "Environment",
        icon: "cloud.sun.fill",
        sources: [
            DataSource(id: "weather", name: "Weather", icon: "thermometer.medium", description: "Temperature and conditions at your location", platform: .all, status: .available),
            DataSource(id: "air_quality", name: "Air Quality", icon: "aqi.medium", description: "AQI at your location", platform: .all, status: .available),
            DataSource(id: "uv_index", name: "UV Index", icon: "sun.max.fill", description: "Sun exposure risk level", platform: .all, status: .available),
            DataSource(id: "noise", name: "Ambient Noise", icon: "ear.fill", description: "Environmental noise level in dB", platform: .watch, status: .available),
            DataSource(id: "daylight", name: "Sunrise & Sunset", icon: "sunrise.fill", description: "Daylight hours at your location", platform: .all, status: .available),
        ]
    ),
    DataCategory(
        id: "finance",
        name: "Finance",
        icon: "dollarsign.circle.fill",
        sources: [
            DataSource(id: "spending", name: "Spending", icon: "creditcard.fill", description: "Transactions and amounts", platform: .all, status: .future),
            DataSource(id: "income", name: "Income", icon: "banknote.fill", description: "Earnings tracking", platform: .all, status: .manual),
            DataSource(id: "subscriptions", name: "Subscriptions", icon: "repeat.circle.fill", description: "Active subscriptions and costs", platform: .all, status: .limited),
            DataSource(id: "investments", name: "Investments", icon: "chart.line.uptrend.xyaxis", description: "Portfolio value over time", platform: .all, status: .future),
            DataSource(id: "net_worth", name: "Net Worth", icon: "building.columns.fill", description: "Assets minus liabilities", platform: .all, status: .manual),
        ]
    ),
    DataCategory(
        id: "social",
        name: "Social & Relationships",
        icon: "person.2.fill",
        sources: [
            DataSource(id: "people_met", name: "People Interactions", icon: "person.line.dotted.person.fill", description: "Who you spent time with", platform: .all, status: .manual),
            DataSource(id: "social_events", name: "Social Events", icon: "party.popper.fill", description: "Gatherings, parties, dinners", platform: .all, status: .manual),
            DataSource(id: "contact_freq", name: "Contact Frequency", icon: "person.crop.circle.badge.clock", description: "How often you reach each person", platform: .all, status: .future),
            DataSource(id: "birthdays", name: "Birthdays", icon: "gift.fill", description: "Upcoming and past birthdays", platform: .all, status: .available),
            DataSource(id: "family_time", name: "Family Time", icon: "figure.2.and.child.holdinghands", description: "Time with family members", platform: .all, status: .manual),
        ]
    ),
    DataCategory(
        id: "learning",
        name: "Learning & Growth",
        icon: "graduationcap.fill",
        sources: [
            DataSource(id: "courses", name: "Courses", icon: "desktopcomputer", description: "Online courses, progress", platform: .all, status: .manual),
            DataSource(id: "language", name: "Language Learning", icon: "character.book.closed.fill", description: "Duolingo etc. streaks and progress", platform: .all, status: .future),
            DataSource(id: "flashcards", name: "Flashcard Reviews", icon: "rectangle.on.rectangle.angled", description: "Anki/flashcard session stats", platform: .all, status: .future),
            DataSource(id: "books_finished", name: "Books Finished", icon: "book.closed.fill", description: "Completed books list", platform: .all, status: .manual),
            DataSource(id: "skills", name: "Skills Practiced", icon: "star.fill", description: "Music, art, sports practice time", platform: .all, status: .manual),
        ]
    ),
    DataCategory(
        id: "habits",
        name: "Habits & Routines",
        icon: "repeat",
        sources: [
            DataSource(id: "morning_routine", name: "Morning Routine", icon: "sunrise.fill", description: "Wake up activities and timing", platform: .all, status: .manual),
            DataSource(id: "evening_routine", name: "Evening Routine", icon: "sunset.fill", description: "Wind-down activities and timing", platform: .all, status: .manual),
            DataSource(id: "habit_streaks", name: "Habit Streaks", icon: "flame.fill", description: "Consecutive days of completion", platform: .all, status: .manual),
            DataSource(id: "custom_habits", name: "Custom Habits", icon: "plus.circle.fill", description: "User-defined habits to track", platform: .all, status: .manual),
        ]
    ),
    DataCategory(
        id: "creative",
        name: "Creative Work",
        icon: "paintbrush.fill",
        sources: [
            DataSource(id: "writing", name: "Writing", icon: "pencil.line", description: "Word count and writing sessions", platform: .all, status: .manual),
            DataSource(id: "drawing", name: "Drawing & Art", icon: "paintpalette.fill", description: "Art created, time spent", platform: .all, status: .manual),
            DataSource(id: "music_prod", name: "Music Production", icon: "pianokeys", description: "Songs produced, DAW time", platform: .mac, status: .manual),
            DataSource(id: "photo_projects", name: "Photography Projects", icon: "photo.on.rectangle.angled", description: "Curated photo projects", platform: .all, status: .manual),
        ]
    ),
    DataCategory(
        id: "device",
        name: "Device & System",
        icon: "laptopcomputer.and.iphone",
        sources: [
            DataSource(id: "battery", name: "Battery Level", icon: "battery.75percent", description: "Battery percentage over time", platform: .iOSMac, status: .available),
            DataSource(id: "storage", name: "Storage Usage", icon: "internaldrive.fill", description: "Disk space used and available", platform: .all, status: .available),
            DataSource(id: "wifi", name: "Wi-Fi Network", icon: "wifi", description: "Connected network (location proxy)", platform: .all, status: .limited),
            DataSource(id: "bluetooth", name: "Bluetooth Devices", icon: "wave.3.right", description: "Connected peripherals", platform: .all, status: .available),
            DataSource(id: "unlocks", name: "Device Unlocks", icon: "lock.open.fill", description: "Unlock frequency", platform: .iOS, status: .available),
        ]
    ),
]

// MARK: - View

struct DataCollectView: View {
    private var syncManager = SyncManager.shared

    var body: some View {
        List {
            // Sync status section
            Section {
                HStack {
                    if syncManager.state == .syncing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing...")
                            .foregroundStyle(.secondary)
                    } else if let lastSync = syncManager.lastSyncDate {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Last sync: \(lastSync, format: .relative(presentation: .named))")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("Not synced yet")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        syncManager.sync(force: true)
                    } label: {
                        Text("Sync Now")
                            .font(.subheadline)
                    }
                    .disabled(syncManager.state == .syncing)
                }

                if let error = syncManager.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(error.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }

            // Data source categories
            ForEach(dataCategories) { category in
                Section {
                    ForEach(category.sources) { source in
                        DataSourceRow(source: source)
                    }
                } header: {
                    Label(category.name, systemImage: category.icon)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle("Data Collect")
    }
}

// MARK: - Row

private struct DataSourceRow: View {
    let source: DataSource
    @AppStorage private var isEnabled: Bool

    init(source: DataSource) {
        self.source = source
        self._isEnabled = AppStorage(wrappedValue: false, "dataCollect.\(source.id)")
    }

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: 12) {
                Image(systemName: source.icon)
                    .font(.body)
                    .foregroundStyle(statusColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.body)

                    HStack(spacing: 4) {
                        Text(source.platform.rawValue)
                        Text("·")
                        Text(source.status.rawValue)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.accentColor)
    }

    private var statusColor: Color {
        switch source.status {
        case .available: return .green
        case .limited: return .orange
        case .manual: return .blue
        case .future: return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        DataCollectView()
    }
}
