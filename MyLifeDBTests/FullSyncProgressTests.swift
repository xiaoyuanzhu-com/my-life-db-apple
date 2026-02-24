//
//  FullSyncProgressTests.swift
//  MyLifeDBTests
//
//  Tests for the full sync progress model: DaySyncStatus, MonthProgress,
//  and FullSyncProgress types used by the calendar grid.
//

import Testing
import Foundation
@testable import MyLifeDB

struct FullSyncProgressTests {

    // MARK: - DaySyncStatus

    @Test func daySyncStatusDefaultIsPending() {
        let mp = MonthProgress(year: 2024, month: 1)
        // Unset days should behave as pending
        #expect(mp.dayStatuses[1] == nil)
        // And the overall status with no entries should be pending
        #expect(mp.status == .pending)
    }

    // MARK: - MonthProgress aggregate status

    @Test func allPendingYieldsPending() {
        let mp = MonthProgress(year: 2024, month: 3)
        // No dayStatuses set → all default to pending
        #expect(mp.status == .pending)
    }

    @Test func someDoneYieldsActive() {
        var mp = MonthProgress(year: 2024, month: 1) // 31 days
        // Mark only day 1 as done — not all days, so should be active
        mp.dayStatuses[1] = .done
        #expect(mp.status == .active)
    }

    @Test func allDoneYieldsDone() {
        var mp = MonthProgress(year: 2024, month: 2) // Feb 2024 = 29 days (leap)
        for day in 1...29 {
            mp.dayStatuses[day] = .done
        }
        #expect(mp.status == .done)
    }

    @Test func errorDetected() {
        var mp = MonthProgress(year: 2024, month: 1) // 31 days
        mp.dayStatuses[1] = .done
        mp.dayStatuses[2] = .error("network failure")
        #expect(mp.status == .error)
    }

    @Test func syncingYieldsActive() {
        var mp = MonthProgress(year: 2024, month: 1)
        mp.dayStatuses[5] = .syncing
        #expect(mp.status == .active)
    }

    // MARK: - daysInMonth

    @Test func daysInMonthLeapYear() {
        let feb2024 = MonthProgress(year: 2024, month: 2)
        #expect(feb2024.daysInMonth == 29)
    }

    @Test func daysInMonthNonLeapYear() {
        let feb2025 = MonthProgress(year: 2025, month: 2)
        #expect(feb2025.daysInMonth == 28)
    }

    @Test func daysInMonthJanuary() {
        let jan = MonthProgress(year: 2024, month: 1)
        #expect(jan.daysInMonth == 31)
    }

    // MARK: - firstWeekday

    @Test func firstWeekdayJan2024IsMonday() {
        // January 1, 2024 is a Monday
        let mp = MonthProgress(year: 2024, month: 1)
        #expect(mp.firstWeekday == 1)
    }

    @Test func firstWeekdayFeb2024IsThursday() {
        // February 1, 2024 is a Thursday
        let mp = MonthProgress(year: 2024, month: 2)
        #expect(mp.firstWeekday == 4)
    }

    // MARK: - MonthProgress id

    @Test func monthIdIsZeroPadded() {
        let mp = MonthProgress(year: 2024, month: 3)
        #expect(mp.id == "2024-03")

        let mp2 = MonthProgress(year: 2024, month: 12)
        #expect(mp2.id == "2024-12")
    }

    // MARK: - FullSyncProgress init

    @Test func buildsCorrectMonthRange() {
        let progress = FullSyncProgress(
            startYear: 2024, startMonth: 11,
            endYear: 2025, endMonth: 2
        )
        #expect(progress.months.count == 4) // Nov, Dec, Jan, Feb
        #expect(progress.months[0].id == "2024-11")
        #expect(progress.months[1].id == "2024-12")
        #expect(progress.months[2].id == "2025-01")
        #expect(progress.months[3].id == "2025-02")
    }

    @Test func singleMonthRange() {
        let progress = FullSyncProgress(
            startYear: 2024, startMonth: 6,
            endYear: 2024, endMonth: 6
        )
        #expect(progress.months.count == 1)
        #expect(progress.months[0].id == "2024-06")
    }

