import SwiftUI

/// The mark from `Brand/quill-logo.svg`, in that file's coordinates.
struct QuillMark: Shape {
    static let viewBox = CGRect(x: 72, y: 22, width: 106, height: 215)

    func path(in rect: CGRect) -> Path {
        let vb = Self.viewBox
        let s = min(rect.width / vb.width, rect.height / vb.height)
        let tx = rect.minX + (rect.width - vb.width * s) / 2 - vb.minX * s
        let ty = rect.minY + (rect.height - vb.height * s) / 2 - vb.minY * s
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s + tx, y: y * s + ty) }

        var feather = Path()
        feather.move(to: q(178.0, 22.0))
        feather.addCurve(to: q(147.0, 91.0), control1: q(174.0, 47.0), control2: q(163.0, 70.0))
        feather.addCurve(to: q(169.0, 68.0), control1: q(160.0, 84.0), control2: q(166.0, 75.0))
        feather.addCurve(to: q(135.0, 130.0), control1: q(168.0, 89.0), control2: q(154.0, 113.0))
        feather.addCurve(to: q(163.0, 104.0), control1: q(151.0, 123.0), control2: q(159.0, 111.0))
        feather.addCurve(to: q(120.0, 162.0), control1: q(157.0, 128.0), control2: q(142.0, 149.0))
        feather.addCurve(to: q(150.0, 138.0), control1: q(137.0, 154.0), control2: q(146.0, 145.0))
        feather.addCurve(to: q(92.0, 190.0), control1: q(140.0, 165.0), control2: q(120.0, 184.0))
        feather.addCurve(to: q(82.0, 137.0), control1: q(79.0, 173.0), control2: q(77.0, 157.0))
        feather.addCurve(to: q(88.0, 165.0), control1: q(81.0, 151.0), control2: q(84.0, 160.0))
        feather.addCurve(to: q(101.0, 106.0), control1: q(82.0, 141.0), control2: q(89.0, 122.0))
        feather.addCurve(to: q(97.0, 141.0), control1: q(96.0, 120.0), control2: q(94.0, 133.0))
        feather.addCurve(to: q(113.0, 90.0), control1: q(92.0, 121.0), control2: q(102.0, 100.0))
        feather.addCurve(to: q(106.0, 126.0), control1: q(105.0, 106.0), control2: q(104.0, 119.0))
        feather.addCurve(to: q(129.0, 74.0), control1: q(103.0, 104.0), control2: q(119.0, 86.0))
        feather.addCurve(to: q(119.0, 109.0), control1: q(119.0, 91.0), control2: q(118.0, 104.0))
        feather.addCurve(to: q(178.0, 22.0), control1: q(121.0, 79.0), control2: q(144.0, 40.0))
        feather.closeSubpath()
        feather.move(to: q(170.0, 37.0))
        feather.addCurve(to: q(91.0, 188.0), control1: q(144.0, 79.0), control2: q(111.0, 138.0))
        feather.addLine(to: q(94.0, 188.0))
        feather.addCurve(to: q(170.0, 37.0), control1: q(114.0, 138.0), control2: q(146.0, 78.0))
        feather.closeSubpath()

        var nib = Path()
        nib.move(to: q(92.0, 181.0))
        nib.addCurve(to: q(72.0, 237.0), control1: q(85.0, 200.0), control2: q(79.0, 218.0))
        nib.addLine(to: q(81.0, 230.0))
        nib.addCurve(to: q(97.0, 183.0), control1: q(85.0, 214.0), control2: q(91.0, 198.0))
        nib.closeSubpath()

        return feather.normalized(eoFill: true).union(nib)
    }
}

extension QuillMark {
    /// Sized taller than a square symbol would be: the feather is narrow, so equal height reads lighter.
    static var emptyStateIcon: some View { view(.quillMark, size: 100) }

    static func view(_ color: Color, size: CGFloat) -> some View {
        QuillMark()
            .fill(color)
            .frame(width: size * (viewBox.width / viewBox.height), height: size)
    }
}
