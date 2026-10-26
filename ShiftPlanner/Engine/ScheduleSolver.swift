import Foundation

struct SolverContext: Sendable, Equatable {
    var employees: [Employee]
    var year: Int
    var month: Int
    var minStaffPerDay: Int
    var maxConsecutiveShifts: Int = 2

    var monthInfo: MonthInfo { MonthInfo(year: year, month: month) }
}

struct PenaltyWeights: Sendable {
    var desiredOff: Double = 100
    var shortage: Double = 80
    var hour: Double = 10
    var consecutive: Double = 40
    var change: Double = 0
    var balance: Double = 0.5
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum ScheduleSolver {
    private static let variants: [(title: String, weights: PenaltyWeights, coverageFirst: Bool)] = [
        ("Вариант 1 · Желаемые выходные", PenaltyWeights(desiredOff: 1000, shortage: 80, hour: 4), false),
        ("Вариант 2 · Норма часов", PenaltyWeights(desiredOff: 100, shortage: 60, hour: 60), false),
        ("Вариант 3 · Закрытие смен", PenaltyWeights(desiredOff: 60, shortage: 600, hour: 8, consecutive: 30), true)
    ]

    static func generateSchedules(context: SolverContext, preserving source: ScheduleCandidate? = nil) -> [ScheduleCandidate] {
        let ideal = solve(context, source: source, weights: PenaltyWeights(), coverageFirst: false, seed: 1)
        if ideal.penaltyScore == 0 {
            var result = ideal
            result.title = "Идеальный график"
            return [result]
        }
        var results: [ScheduleCandidate] = []
        for (index, variant) in variants.enumerated() {
            for attempt in 0..<4 {
                var candidate = solve(context, source: source, weights: variant.weights,
                                      coverageFirst: variant.coverageFirst, seed: UInt64(index * 100 + attempt + 7))
                guard !results.contains(where: { $0.sameAssignments(as: candidate) }) else { continue }
                candidate.title = variant.title
                results.append(candidate)
                break
            }
        }
        return results.isEmpty ? [ideal] : results
    }

    static func rebalanceSchedule(_ candidate: ScheduleCandidate, context: SolverContext,
                                  editing employeeID: UUID? = nil, day: Int = 0,
                                  status: ShiftStatus = .work, hours: Double = 0,
                                  directorInMinimum: Bool = false) -> ScheduleCandidate {
        var source = candidate
        if let employeeID {
            source.grid[employeeID, default: [:]][day] = DayAssignment(
                day: day, employeeID: employeeID, status: status,
                hours: status.isWorking ? hours : 0, isLocked: true,
                directorInMinimum: directorInMinimum && status.isWorking)
        }
        var board = Board(context: context, source: source, keepUnlocked: true,
                          weights: PenaltyWeights(change: 3, balance: 0))
        board.baseline = board.statuses.map { $0.map(\.isWorking) }
        var rng = SeededGenerator(state: 42)
        board.optimize(&rng)
        return board.makeCandidate(title: candidate.title, id: candidate.id)
    }

    private static func solve(_ context: SolverContext, source: ScheduleCandidate?, weights: PenaltyWeights,
                              coverageFirst: Bool, seed: UInt64) -> ScheduleCandidate {
        var rng = SeededGenerator(state: seed)
        var board = Board(context: context, source: source, keepUnlocked: false, weights: weights)
        board.greedyFill(&rng, coverageFirst: coverageFirst)
        board.optimize(&rng)
        var best = board
        var bestCost = best.totalCost
        for _ in 0..<6 {
            var trial = best
            trial.perturb(&rng, flips: max(3, context.employees.count))
            trial.optimize(&rng)
            let cost = trial.totalCost
            if cost < bestCost - 1e-9 { best = trial; bestCost = cost }
        }
        return best.makeCandidate(title: "", id: UUID())
    }
}

private struct Board {
    let ctx: SolverContext
    let days: Int
    let weights: PenaltyWeights
    var statuses: [[ShiftStatus]]
    var hours: [[Double]]
    var fixed: [[Bool]]
    var locked: [[Bool]]
    var directorCounted: [[Bool]]
    var baseline: [[Bool]]?

