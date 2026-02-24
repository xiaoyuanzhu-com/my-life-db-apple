//
//  HKTypeFileNameTests.swift
//  MyLifeDBTests
//
//  Tests for HK type identifier → kebab-case filename mapping.
//

import Testing
@testable import MyLifeDB

struct HKTypeFileNameTests {

    // MARK: - Quantity types: strip prefix, kebab-case

    @Test func quantityTypeStepCount() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierStepCount")
        #expect(name == "step-count")
    }

    @Test func quantityTypeHeartRate() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierHeartRate")
        #expect(name == "heart-rate")
    }

    @Test func quantityTypeHeartRateVariabilitySDNN() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
        #expect(name == "heart-rate-variability-sdnn")
    }

    @Test func quantityTypeVO2Max() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierVO2Max")
        #expect(name == "vo2-max")
    }

    @Test func quantityTypeAppleExerciseTime() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierAppleExerciseTime")
        #expect(name == "apple-exercise-time")
    }

    @Test func quantityTypeBloodPressureSystolic() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierBloodPressureSystolic")
        #expect(name == "blood-pressure-systolic")
    }

    // MARK: - Category types: strip prefix, kebab-case

    @Test func categoryTypeSleepAnalysis() {
        let name = HKTypeFileName.fileName(for: "HKCategoryTypeIdentifierSleepAnalysis")
        #expect(name == "sleep-analysis")
    }

    @Test func categoryTypeMindfulSession() {
        let name = HKTypeFileName.fileName(for: "HKCategoryTypeIdentifierMindfulSession")
        #expect(name == "mindful-session")
    }

    @Test func categoryTypeAppleStandHour() {
        let name = HKTypeFileName.fileName(for: "HKCategoryTypeIdentifierAppleStandHour")
        #expect(name == "apple-stand-hour")
    }

    // MARK: - Workout type: uses "workout" prefix

    @Test func workoutTypeNoActivity() {
        let name = HKTypeFileName.fileName(for: "HKWorkoutTypeIdentifier")
        #expect(name == "workout")
    }

    @Test func workoutWithActivityType() {
        let name = HKTypeFileName.workoutFileName(activityName: "running")
        #expect(name == "workout-running")
    }

    @Test func workoutWithFunctionalStrengthTraining() {
        let name = HKTypeFileName.workoutFileName(activityName: "functionalStrengthTraining")
        #expect(name == "workout-functional-strength-training")
    }

    // MARK: - Edge cases

    @Test func unknownTypePassesThrough() {
        let name = HKTypeFileName.fileName(for: "HKSomeFutureTypeIdentifierNewThing")
        #expect(name == "new-thing")
    }

    @Test func consecutiveUppercase() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
        #expect(name == "heart-rate-variability-sdnn")
    }
}
