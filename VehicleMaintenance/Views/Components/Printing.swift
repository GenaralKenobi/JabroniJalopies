import UIKit

/// Opens the system print screen for a PDF (which also offers saving or sharing it).
@MainActor
func printPDF(_ data: Data, jobName: String) {
    let info = UIPrintInfo(dictionary: nil)
    info.outputType = .general
    info.jobName = jobName
    let controller = UIPrintInteractionController.shared
    controller.printInfo = info
    controller.printingItem = data
    controller.present(animated: true)
}
