//
//  LibraryFileDetailView.swift
//  MyLifeDB
//
//  File detail screen for the Library tab.
//  Thin wrapper around the shared FileViewerView.
//

import SwiftUI

struct LibraryFileDetailView: View {

    let filePath: String
    let fileName: String

    var body: some View {
        FileViewerView(filePath: filePath, fileName: fileName)
    }
}
