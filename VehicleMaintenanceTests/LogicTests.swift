import Foundation
import Testing
@testable import VehicleMaintenance

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day))!
}

struct DueCalculatorTests {
    let calculator = DueCalculator(soonDistance: 500, soonDays: 30, calendar: utc)
    let now = date(2026, 6, 15)

    @Test func nextDueDateAddsMonths() {
        #expect(calculator.nextDueDate(lastDate: date(2026, 1, 31), intervalMonths: 6) == date(2026, 7, 31))
        #expect(calculator.nextDueDate(lastDate: now, intervalMonths: nil) == nil)
        #expect(calculator.nextDueDate(lastDate: now, intervalMonths: 0) == nil)
    }

    @Test func nextDueOdometerAddsInterval() {
        #expect(calculator.nextDueOdometer(lastOdometer: 40_000, intervalDistance: 5_000) == 45_000)
        #expect(calculator.nextDueOdometer(lastOdometer: 40_000, intervalDistance: nil) == nil)
    }

    @Test func okWithNoIntervals() {
        #expect(calculator.status(nextDueDate: nil, nextDueOdometer: nil, currentOdometer: 1, now: now) == .ok)
    }

    @Test func statusByDistance() {
        #expect(calculator.status(nextDueDate: nil, nextDueOdometer: 45_000, currentOdometer: 44_000, now: now) == .ok)
        #expect(calculator.status(nextDueDate: nil, nextDueOdometer: 45_000, currentOdometer: 44_500, now: now) == .dueSoon)
        #expect(calculator.status(nextDueDate: nil, nextDueOdometer: 45_000, currentOdometer: 45_000, now: now) == .overdue)
    }

    @Test func statusByDate() {
        #expect(calculator.status(nextDueDate: date(2026, 9, 1), nextDueOdometer: nil, currentOdometer: 0, now: now) == .ok)
        #expect(calculator.status(nextDueDate: date(2026, 7, 1), nextDueOdometer: nil, currentOdometer: 0, now: now) == .dueSoon)
        #expect(calculator.status(nextDueDate: date(2026, 6, 1), nextDueOdometer: nil, currentOdometer: 0, now: now) == .overdue)
    }

    @Test func usesWorstOfDateAndDistance() {
        let status = calculator.status(nextDueDate: date(2026, 1, 1), nextDueOdometer: 90_000, currentOdometer: 10_000, now: now)
        #expect(status == .overdue)
    }
}

struct CostAggregationTests {
    @Test func bucketsByMonthAndFillsGaps() {
        let entries: [(date: Date, cost: Double)] = [
            (date(2026, 6, 2), 50),
            (date(2026, 6, 20), 25),
            (date(2026, 4, 10), 100),
            (date(2025, 1, 1), 999), // outside the window
        ]
        let totals = CostAggregation.monthlyTotals(entries, months: 3, endingAt: date(2026, 6, 15), calendar: utc)
        #expect(totals.map(\.month) == [date(2026, 4, 1), date(2026, 5, 1), date(2026, 6, 1)])
        #expect(totals.map(\.total) == [100, 0, 75])
    }
}

struct CSVTests {
    @Test func escapesSpecialCharacters() {
        #expect(CSV.escape("plain") == "plain")
        #expect(CSV.escape("a,b") == "\"a,b\"")
        #expect(CSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSV.escape("line\nbreak") == "\"line\nbreak\"")
    }

    @Test func buildsRows() {
        #expect(CSV.make(header: ["A", "B"], rows: [["1", "x,y"]]) == "A,B\n1,\"x,y\"")
    }
}

struct NumberParsingTests {
    @Test func parsesIntegersWithSeparators() {
        #expect(NumberParsing.int("48,250") == 48_250)
        #expect(NumberParsing.int(" 1 200 ") == 1_200)
        #expect(NumberParsing.int("") == nil)
    }

    @Test func parsesLocalizedDecimals() throws {
        let us = try #require(NumberParsing.decimal("89.99", locale: Locale(identifier: "en_US")))
        let de = try #require(NumberParsing.decimal("89,99", locale: Locale(identifier: "de_DE")))
        #expect(abs(us - 89.99) < 0.0001)
        #expect(abs(de - 89.99) < 0.0001)
        #expect(NumberParsing.decimal("  ", locale: Locale(identifier: "en_US")) == nil)
    }
}

struct ServiceTypeTests {
    @Test func convertsSuggestedIntervalsToKilometers() {
        #expect(ServiceType.oilChange.suggestedInterval(in: .miles).distance == 5_000)
        #expect(ServiceType.oilChange.suggestedInterval(in: .kilometers).distance == 8_000)
        #expect(ServiceType.battery.suggestedInterval(in: .kilometers).distance == nil)
    }
}
