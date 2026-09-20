import SwiftUI

/// Traced from the supplied feather SVG; the inner shaft is a second subpath, so this must be
/// filled with `FillStyle(eoFill: true)` or the cut closes up.
struct QuillMark: Shape {
    static let viewBox = CGRect(x: 1049, y: 344, width: 1159, height: 2037)

    func path(in rect: CGRect) -> Path {
        let vb = Self.viewBox
        let s = min(rect.width / vb.width, rect.height / vb.height)
        let tx = rect.minX + (rect.width - vb.width * s) / 2 - vb.minX * s
        let ty = rect.minY + (rect.height - vb.height * s) / 2 - vb.minY * s
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s + tx, y: y * s + ty) }

        var p = Path()
        p.move(to: q(1069.390625, 2360.898438))
        p.addLine(to: q(1081.878906, 2348.089844))
        p.addCurve(to: q(1177.488281, 2269.667969), control1: q(1116.769531, 2310.5625), control2: q(1148.640625, 2284.417969))
        p.addLine(to: q(1235.050781, 2069.019531))
        p.addCurve(to: q(1255.53125, 2016.90625), control1: q(1244.398438, 2038.492188), control2: q(1251.230469, 2021.121094))
        p.addCurve(to: q(1541.148438, 1952.640625), control1: q(1396.730469, 2004.394531), control2: q(1491.929688, 1982.972656))
        p.addCurve(to: q(1710.300781, 1784.191406), control1: q(1595.058594, 1928.25), control2: q(1651.441406, 1872.101562))
        p.addCurve(to: q(1839.269531, 1568.421875), control1: q(1780.28125, 1673.789062), control2: q(1823.269531, 1601.871094))
        p.addCurve(to: q(1916.039062, 1376.980469), control1: q(1857.851562, 1532.398438), control2: q(1883.441406, 1468.589844))
        p.addCurve(to: q(1554.789062, 1535.480469), control1: q(1786.410156, 1479.71875), control2: q(1665.988281, 1532.550781))
        p.addCurve(to: q(1835.789062, 1412.25), control1: q(1695.320312, 1502.441406), control2: q(1788.988281, 1461.371094))
        p.addCurve(to: q(1996.269531, 1135.539062), control1: q(1901.601562, 1361.28125), control2: q(1955.101562, 1269.039062))
        p.addLine(to: q(1813.160156, 1271.660156))
        p.addCurve(to: q(1602.671875, 1383.921875), control1: q(1792.859375, 1285.710938), control2: q(1722.691406, 1323.128906))
        p.addCurve(to: q(2072.769531, 848.140625), control1: q(1848.46875, 1264.671875), control2: q(2005.179688, 1086.078125))
        p.addCurve(to: q(2084.859375, 794.78125), control1: q(2076.988281, 830.621094), control2: q(2081.019531, 812.839844))
        p.addCurve(to: q(1737.488281, 1090.648438), control1: q(1994.71875, 907.589844), control2: q(1878.929688, 1006.210938))
        p.addCurve(to: q(2009.589844, 832.890625), control1: q(1863.179688, 1002.480469), control2: q(1953.878906, 916.570312))
        p.addCurve(to: q(2068.359375, 715.160156), control1: q(2025.808594, 809.679688), control2: q(2045.398438, 770.429688))
        p.addCurve(to: q(2144.058594, 463.960938), control1: q(2082.960938, 681.828125), control2: q(2108.191406, 598.101562))
        p.addCurve(to: q(2188.011719, 364.0), control1: q(2153.941406, 435.0), control2: q(2168.589844, 401.679688))
        p.addCurve(to: q(1816.898438, 625.121094), control1: q(2005.128906, 446.929688), control2: q(1881.429688, 533.960938))
        p.addCurve(to: q(1699.351562, 841.371094), control1: q(1765.339844, 694.25), control2: q(1726.160156, 766.339844))
        p.addCurve(to: q(1666.660156, 1030.289062), control1: q(1677.710938, 904.578125), control2: q(1666.808594, 967.558594))
        p.addCurve(to: q(1728.0, 750.070312), control1: q(1663.980469, 937.011719), control2: q(1684.421875, 843.609375))
        p.addCurve(to: q(1556.878906, 914.820312), control1: q(1657.730469, 804.410156), control2: q(1600.691406, 859.320312))
        p.addCurve(to: q(1482.921875, 1064.980469), control1: q(1520.261719, 959.050781), control2: q(1495.609375, 1009.101562))
        p.addCurve(to: q(1483.949219, 1284.480469), control1: q(1472.128906, 1105.710938), control2: q(1472.480469, 1178.871094))
        p.addCurve(to: q(1471.46875, 1100.140625), control1: q(1473.660156, 1199.828125), control2: q(1469.5, 1138.378906))
        p.addCurve(to: q(1495.96875, 936.980469), control1: q(1472.171875, 1061.160156), control2: q(1480.339844, 1006.78125))
        p.addCurve(to: q(1417.328125, 1100.339844), control1: q(1452.191406, 1000.160156), control2: q(1425.980469, 1054.621094))
        p.addCurve(to: q(1407.550781, 1337.140625), control1: q(1406.328125, 1143.539062), control2: q(1403.070312, 1222.480469))
        p.addCurve(to: q(1394.851562, 1145.21875), control1: q(1397.640625, 1244.101562), control2: q(1393.410156, 1180.121094))
        p.addCurve(to: q(1415.371094, 1013.710938), control1: q(1395.148438, 1108.25), control2: q(1401.988281, 1064.410156))
        p.addCurve(to: q(1296.589844, 1269.210938), control1: q(1337.488281, 1145.910156), control2: q(1297.898438, 1231.070312))
        p.addCurve(to: q(1341.320312, 1507.699219), control1: q(1288.609375, 1308.550781), control2: q(1303.519531, 1388.039062))
        p.addCurve(to: q(1286.679688, 1331.410156), control1: q(1310.410156, 1426.789062), control2: q(1292.199219, 1368.019531))
        p.addCurve(to: q(1283.660156, 1175.078125), control1: q(1279.390625, 1294.109375), control2: q(1278.378906, 1242.0))
        p.addLine(to: q(1207.820312, 1308.230469))
        p.addCurve(to: q(1167.101562, 1385.789062), control1: q(1186.859375, 1346.308594), control2: q(1173.28125, 1372.160156))
        p.addCurve(to: q(1125.039062, 1503.671875), control1: q(1152.171875, 1415.308594), control2: q(1138.140625, 1454.601562))
        p.addCurve(to: q(1117.449219, 1745.761719), control1: q(1104.96875, 1583.390625), control2: q(1102.441406, 1664.089844))
        p.addCurve(to: q(1214.839844, 1977.878906), control1: q(1131.230469, 1811.929688), control2: q(1163.691406, 1889.300781))
        p.addLine(to: q(1069.390625, 2360.898438))
        p.move(to: q(1204.539062, 2004.136719))
        p.addLine(to: q(1202.808594, 2003.148438))
        p.addCurve(to: q(1214.128906, 1930.449219), control1: q(1189.199219, 1999.59375), control2: q(1192.980469, 1975.363281))
        p.addLine(to: q(1390.019531, 1548.011719))
        p.addCurve(to: q(1474.589844, 1390.269531), control1: q(1420.449219, 1484.949219), control2: q(1448.640625, 1432.371094))
        p.addCurve(to: q(1701.929688, 1055.488281), control1: q(1512.71875, 1325.558594), control2: q(1588.5, 1213.960938))
        p.addLine(to: q(2008.109375, 661.890625))
        p.addCurve(to: q(1540.109375, 1315.019531), control1: q(1755.609375, 993.328125), control2: q(1599.609375, 1211.039062))
        p.addCurve(to: q(1432.828125, 1510.910156), control1: q(1514.769531, 1355.371094), control2: q(1479.011719, 1420.660156))
        p.addLine(to: q(1204.539062, 2004.136719))
        return p
    }
}

extension QuillMark {
    /// Sized taller than a square symbol would be: the feather is narrow, so equal height reads lighter.
    static var emptyStateIcon: some View { view(.quillMark, size: 80) }

    static func view(_ color: Color, size: CGFloat) -> some View {
        QuillMark()
            .fill(color, style: FillStyle(eoFill: true))
            .frame(width: size * (viewBox.width / viewBox.height), height: size)
    }
}