    // MARK: - years

    @Test func yearsComputedProperty() {
        let progress = FullSyncProgress(
            startYear: 2023, startMonth: 11,
            endYear: 2025, endMonth: 3
        )
        #expect(progress.years == [2023, 2024, 2025])
    }

    @Test func yearsSingleYear() {
        let progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 12
        )
        #expect(progress.years == [2024])
    }

    // MARK: - months(for:)

    @Test func monthsForYear() {
        let progress = FullSyncProgress(
            startYear: 2024, startMonth: 10,
            endYear: 2025, endMonth: 2
        )
        let m2024 = progress.months(for: 2024)
        #expect(m2024.count == 3) // Oct, Nov, Dec
        #expect(m2024.map(\.month) == [10, 11, 12])

        let m2025 = progress.months(for: 2025)
        #expect(m2025.count == 2) // Jan, Feb
        #expect(m2025.map(\.month) == [1, 2])
    }

    // MARK: - yearStatus

    @Test func yearStatusAllPending() {
        let progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 3
        )
        #expect(progress.yearStatus(2024) == .pending)
    }

    @Test func yearStatusAllDone() {
        var progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 1
        )
        // Mark all 31 days of January as done
        for day in 1...31 {
            progress.months[0].dayStatuses[day] = .done
        }
        #expect(progress.yearStatus(2024) == .done)
    }

    @Test func yearStatusMixed() {
        var progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 2
        )
        // Mark all of January as done
        for day in 1...31 {
            progress.months[0].dayStatuses[day] = .done
        }
        // February still pending → year should be active
        #expect(progress.yearStatus(2024) == .active)
    }

    @Test func yearStatusWithError() {
        var progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 2
        )
        progress.months[0].dayStatuses[1] = .error("fail")
        #expect(progress.yearStatus(2024) == .error)
    }

    @Test func yearStatusForMissingYear() {
        let progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 3
        )
        #expect(progress.yearStatus(1999) == .pending)
    }

    // MARK: - completedMonthKeys

    @Test func completedMonthKeysWhenNoneDone() {
        let progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 3
        )
        #expect(progress.completedMonthKeys.isEmpty)
    }

    @Test func completedMonthKeysTracksFullyDoneMonths() {
        var progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 2
        )
        // Complete January (31 days)
        for day in 1...31 {
            progress.months[0].dayStatuses[day] = .done
        }
        // Partially complete February
        progress.months[1].dayStatuses[1] = .done

        let keys = progress.completedMonthKeys
        #expect(keys.contains("2024-01"))
        #expect(!keys.contains("2024-02"))
    }

    // MARK: - restoreCompleted

    @Test func restoreCompletedMarksDaysAsDone() {
        var progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 3
        )
        // Restore January and March
        progress.restoreCompleted(["2024-01", "2024-03"])

        // January (31 days) should all be done
        #expect(progress.months[0].status == .done)
        for day in 1...31 {
            #expect(progress.months[0].dayStatuses[day] == .done)
        }

        // February should still be pending
        #expect(progress.months[1].status == .pending)

        // March (31 days) should all be done
        #expect(progress.months[2].status == .done)
    }

    @Test func restoreCompletedIgnoresUnknownKeys() {
        var progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 1
        )
        // Should not crash or change anything
        progress.restoreCompleted(["2099-12"])
        #expect(progress.months[0].status == .pending)
    }

    @Test func restoreCompletedRoundTrips() {
        var progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 3
        )
        // Complete January
        for day in 1...31 {
            progress.months[0].dayStatuses[day] = .done
        }

        // Save completed keys
        let saved = progress.completedMonthKeys
        #expect(saved == ["2024-01"])

        // Build a new progress and restore
        var fresh = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 3
        )
        fresh.restoreCompleted(saved)

        #expect(fresh.months[0].status == .done)
        #expect(fresh.months[1].status == .pending)
        #expect(fresh.months[2].status == .pending)
        #expect(fresh.completedMonthKeys == saved)
    }
}
