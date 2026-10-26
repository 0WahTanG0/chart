import SwiftUI

struct SetupView: View {
    @Bindable var store: ScheduleStore
    @State private var showSchedule = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Период") {
                    Picker("Месяц", selection: $store.month) {
                        ForEach(1...12, id: \.self) { Text(MonthInfo.monthNames[$0 - 1]).tag($0) }
                    }
                    Stepper("Год: \(String(store.year))", value: $store.year, in: 2020...2100)
                }
                Section("Правила") {
                    Stepper("Минимум на смене: \(store.minStaffPerDay) чел.", value: $store.minStaffPerDay, in: 1...20)
                    Stepper("Макс. смен подряд: \(store.maxConsecutiveShifts)", value: $store.maxConsecutiveShifts, in: 1...7)
                }
                Section {
                    ForEach($store.employees) { $employee in
                        NavigationLink {
                            EmployeeEditorView(employee: $employee, monthInfo: store.monthInfo)
                        } label: {
                            EmployeeRow(employee: employee)
                        }
                    }
                    .onDelete { store.employees.remove(atOffsets: $0) }
                    Button("Добавить сотрудника", systemImage: "person.badge.plus") {
                        store.employees.append(Employee(name: "Сотрудник \(store.employees.count + 1)",
                                                        defaultShiftHours: 12, targetMonthlyHours: 144))
                    }
                    Button("Заполнить тестовыми", systemImage: "wand.and.stars") {
                        store.employees = Employee.samples
                    }
                } header: {
                    Text("Сотрудники (\(store.employees.count))")
                }
                Section {
                    Button {
                        store.generate()
                        showSchedule = true
                    } label: {
                        Label("Сформировать график", systemImage: "calendar.badge.clock")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.employees.isEmpty)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("График смен")
            .toolbar { EditButton() }
            .navigationDestination(isPresented: $showSchedule) { ScheduleGridView(store: store) }
        }
    }
}

private struct EmployeeRow: View {
    let employee: Employee

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(employee.name.isEmpty ? "Без имени" : employee.name).font(.headline)
            Text("Смена \(employee.defaultShiftHours.hoursText) ч · норма \(employee.targetMonthlyHours.hoursText) ч")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                badge(employee.vacationDays.count, .vacation)
                badge(employee.desiredOffDays.count, .desiredOff)
                badge(employee.mandatoryShiftDays.count, .mandatory)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func badge(_ count: Int, _ status: ShiftStatus) -> some View {
        if count > 0 {
            Label("\(count)", systemImage: status.icon)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(status.color.opacity(0.2), in: Capsule())
                .foregroundStyle(status.color)
        }
    }
}

private enum DayPickMode: String, CaseIterable, Identifiable {
    case vacation = "Отпуск"
    case desiredOff = "Выходной"
    case mandatory = "Обяз. смена"

    var id: Self { self }

    var status: ShiftStatus {
        switch self {
        case .vacation: .vacation
        case .desiredOff: .desiredOff
        case .mandatory: .mandatory
        }
    }
}

struct EmployeeEditorView: View {
    @Binding var employee: Employee
    let monthInfo: MonthInfo
    @State private var mode: DayPickMode = .vacation

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        Form {
            Section("Сотрудник") {
                TextField("Имя", text: $employee.name)
                Stepper("Смена: \(employee.defaultShiftHours.hoursText) ч", value: $employee.defaultShiftHours, in: 1...24, step: 1)
                Stepper("Норма: \(employee.targetMonthlyHours.hoursText) ч/мес", value: $employee.targetMonthlyHours, in: 0...320, step: 4)
            }
            Section {
                Picker("Режим", selection: $mode) {
                    ForEach(DayPickMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(MonthInfo.weekdaySymbols, id: \.self) { symbol in
                        Text(symbol).font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                    ForEach(0..<monthInfo.leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 38) }
                    ForEach(monthInfo.days, id: \.self) { day in dayCell(day) }
                }
                .padding(.vertical, 4)
                HStack(spacing: 12) {
                    ForEach(DayPickMode.allCases) { item in
                        Label(item.rawValue, systemImage: "circle.fill")
                            .foregroundStyle(item.status.color)
                    }
                }
                .font(.caption2)
                .labelStyle(.titleAndIcon)
            } header: {
                Text("Календарь — \(monthInfo.title)")
            } footer: {
                Text("Выберите режим и нажимайте на даты. Повторное нажатие снимает отметку.")
            }
            Section {
                Button("Очистить все отметки", role: .destructive) {
                    employee.vacationDays.removeAll()
                    employee.desiredOffDays.removeAll()
                    employee.mandatoryShiftDays.removeAll()
                }
            }
        }
        .navigationTitle(employee.name.isEmpty ? "Сотрудник" : employee.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func status(of day: Int) -> ShiftStatus? {
        if employee.vacationDays.contains(day) { return .vacation }
        if employee.desiredOffDays.contains(day) { return .desiredOff }
        if employee.mandatoryShiftDays.contains(day) { return .mandatory }
        return nil
    }

    private func dayCell(_ day: Int) -> some View {
        let status = status(of: day)
        return Button {
            withAnimation(.snappy) { toggle(day) }
        } label: {
            Text("\(day)")
                .font(.callout.weight(status == nil ? .regular : .bold))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(status?.color ?? Color.secondary.opacity(monthInfo.isWeekend(day) ? 0.18 : 0.08)))
                .foregroundStyle(status != nil ? Color.white : monthInfo.isWeekend(day) ? Color.red : Color.primary)
        }
        .buttonStyle(.borderless)
    }

    private func toggle(_ day: Int) {
        let wasSelected = status(of: day) == mode.status
        employee.vacationDays.remove(day)
        employee.desiredOffDays.remove(day)
        employee.mandatoryShiftDays.remove(day)
        guard !wasSelected else { return }
        switch mode {
        case .vacation: employee.vacationDays.insert(day)
        case .desiredOff: employee.desiredOffDays.insert(day)
        case .mandatory: employee.mandatoryShiftDays.insert(day)
        }
    }
}
