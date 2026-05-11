import Foundation

#if os(macOS)
import AppKit
import SwiftUI

/// Wraps an `Issue` in an `NSHostingView` and hands it to `NSPrintOperation`
/// so the system print panel surfaces (#0063). The Save as PDF dropdown
/// in the panel uses `jobTitle` as the default filename — we set it to
/// `NNNN.pdf` so the export name lands at the issue id.
enum IssuePrintRunner {

    /// US Letter at 72 dpi. The print info itself negotiates the actual
    /// paper size; this is the SwiftUI hosting frame so layout pagination
    /// has a sensible default before the panel adjusts it.
    private static let pageSize = CGSize(width: 612, height: 792)

    @MainActor
    static func print(issue: Issue) {
        let hosting = NSHostingView(rootView: IssuePrintView(issue: issue))
        hosting.frame = NSRect(origin: .zero, size: pageSize)

        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        // Reasonable defaults that the user can override in the print panel.
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.verticalPagination = .automatic
        info.horizontalPagination = .fit

        let operation = NSPrintOperation(view: hosting, printInfo: info)
        // `jobTitle` doubles as the default filename in the Save as PDF
        // sheet, so the export lands at NNNN.pdf out of the box.
        operation.jobTitle = "\(issue.id).pdf"
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }
}

#endif
