import SwiftUI
import UIKit

struct PrintableScheduleView: View {
    let candidate: ScheduleCandidate
    let context: SolverContext

    private let nameWidth: CGFloat = 160
    private let cellWidth: CGFloat = 36
    private let rowHeight: CGFloat = 34
    private let totalWidth: CGFloat = 96
    private let line = Color.black.opacity(0.35)

    var body: some View {
        let info = context.monthInfo
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("График смен — \(info.title)").font(.system(size: 26, weight: .bold))
                Spacer()
                Text(candidate.title).font(.system(size: 15, weight: .medium)).foregroundStyle(.gray)
            }
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    box(width: nameWidth, alignment: .leading) { Text("Сотрудник").bold() }
                    ForEach(info.days, id: \.self) { day in
                        box(width: cellWidth, fill: info.isWeekend(day) ? Color.red.opacity(0.08) : .clear) {
                            VStack(spacing: 0) {
                                Text("\(day)").bold()
                                Text(info.weekdaySymbol(day)).font(.system(size: 9))
                            }
                            .foregroundStyle(info.isWeekend(day) ? Color.red : Color.black)
                        }
                    }
                    box(width: totalWidth) { Text("Факт / Норма").bold() }
                }
                ForEach(context.employees) { employee in
                    HStack(spacing: 0) {
                        box(width: nameWidth, alignment: .leading) { Text(employee.name + (employee.isDirector ? " (дир.)" : "")).lineLimit(1) }
                        ForEach(info.days, id: \.self) { day in
                            let a = candidate.assignment(employee.id, day)
                            let status = a?.status ?? .off
                            box(width: cellWidth, fill: status.color.opacity(status.isWorking ? 0.8 : 0.18)) {
                                Text(status.isWorking ? (a?.hours ?? 0).hoursText : status.shortLabel)
                                    .bold(status.isWorking)
                                    .foregroundStyle(status.isWorking ? Color.white : Color.black)
                            }
                        }
                        let deviation = candidate.hoursDeviation(of: employee)
                        box(width: totalWidth, fill: (abs(deviation) < 0.5 ? Color.green : .orange).opacity(0.2)) {
                            Text("\(candidate.workedHours(of: employee.id).hoursText) / \(employee.targetMonthlyHours.hoursText)").bold()
                        }
                    }
                }
                HStack(spacing: 0) {
                    box(width: nameWidth, alignment: .leading) { Text("Итого на смене").bold() }
                    ForEach(info.days, id: \.self) { day in
                        let count = candidate.staffCount(on: day)
                        box(width: cellWidth, fill: count < context.minStaffPerDay ? Color.red.opacity(0.2) : .clear) {
                            Text("\(count)" + (candidate.hasExtraDirector(on: day) ? "+Д" : "")).bold()
                        }
                    }
                    box(width: totalWidth) {
                        Text("\(context.employees.reduce(0) { $0 + candidate.workedHours(of: $1.id) }.hoursText) ч").bold()
                    }
                }
            }
            .overlay(Rectangle().stroke(Color.black.opacity(0.6), lineWidth: 1))
            HStack(spacing: 18) {
                ForEach(ShiftStatus.allCases) { status in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(status.color.opacity(status.isWorking ? 0.8 : 0.3))
                            .frame(width: 16, height: 16)
                        Text("\(status.shortLabel) — \(status.title)")
                    }
                }
                Spacer()
                Text("Минимум на смене: \(context.minStaffPerDay) чел.")
            }
            .font(.system(size: 12))
            if !candidate.compromises.isEmpty {
                Text("Компромиссы: " + candidate.compromises.joined(separator: "; "))
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.black)
        .padding(28)
        .frame(width: nameWidth + cellWidth * CGFloat(info.daysCount) + totalWidth + 56)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func box<Content: View>(width: CGFloat, alignment: Alignment = .center, fill: Color = .clear,
                                    @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, alignment == .leading ? 8 : 0)
            .frame(width: width, height: rowHeight, alignment: alignment)
            .background(fill)
            .overlay(Rectangle().stroke(line, lineWidth: 0.5))
    }
}

@MainActor
enum ScheduleExportService {
    static func renderImage(candidate: ScheduleCandidate, context: SolverContext) -> UIImage? {
        let renderer = ImageRenderer(content: PrintableScheduleView(candidate: candidate, context: context))
        renderer.scale = 3.0
        renderer.isOpaque = true
        return renderer.uiImage
    }

    static func renderPNGImage(candidate: ScheduleCandidate, context: SolverContext) -> UIImage? {
        guard let image = renderImage(candidate: candidate, context: context) else { return nil }
        return image.pngData().flatMap { UIImage(data: $0, scale: image.scale) } ?? image
    }

    static func print(_ image: UIImage, jobName: String) {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.orientation = .landscape
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = image
        controller.present(animated: true)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
