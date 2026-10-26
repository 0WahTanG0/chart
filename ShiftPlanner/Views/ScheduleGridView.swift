import SwiftUI

struct CellRef: Identifiable, Hashable {
    let employeeID: UUID
    let day: Int
    var id: String { "\(employeeID.uuidString)-\(day)" }
}

private struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ScheduleGridView: View {
    @Bindable var store: ScheduleStore
    @State private var editing: CellRef?
    @State private var shareItem: ShareImage?
    @State private var showCompromises = true

    private let cellSize: CGFloat = 46
    private let nameWidth: CGFloat = 132

    var body: some View {
        Group {
            if let candidate = store.current, let context = store.generatedContext {
                VStack(spacing: 0) {
                    header(candidate)
                    Divider()
                    table(candidate, context)
                }
            } else {
                ContentUnavailableView("Нет графика", systemImage: "calendar",
                                       description: Text("Сформируйте график на экране настройки."))
            }
        }
        .navigationTitle(store.generatedContext?.monthInfo.title ?? "График")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("В общий чат (Картинка)", systemImage: "paperplane") { share() }
                Button("На печать", systemImage: "printer") { printSchedule() }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Сбросить ручные правки", systemImage: "lock.open") {
                    withAnimation(.snappy) { store.resetManualEdits() }
                }
                .labelStyle(.titleAndIcon)
                .disabled((store.current?.lockedCount ?? 0) == 0)
            }
        }
        .sheet(item: $editing) { ref in
            CellEditorView(store: store, ref: ref).presentationDetents([.medium, .large])
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.image]).ignoresSafeArea()
        }
    }

    private func header(_ candidate: ScheduleCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.candidates.count > 1 {
                Picker("Вариант", selection: $store.selectedIndex.animation(.snappy)) {
                    ForEach(store.candidates.indices, id: \.self) { Text("Вариант \($0 + 1)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Text(candidate.title).font(.headline)
                Spacer()
                Text("Штраф: \(candidate.penaltyScore)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((candidate.penaltyScore == 0 ? Color.green : .orange).opacity(0.2), in: Capsule())
            }
            if candidate.compromises.isEmpty {
                Label("Все ограничения соблюдены", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                DisclosureGroup("Компромиссы (\(candidate.compromises.count))", isExpanded: $showCompromises) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(candidate.compromises.enumerated()), id: \.offset) { _, text in
                                Text("• \(text)").frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 110)
                }
                .font(.footnote)
            }
        }
        .padding()
    }

    private func table(_ candidate: ScheduleCandidate, _ context: SolverContext) -> some View {
        let info = context.monthInfo
        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text("Сотрудник\nФакт / Норма ч.")
                        .font(.caption2.bold())
                        .frame(width: nameWidth, height: cellSize, alignment: .leading)
                    ForEach(context.employees) { nameCell($0, candidate) }
                    Text("Итого на смене")
                        .font(.caption.bold())
                        .frame(width: nameWidth, height: cellSize, alignment: .leading)
                }
                .padding(.leading, 8)
                .background(Color(.secondarySystemBackground))
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(info.days, id: \.self) { day in
                                VStack(spacing: 1) {
                                    Text("\(day)").font(.caption.bold())
                                    Text(info.weekdaySymbol(day)).font(.caption2)
                                }
                                .foregroundStyle(info.isWeekend(day) ? Color.red : Color.primary)
                                .frame(width: cellSize, height: cellSize)
                            }
                        }
                        ForEach(context.employees) { employee in
                            HStack(spacing: 0) {
                                ForEach(info.days, id: \.self) { cell(employee, $0, candidate) }
                            }
                        }
                        HStack(spacing: 0) {
                            ForEach(info.days, id: \.self) { day in
                                let count = candidate.staffCount(on: day)
                                Text("\(count)")
                                    .font(.callout.bold())
                                    .frame(width: cellSize - 4, height: cellSize - 4)
                                    .background((count < context.minStaffPerDay ? Color.red : Color.green).opacity(0.2),
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                    .padding(.trailing, 8)
                }
            }
        }
    }

    private func nameCell(_ employee: Employee, _ candidate: ScheduleCandidate) -> some View {
        let deviation = candidate.hoursDeviation(of: employee)
        return VStack(alignment: .leading, spacing: 3) {
            Text(employee.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("\(candidate.workedHours(of: employee.id).hoursText) / \(employee.targetMonthlyHours.hoursText) ч")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((abs(deviation) < 0.5 ? Color.green : .orange).opacity(0.25), in: Capsule())
                .contentTransition(.numericText())
        }
        .frame(width: nameWidth, height: cellSize, alignment: .leading)
    }

    private func cell(_ employee: Employee, _ day: Int, _ candidate: ScheduleCandidate) -> some View {
        let assignment = candidate.assignment(employee.id, day)
        let status = assignment?.status ?? .off
        return Button {
            editing = CellRef(employeeID: employee.id, day: day)
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 6).fill(status.color.opacity(status.isWorking ? 0.85 : 0.22))
                VStack(spacing: 0) {
                    Text(status.isWorking ? (assignment?.hours ?? 0).hoursText : status.shortLabel)
                        .font(.caption.bold())
                    if status.isWorking {
                        Text(status.shortLabel).font(.system(size: 8))
                    }
                }
                .foregroundStyle(status.isWorking ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if assignment?.isLocked == true {
                    Image(systemName: "lock.fill").font(.system(size: 8)).padding(3)
                        .foregroundStyle(status.isWorking ? Color.white : Color.primary)
                }
            }
            .padding(2)
            .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
    }

    private func share() {
        guard let candidate = store.current, let context = store.generatedContext,
              let image = ScheduleExportService.renderPNGImage(candidate: candidate, context: context) else { return }
        shareItem = ShareImage(image: image)
    }

    private func printSchedule() {
        guard let candidate = store.current, let context = store.generatedContext,
              let image = ScheduleExportService.renderImage(candidate: candidate, context: context) else { return }
        ScheduleExportService.print(image, jobName: "График смен — \(context.monthInfo.title)")
    }
}

