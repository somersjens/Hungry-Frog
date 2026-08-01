//
//  EmphasizedText.swift
//  Jumping Fox
//
//  Converts the pipe markers used by localized intro copy into one attributed
//  string. Keeping the result as a single text value lets SwiftUI wrap a bold
//  span across lines without treating each styled part as a separate view.
//

import Foundation

func emphasizedAttributedString(_ copy: String) -> AttributedString {
    var result = AttributedString()

    for (index, part) in copy.components(separatedBy: "|").enumerated() {
        var segment = AttributedString(part)
        if !index.isMultiple(of: 2) {
            segment.inlinePresentationIntent = .stronglyEmphasized
        }
        result.append(segment)
    }

    return result
}
