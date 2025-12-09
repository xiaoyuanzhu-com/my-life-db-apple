//
//  Item.swift
//  MyLifeDB
//
//  Created by Li Zhao on 2025/12/9.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
