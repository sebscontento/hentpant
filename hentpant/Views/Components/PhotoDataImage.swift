//
//  PhotoDataImage.swift
//  hentpant
//

import SwiftUI
import UIKit

struct PhotoDataImage: View {
    let data: Data
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "photo")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