    init(context: SolverContext, source: ScheduleCandidate?, keepUnlocked: Bool, weights: PenaltyWeights) {
        ctx = context
        days = context.monthInfo.daysCount
        self.weights = weights
        let n = context.employees.count
        statuses = Array(repeating: Array(repeating: .off, count: days), count: n)
        hours = Array(repeating: Array(repeating: 0, count: days), count: n)
        fixed = Array(repeating: Array(repeating: false, count: days), count: n)
        locked = fixed
        directorCounted = fixed
        for (e, emp) in context.employees.enumerated() {
            for d in 0..<days {
                let day = d + 1
                let previous = source?.assignment(emp.id, day)
                if let previous, previous.isLocked {
                    statuses[e][d] = previous.status
                    hours[e][d] = previous.hours
                    fixed[e][d] = true
                    locked[e][d] = true
                    directorCounted[e][d] = previous.directorInMinimum && previous.status.isWorking
                } else if emp.vacationDays.contains(day) {
                    statuses[e][d] = .vacation
                    fixed[e][d] = true
                } else if emp.mandatoryShiftDays.contains(day) {
                    statuses[e][d] = .mandatory
                    hours[e][d] = emp.defaultShiftHours
                    fixed[e][d] = true
                } else {
                    setFree(e, d, keepUnlocked && previous?.status.isWorking == true)
                }
            }
        }
    }

    func works(_ e: Int, _ d: Int) -> Bool { statuses[e][d].isWorking }

    mutating func setFree(_ e: Int, _ d: Int, _ working: Bool) {
        let emp = ctx.employees[e]
        statuses[e][d] = working ? .work : (emp.desiredOffDays.contains(d + 1) ? .desiredOff : .off)
        hours[e][d] = working ? emp.defaultShiftHours : 0
        directorCounted[e][d] = false
    }

    func counts(_ e: Int, _ d: Int) -> Bool {
        works(e, d) && (!ctx.employees[e].isDirector || directorCounted[e][d])
    }

    func staff(_ d: Int) -> Int { (0..<statuses.count).filter { counts($0, d) }.count }

    func run(_ e: Int, around d: Int) -> Int {
        var count = 1, i = d - 1, j = d + 1
        while i >= 0, works(e, i) { count += 1; i -= 1 }
        while j < days, works(e, j) { count += 1; j += 1 }
        return count
    }

    func employeeCost(_ e: Int) -> Double {
        let emp = ctx.employees[e]
        var total = 0.0, run = 0, over = 0, desired = 0, changes = 0
        for d in 0..<days {
            if works(e, d) {
                total += hours[e][d]
                run += 1
                if run > ctx.maxConsecutiveShifts { over += 1 }
                if emp.desiredOffDays.contains(d + 1) { desired += 1 }
            } else {
                run = 0
            }
            if let baseline, baseline[e][d] != works(e, d) { changes += 1 }
        }
        return Double(desired) * weights.desiredOff + abs(total - emp.targetMonthlyHours) * weights.hour
            + Double(over) * weights.consecutive + Double(changes) * weights.change
    }

    func dayCost(_ d: Int) -> Double {
        let count = staff(d)
        return Double(max(0, ctx.minStaffPerDay - count)) * weights.shortage + Double(count * count) * weights.balance
    }

    var totalCost: Double {
        (0..<statuses.count).reduce(0) { $0 + employeeCost($1) } + (0..<days).reduce(0) { $0 + dayCost($1) }
    }

    mutating func greedyFill(_ rng: inout SeededGenerator, coverageFirst: Bool) {
        let n = ctx.employees.count
        var need = ctx.employees.enumerated().map { e, emp in
            let fixedHours = (0..<days).filter { fixed[e][$0] && works(e, $0) }.reduce(0.0) { $0 + hours[e][$1] }
            return max(0, Int(((emp.targetMonthlyHours - fixedHours) / max(emp.defaultShiftHours, 1)).rounded()))
        }
        let tieBreak = (0..<n).map { _ in Int.random(in: 0..<1000, using: &rng) }
        for d in 0..<days {
            var count = staff(d)
            let order = (0..<n).filter { !ctx.employees[$0].isDirector && !fixed[$0][d] && !works($0, d) }.sorted {
                let a = ctx.employees[$0].desiredOffDays.contains(d + 1), b = ctx.employees[$1].desiredOffDays.contains(d + 1)
                if a != b { return !a }
                return need[$0] != need[$1] ? need[$0] > need[$1] : tieBreak[$0] < tieBreak[$1]
            }
            for e in order where count < ctx.minStaffPerDay {
                let strict = !coverageFirst
                if strict && (need[e] <= 0 || ctx.employees[e].desiredOffDays.contains(d + 1)) { continue }
                if strict && run(e, around: d) > ctx.maxConsecutiveShifts { continue }
                setFree(e, d, true)
                need[e] -= 1
                count += 1
            }
        }
        for e in (0..<n).shuffled(using: &rng) where need[e] > 0 {
            let free = (0..<days).filter {
                !fixed[e][$0] && !works(e, $0) && !ctx.employees[e].desiredOffDays.contains($0 + 1)
            }.shuffled(using: &rng).sorted { staff($0) < staff($1) }
            for d in free where need[e] > 0 && run(e, around: d) <= ctx.maxConsecutiveShifts {
                setFree(e, d, true)
                need[e] -= 1
            }
        }
    }

