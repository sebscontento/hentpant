//
//  StaffRole.swift
//  hentpant
//

import Foundation

/// Elevated roles (normal users have `.user`). Admins are created in the backend in production.
enum StaffRole: String, Codable, CaseIterable {
    case user
    case moderator
    case admin

    var isModeratorOrAbove: Bool {
        self == .moderator || self == .admin
    }
}
