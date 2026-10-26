import SwiftUI

enum ShiftStatus: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case work, mandatory, vacation, desiredOff, off

    var id: String { rawValue }
    var isWorking: Bool { self == .work || self == .mandatory }

    var title: String {
        switch self {
        case .work: "Смена"
        case .mandatory: "Обязательная смена"
        case .vacation: "Отпуск"
        case .desiredOff: "Желаемый выходной"
        case .off: "Выходной"
        }
    }

    var shortLabel: String {
        switch self {
        case .work: "С"
        case .mandatory: "О"
        case .vacation: "Отп"
        case .desiredOff: "Жв"
        case .off: "В"
        }
    }

    var icon: String {
        switch self {
        case .work: "briefcase.fill"
        case .mandatory: "exclamationmark.circle.fill"
        case .vacation: "airplane"
        case .desiredOff: "heart.fill"
        case .off: "moon.zzz.fill"
        }
    }

    var color: Color {
        switch self {
        case .work: .blue
        case .mandatory: .purple
        case .vacation: .orange
        case .desiredOff: .green
        case .off: .gray
        }
    }
}

struct Employee: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var defaultShiftHours: Double
    var targetMonthlyHours: Double
    var vacationDays: Set<Int> = []
    var desiredOffDays: Set<Int> = []
    var mandatoryShiftDays: Set<Int> = []

    static var samples: [Employee] {
        [
            Employee(name: "Иванов А.", defaultShiftHours: 12, targetMonthlyHours: 144,
                     desiredOffDays: [6, 7], mandatoryShiftDays: [1]),
            Employee(name: "Петров С.", defaultShiftHours: 12, targetMonthlyHours: 144,
                     desiredOffDays: [14, 15, 21]),
            Employee(name: "Сидорова Е.", defaultShiftHours: 12, targetMonthlyHours: 132,
                     vacationDays: [10, 11, 12, 13]),
            Employee(name: "Кузнецов Д.", defaultShiftHours: 8, targetMonthlyHours: 160,
                     desiredOffDays: [1, 2], mandatoryShiftDays: [15, 16]),
            Employee(name: "Смирнова О.", defaultShiftHours: 12, targetMonthlyHours: 120,
                     vacationDays: [20, 21, 22], desiredOffDays: [28])
        ]
    }
}

struct DayAssignment: Codable, Identifiable, Equatable, Hashable, Sendable {
    var day: Int
    var employeeID: UUID
    var status: ShiftStatus
    var hours: Double
    var isLocked = false

    var id: String { "\(employeeID.uuidString)-\(day)" }
}

struct ScheduleCandidate: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var grid: [UUID: [Int: DayAssignment]]
    var penaltyScore: Int
    var compromises: [String]

    func assignment(_ employeeID: UUID, _ day: Int) -> DayAssignment? {
        grid[employeeID]?[day]
    }

    func workedHours(of employeeID: UUID) -> Double {
        grid[employeeID]?.values.filter { $0.status.isWorking }.reduce(0) { $0 + $1.hours } ?? 0
    }

    func hoursDeviation(of employee: Employee) -> Double {
        workedHours(of: employee.id) - employee.targetMonthlyHours
    }

    func staffCount(on day: Int) -> Int {
        grid.values.filter { $0[day]?.status.isWorking == true }.count
    }

    var lockedCount: Int {
        grid.values.reduce(0) { $0 + $1.values.filter(\.isLocked).count }
    }

    func sameAssignments(as other: ScheduleCandidate) -> Bool {
        guard Set(grid.keys) == Set(other.grid.keys) else { return false }
        return grid.allSatisfy { id, days in
            days.allSatisfy { day, a in other.grid[id]?[day]?.status.isWorking == a.status.isWorking }
        }
    }
}

struct MonthInfo: Sendable, Equatable {
    let year: Int
    let month: Int

    static let monthNames = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
                             "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
    static let genitiveNames = ["января", "февраля", "марта", "апреля", "мая", "июня",
                                "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    static let weekdaySymbols = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    private func date(_ day: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    var daysCount: Int { Self.calendar.range(of: .day, in: .month, for: date(1))?.count ?? 30 }
    var days: [Int] { Array(1...daysCount) }
    var title: String { "\(Self.monthNames[month - 1]) \(year)" }
    var leadingBlanks: Int { weekdayIndex(1) }

    func weekdayIndex(_ day: Int) -> Int {
        (Self.calendar.component(.weekday, from: date(day)) + 5) % 7
    }

    func weekdaySymbol(_ day: Int) -> String { Self.weekdaySymbols[weekdayIndex(day)] }
    func isWeekend(_ day: Int) -> Bool { weekdayIndex(day) >= 5 }
    func dayTitle(_ day: Int) -> String { "\(day) \(Self.genitiveNames[month - 1])" }
}

extension Double {
    var hoursText: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.1f", self)
    }

    var signedHoursText: String { (self > 0 ? "+" : self < 0 ? "−" : "") + abs(self).hoursText }
}
