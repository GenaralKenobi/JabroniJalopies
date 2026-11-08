import Charts
import SwiftUI

/// Bar chart of service spending per month over the last year.
struct CostChartView: View {
    let monthlyTotals: [MonthlyCost]

    var body: some View {
        Chart(monthlyTotals) { item in
            BarMark(
                x: .value("Month", item.month, unit: .month),
                y: .value("Cost", item.total)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: Formatting.currencyCode).precision(.fractionLength(0)))
                    }
                }
            }
        }
        .accessibilityLabel("Monthly service spending for the last 12 months")
    }
}
