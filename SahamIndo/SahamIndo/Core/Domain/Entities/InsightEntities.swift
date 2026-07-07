//
//  InsightEntities.swift
//  SahamIndo
//
//  Created by Surya on 17/06/26.
//

import Foundation
// MARK: - InsightChip (View-model DTO, no SwiftUI import needed)

struct InsightChip: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let text: String

    static func == (lhs: InsightChip, rhs: InsightChip) -> Bool {
        lhs.label == rhs.label && lhs.text == rhs.text
    }
}
