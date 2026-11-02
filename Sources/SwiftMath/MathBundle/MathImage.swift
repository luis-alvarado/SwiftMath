//
//  MathImage.swift
//  
//
//  Created by Peter Tang on 15/9/2023.
//

import Foundation

#if os(iOS) || os(visionOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

public struct MathImage {
    public var font: MathFont = .latinModernFont
    public var fontSize: CGFloat
    public var textColor: MTColor

    public var labelMode: MTMathUILabelMode
    public var textAlignment: MTTextAlignment

    public var contentInsets: MTEdgeInsets = MTEdgeInsetsZero
    
    public let latex: String
    
    private(set) var intrinsicContentSize = CGSize.zero

    public init(latex: String, fontSize: CGFloat, textColor: MTColor, labelMode: MTMathUILabelMode = .display, textAlignment: MTTextAlignment = .center) {
        self.latex = latex
        self.fontSize = fontSize
        self.textColor = textColor
        self.labelMode = labelMode
        self.textAlignment = textAlignment
    }
}
extension MathImage {
    public var currentStyle: MTLineStyle {
        switch labelMode {
            case .display: return .display
            case .text: return .text
        }
    }
    private func intrinsicContentSize(_ displayList: MTMathListDisplay) -> CGSize {
        CGSize(width: displayList.width + contentInsets.left + contentInsets.right,
               height: displayList.ascent + displayList.descent + contentInsets.top + contentInsets.bottom)
    }
    public struct LayoutInfo {
        public var ascent: CGFloat = 0
        public var descent: CGFloat = 0
        /// Where each `\colorbox` is in the image, from its top left corner (y down)
        public var colorBoxes: [CGRect] = []

        public init(ascent: CGFloat, descent: CGFloat, colorBoxes: [CGRect] = []) {
            self.ascent = ascent
            self.descent = descent
            self.colorBoxes = colorBoxes
        }
    }
    public mutating func asImage() -> (NSError?, MTImage?, LayoutInfo?) {
        func layoutImage(size: CGSize, displayList: MTMathListDisplay) {
            var textX = CGFloat(0)
            switch self.textAlignment {
                case .left:   textX = contentInsets.left
                case .center: textX = (size.width - contentInsets.left - contentInsets.right - displayList.width) / 2 + contentInsets.left
                case .right:  textX = size.width - displayList.width - contentInsets.right
            }
            let availableHeight = size.height - contentInsets.bottom - contentInsets.top
            
            // center things vertically
            var height = displayList.ascent + displayList.descent
            if height < fontSize/2 {
                height = fontSize/2  // set height to half the font size
            }
            let textY = (availableHeight - height) / 2 + displayList.descent + contentInsets.bottom
            displayList.position = CGPoint(x: textX, y: textY)
        }
        var error: NSError?
        let mtfont: MTFont? = font.mtfont(size: fontSize)

        guard let mathList = MTMathListBuilder.build(fromString: latex, error: &error), error == nil,
              let displayList = MTTypesetter.createLineForMathList(mathList, font: mtfont, style: currentStyle) else {
            return (error, nil, nil)
        }

        intrinsicContentSize = intrinsicContentSize(displayList)
        displayList.textColor = textColor

        var size = intrinsicContentSize.regularized
        layoutImage(size: size, displayList: displayList)
        // Room for ink past the edges: a slanted letter's reaches past its advance (the P ending
        // X + P, an f starting a line), which the image would clip
        let ink = displayList.inkBounds(from: .zero)
        let left = max(0, ceil(-ink.minX)), right = max(0, ceil(ink.maxX - size.width))
        if left > 0 || right > 0 {
            size.width += left + right
            displayList.position.x += left
        }
        var boxes: [CGRect] = []
        displayList.colorBoxes(from: .zero, into: &boxes)
        let layout = LayoutInfo(ascent: displayList.ascent, descent: displayList.descent,
                                colorBoxes: boxes.map { CGRect(x: $0.minX, y: size.height - $0.maxY, width: $0.width, height: $0.height) })
        
        #if os(iOS) || os(visionOS)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { rendererContext in
                rendererContext.cgContext.saveGState()
                rendererContext.cgContext.concatenate(.flippedVertically(size.height))
                displayList.draw(rendererContext.cgContext)
                rendererContext.cgContext.restoreGState()
            }
            return (nil, image, layout)
        #endif
        #if os(macOS)
            let image = NSImage(size: size, flipped: false) { bounds in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.saveGState()
                displayList.draw(context)
                context.restoreGState()
                return true
            }
            return (nil, image, layout)
        #endif
    }
}
private extension CGAffineTransform {
    static func flippedVertically(_ height: CGFloat) -> CGAffineTransform {
        var transform = CGAffineTransform(scaleX: 1, y: -1)
        transform = transform.translatedBy(x: 0, y: -height)
        return transform
    }
}
extension CGSize {
    fileprivate var regularized: CGSize {
        CGSize(width: ceil(width), height: ceil(height))
    }
}
