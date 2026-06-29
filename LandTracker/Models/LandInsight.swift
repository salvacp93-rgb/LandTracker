import Foundation

// MARK: - Cost Category

enum CostCategory: String, CaseIterable {
    case irrigation
    case fertilizer
    case labor
    case maintenance
}

// MARK: - Suggestions

enum LandSuggestion {
    case negativeMargin(amount: Double)
    case dominantCost(CostCategory, share: Double)
    case planUnderachieved(variance: Double)
    case noHistoryData
}

// MARK: - Per-land insight

struct LandEconomicInsight {
    let netMarginRate: Double?
    let incomePerAcre: Double?
    let netMarginPerAcre: Double?
    let dominantCost: CostCategory?
    let dominantCostShare: Double?
    let actualIncomeCurrentYear: Double
    let currentYearMonthsRecorded: Int
    let yoyIncomeChange: Double?
    let suggestions: [LandSuggestion]

    init(land: Land) {
        let currentYear = Calendar.current.component(.year, from: Date())
        let previousYear = currentYear - 1

        netMarginRate = land.incomeAnnual > 0 ? land.annualNetMargin / land.incomeAnnual : nil
        incomePerAcre = land.sizeAcres > 0 ? land.incomeAnnual / land.sizeAcres : nil
        netMarginPerAcre = land.sizeAcres > 0 ? land.annualNetMargin / land.sizeAcres : nil

        let costs: [(CostCategory, Double)] = [
            (.irrigation, land.annualIrrigationCost),
            (.fertilizer, land.annualFertilizerCost),
            (.labor, land.annualLaborCost),
            (.maintenance, land.annualMaintenanceCost)
        ]
        let totalExpenses = land.annualTotalExpenses
        if totalExpenses > 0, let top = costs.max(by: { $0.1 < $1.1 }) {
            dominantCost = top.0
            dominantCostShare = top.1 / totalExpenses
        } else {
            dominantCost = nil
            dominantCostShare = nil
        }

        let currentYearEntries = land.historyEntries.filter { $0.year == currentYear }
        let previousYearEntries = land.historyEntries.filter { $0.year == previousYear }

        actualIncomeCurrentYear = currentYearEntries.reduce(0) { $0 + $1.incomeAmount }
        currentYearMonthsRecorded = currentYearEntries.count

        let previousYearTotal = previousYearEntries.reduce(0) { $0 + $1.incomeAmount }
        if !currentYearEntries.isEmpty && previousYearTotal > 0 {
            yoyIncomeChange = (actualIncomeCurrentYear - previousYearTotal) / previousYearTotal
        } else {
            yoyIncomeChange = nil
        }

        var result: [LandSuggestion] = []

        if land.annualNetMargin < 0 {
            result.append(.negativeMargin(amount: land.annualNetMargin))
        }
        if let share = dominantCostShare, let category = dominantCost, share > 0.6 {
            result.append(.dominantCost(category, share: share))
        }
        if land.historyEntries.isEmpty {
            result.append(.noHistoryData)
        } else if currentYearMonthsRecorded >= 6 && land.incomeAnnual > 0 {
            let proratedPlan = land.incomeAnnual * Double(currentYearMonthsRecorded) / 12.0
            let variance = actualIncomeCurrentYear - proratedPlan
            if variance / proratedPlan < -0.2 {
                result.append(.planUnderachieved(variance: variance))
            }
        }

        suggestions = result
    }
}

// MARK: - Portfolio insight

struct PortfolioInsight {
    let totalIncome: Double
    let totalExpenses: Double
    let totalNetMargin: Double
    let portfolioMarginRate: Double?
    let totalAreaAcres: Double
    let bestLand: Land?
    let worstLand: Land?

    init(lands: [Land]) {
        totalIncome = lands.reduce(0) { $0 + $1.incomeAnnual }
        totalExpenses = lands.reduce(0) { $0 + $1.annualTotalExpenses }
        totalNetMargin = lands.reduce(0) { $0 + $1.annualNetMargin }
        portfolioMarginRate = totalIncome > 0 ? totalNetMargin / totalIncome : nil
        totalAreaAcres = lands.reduce(0) { $0 + $1.sizeAcres }

        let ranked = lands
            .filter { $0.incomeAnnual > 0 }
            .sorted { $0.annualNetMargin / $0.incomeAnnual > $1.annualNetMargin / $1.incomeAnnual }

        bestLand = ranked.first
        worstLand = ranked.count > 1 ? ranked.last : nil
    }
}
