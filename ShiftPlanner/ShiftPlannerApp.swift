import SwiftUI

@main
struct ShiftPlannerApp: App {
    @State private var store = ScheduleStore()

    var body: some Scene {
        WindowGroup {
            SetupView(store: store)
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
    }
}

@MainActor @Observable
final class ScheduleStore {
    var year: Int
    var month: Int
    var minStaffPerDay = 2
    var maxConsecutiveShifts = 2
    var employees = Employee.samples
    var candidates: [ScheduleCandidate] = []
    var selectedIndex = 0
    private(set) var generatedContext: SolverContext?

    init() {
        let next = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
        year = Calendar.current.component(.year, from: next)
        month = Calendar.current.component(.month, from: next)
    }

    var monthInfo: MonthInfo { MonthInfo(year: year, month: month) }

    var current: ScheduleCandidate? {
        candidates.indices.contains(selectedIndex) ? candidates[selectedIndex] : nil
    }

    func generate() {
        let context = SolverContext(employees: employees, year: year, month: month,
                                    minStaffPerDay: minStaffPerDay, maxConsecutiveShifts: maxConsecutiveShifts)
        generatedContext = context
        candidates = ScheduleSolver.generateSchedules(context: context)
        selectedIndex = 0
    }

    func applyEdit(employeeID: UUID, day: Int, status: ShiftStatus, hours: Double) {
        guard let context = generatedContext, let candidate = current else { return }
        candidates[selectedIndex] = ScheduleSolver.rebalanceSchedule(
            candidate, context: context, editing: employeeID, day: day, status: status, hours: hours)
    }

    func setLock(employeeID: UUID, day: Int, locked: Bool) {
        guard let context = generatedContext, var candidate = current else { return }
        candidate.grid[employeeID]?[day]?.isLocked = locked
        candidates[selectedIndex] = locked ? candidate : ScheduleSolver.rebalanceSchedule(candidate, context: context)
    }

    func resetManualEdits() {
        guard let context = generatedContext, var candidate = current else { return }
        for id in candidate.grid.keys {
            for day in candidate.grid[id, default: [:]].keys { candidate.grid[id]?[day]?.isLocked = false }
        }
        candidates[selectedIndex] = ScheduleSolver.rebalanceSchedule(candidate, context: context)
    }
}
