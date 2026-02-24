//
//  SyncCalendarGrid.swift
//  MyLifeDB
//
//  Calendar grid components for the full-history sync view.
//  Date numbers turn green as each day completes syncing.
//

import SwiftUI

// MARK: - Pulse Animation

/// Fades opacity between 1.0 and 0.4, repeating forever.
struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

extension View {
    func pulse() -> some View {
        modifier(PulseAnimation())
    }
}

// MARK: - Status Dot

/// Small circle indicator for month/year headers.
private struct StatusDot: View {
    let status: AggregateStatus
    var size: CGFloat = 6

    var body: some View {
        switch status {
        case .pending:
            EmptyView()
        case .active:
            Circle()
                .fill(Color.accentColor)
                .frame(width: size, height: size)
                .pulse()
        case .done:
            Circle()
                .fill(Color.green)
                .frame(width: size, height: size)
        case .error:
            Circle()
                .fill(Color.red)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Month Calendar Grid

/// Renders a single month as a Mon-Sun calendar grid with colored date numbers.
struct MonthCalendarGrid: View {
    let month: MonthProgress

    private static let weekdays: [(id: Int, label: String)] = [
        (0, "M"), (1, "T"), (2, "W"), (3, "T"), (4, "F"), (5, "S"), (6, "S"),
    ]
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Month header
            HStack(spacing: 6) {
                Text(monthName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                StatusDot(status: month.status)
            }

            // Weekday headers
            LazyVGrid(columns: Self.columns, spacing: 2) {
                ForEach(Self.weekdays, id: \.id) { day in
                    Text(day.label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Date numbers
            LazyVGrid(columns: Self.columns, spacing: 2) {
                // Empty cells before the 1st
                ForEach(0..<(month.firstWeekday - 1), id: \.self) { _ in
                    Text("")
                        .frame(maxWidth: .infinity, minHeight: 20)
                }

                // Day numbers
                ForEach(1...month.daysInMonth, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let status = month.dayStatuses[day] ?? .pending
        Text("\(day)")
            .font(.caption)
            .monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 20)
            .modifier(DayStatusModifier(status: status))
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let dc = DateComponents(year: month.year, month: month.month, day: 1)
        guard let date = Calendar(identifier: .gregorian).date(from: dc) else {
            return "?"
        }
        return formatter.string(from: date)
    }
}

// MARK: - Day Status Modifier

/// Applies color and animation based on day sync status.
private struct DayStatusModifier: ViewModifier {
    let status: DaySyncStatus

    func body(content: Content) -> some View {
        switch status {
        case .pending:
            content
                .foregroundStyle(.gray)
                .opacity(0.3)
        case .syncing:
            content
                .foregroundStyle(Color.accentColor)
                .pulse()
        case .done:
            content
                .foregroundStyle(.green)
        case .error:
            content
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Year Section

/// Displays a year header and all months for that year.
struct YearSection: View {
    let year: Int
    let months: [MonthProgress]
    let yearStatus: AggregateStatus

    private static let monthColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Year header
            HStack(spacing: 8) {
                Text(String(year))
                    .font(.title3)
                    .fontWeight(.semibold)
                StatusDot(status: yearStatus, size: 8)
            }
            .padding(.bottom, 4)

            // Months in a 3-column grid
            LazyVGrid(columns: Self.monthColumns, alignment: .leading, spacing: 16) {
                ForEach(months) { month in
                    MonthCalendarGrid(month: month)
                }
            }
        }
        .padding(.bottom, 8)
    }
}

#Preview("Month Grid") {
    let month = MonthProgress(
        year: 2024,
        month: 3,
        dayStatuses: [
            1: .done, 2: .done, 3: .done, 4: .done, 5: .done,
            6: .syncing, 7: .pending, 8: .pending, 9: .error("fail"),
        ]
    )
    MonthCalendarGrid(month: month)
        .padding()
}

#Preview("Year Section") {
    let months = (1...12).map { m in
        MonthProgress(year: 2024, month: m, dayStatuses: [:])
    }
    ScrollView {
        YearSection(year: 2024, months: months, yearStatus: .pending)
            .padding()
    }
}