struct CellEditorView: View {
    @Bindable var store: ScheduleStore
    let ref: CellRef
    @Environment(\.dismiss) private var dismiss

    private let editableStatuses: [ShiftStatus] = [.work, .off, .vacation, .mandatory]

    var body: some View {
        NavigationStack {
            Form {
                if let a = store.current?.assignment(ref.employeeID, ref.day),
                   let employee = store.generatedContext?.employees.first(where: { $0.id == ref.employeeID }) {
                    Section("Статус") {
                        Picker("Статус", selection: Binding(
                            get: { a.status == .desiredOff ? .off : a.status },
                            set: { apply($0, $0.isWorking ? (a.status.isWorking ? a.hours : employee.defaultShiftHours) : 0) }
                        )) {
                            ForEach(editableStatuses) { Label($0.title, systemImage: $0.icon).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    Section("Часы за смену") {
                        Stepper("\(a.hours.hoursText) ч", value: Binding(get: { a.hours }, set: { apply(a.status, $0) }),
                                in: 0.5...24, step: 0.5)
                            .disabled(!a.status.isWorking)
                    }
                    Section {
                        Toggle("Зафиксировать ячейку", systemImage: a.isLocked ? "lock.fill" : "lock.open", isOn: Binding(
                            get: { a.isLocked },
                            set: { locked in
                                withAnimation(.snappy) { store.setLock(employeeID: ref.employeeID, day: ref.day, locked: locked) }
                            }))
                    } footer: {
                        Text("Изменённая ячейка фиксируется автоматически, остальной график подстраивается под неё.")
                    }
                    Section("Итог сотрудника") {
                        LabeledContent("Факт / Норма", value: "\(store.current?.workedHours(of: employee.id).hoursText ?? "0") / \(employee.targetMonthlyHours.hoursText) ч")
                        LabeledContent("На смене в этот день", value: "\(store.current?.staffCount(on: ref.day) ?? 0) чел.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Готово") { dismiss() } }
        }
    }

    private var title: String {
        let name = store.generatedContext?.employees.first { $0.id == ref.employeeID }?.name ?? ""
        let date = store.generatedContext?.monthInfo.dayTitle(ref.day) ?? "\(ref.day)"
        return "\(name), \(date)"
    }

    private func apply(_ status: ShiftStatus, _ hours: Double) {
        withAnimation(.snappy) {
            store.applyEdit(employeeID: ref.employeeID, day: ref.day, status: status, hours: hours)
        }
    }
}
