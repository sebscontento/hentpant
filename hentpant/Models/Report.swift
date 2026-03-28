//
//  Report.swift
//  hentpant
//

import Foundation

enum ReportTarget: String, Codable {
    case listing
    case user
}

struct Report: Identifiable, Equatable {
    let id: UUID
    let target: ReportTarget
    let targetId: String
    let reporterId: String
    let reason: String
    let createdAt: Date
}