    mutating func perturb(_ rng: inout SeededGenerator, flips: Int) {
        let free = (0..<statuses.count).flatMap { e in (0..<days).filter { !fixed[e][$0] }.map { (e, $0) } }
        for (e, d) in free.shuffled(using: &rng).prefix(flips) { setFree(e, d, !works(e, d)) }
    }

    mutating func optimize(_ rng: inout SeededGenerator, maxPasses: Int = 40) {
        let eps = 1e-9
        for _ in 0..<maxPasses {
            var improved = false
            let eOrder = (0..<statuses.count).shuffled(using: &rng)
            let dOrder = (0..<days).shuffled(using: &rng)
            for e in eOrder {
                for d in dOrder where !fixed[e][d] {
                    let before = employeeCost(e) + dayCost(d), was = works(e, d)
                    setFree(e, d, !was)
                    if employeeCost(e) + dayCost(d) < before - eps { improved = true } else { setFree(e, d, was) }
                }
            }
            for d in dOrder {
                for a in eOrder where !fixed[a][d] && works(a, d) {
                    for b in eOrder where b != a && !fixed[b][d] && !works(b, d) {
                        let before = employeeCost(a) + employeeCost(b)
                        setFree(a, d, false); setFree(b, d, true)
                        if employeeCost(a) + employeeCost(b) < before - eps { improved = true; break }
                        setFree(b, d, false); setFree(a, d, true)
                    }
                }
            }
            for e in eOrder {
                for d1 in dOrder where !fixed[e][d1] && works(e, d1) {
                    for d2 in dOrder where d2 != d1 && !fixed[e][d2] && !works(e, d2) {
                        let before = employeeCost(e) + dayCost(d1) + dayCost(d2)
                        setFree(e, d1, false); setFree(e, d2, true)
                        if employeeCost(e) + dayCost(d1) + dayCost(d2) < before - eps { improved = true; break }
                        setFree(e, d2, false); setFree(e, d1, true)
                    }
                }
            }
            if !improved { break }
        }
    }

    func makeCandidate(title: String, id: UUID) -> ScheduleCandidate {
        let base = PenaltyWeights()
        var grid: [UUID: [Int: DayAssignment]] = [:]
        var penalty = 0
        var shortages: [String] = [], desired: [String] = [], hourNotes: [String] = [], runs: [String] = []
        for (e, emp) in ctx.employees.enumerated() {
            var row: [Int: DayAssignment] = [:]
            var total = 0.0, runStart = 0, runLength = 0
            for d in 0..<days {
                row[d + 1] = DayAssignment(day: d + 1, employeeID: emp.id, status: statuses[e][d],
                                           hours: hours[e][d], isLocked: locked[e][d],
                                           directorInMinimum: directorCounted[e][d], countsToMinimum: counts(e, d))
                if works(e, d) {
                    total += hours[e][d]
                    if runLength == 0 { runStart = d + 1 }
                    runLength += 1
                    if runLength > ctx.maxConsecutiveShifts { penalty += Int(base.consecutive) }
                    if emp.desiredOffDays.contains(d + 1) {
                        penalty += Int(base.desiredOff)
                        desired.append("\(emp.name): смена \(d + 1) числа вместо желаемого выходного")
                    }
                }
                if !works(e, d) || d == days - 1 {
                    if runLength > ctx.maxConsecutiveShifts {
                        runs.append("\(emp.name): \(runLength) смен подряд с \(runStart) числа (лимит \(ctx.maxConsecutiveShifts))")
                    }
                    if !works(e, d) { runLength = 0 }
                }
            }
            grid[emp.id] = row
            let deviation = total - emp.targetMonthlyHours
            penalty += Int((abs(deviation) * base.hour).rounded())
            if abs(deviation) >= 0.5 {
                hourNotes.append("\(emp.name): \(deviation.signedHoursText)ч к месячной норме")
            }
        }
        for d in 0..<days {
            let count = staff(d)
            guard count < ctx.minStaffPerDay else { continue }
            penalty += (ctx.minStaffPerDay - count) * Int(base.shortage)
            let director = (0..<statuses.count).contains {
                ctx.employees[$0].isDirector && works($0, d) && !directorCounted[$0][d]
            }
            shortages.append("\(d + 1) числа на смене \(count) чел. вместо \(ctx.minStaffPerDay)"
                + (director ? " (директор на смене, его можно засчитать)" : ""))
        }
        return ScheduleCandidate(id: id, title: title, grid: grid, penaltyScore: penalty,
                                 compromises: shortages + desired + hourNotes + runs)
    }
}
