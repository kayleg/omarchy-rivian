import QtQuick
import QtQuick.Shapes
import qs.Commons

// Rivian's compass, the solid badge: a filled diamond notched east and west,
// around a diamond void, around the two arrows that meet in the middle.
//
// This is the heavier of the two drawings of the mark in circulation. The
// thin-outline one is prettier at poster size and turns to porridge in a bar;
// this one keeps a little more of itself, because what has to survive is the
// gap between the ring and the arrows rather than a hairline.
//
// It is still an ambitious mark at 13px — the arrows read as a divided blob
// rather than as arrows. The silhouette is what identifies it, and nothing
// else in a bar is a diamond.
//
// Rivian's trademark, reproduced to identify a Rivian, the same footing on
// which omarchy-tesla draws Tesla's T. See NOTICE.
Item {
  id: root

  property real iconSize: Style.bar.iconFont
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize

  // A diamond wastes most of its bounding box on empty corner, so at nominal
  // size it reads smaller than the lettered icons beside it. This puts it back
  // on visual par and buys back a little of the interior.
  readonly property real opticalScale: 1.12

  Item {
    anchors.centerIn: parent
    // The traced artwork's own box, so the path below needs no rewriting.
    width: 802
    height: 777
    // Fit by the wider axis; the mark never exceeds the icon box.
    scale: root.iconSize * root.opticalScale / width

    Shape {
      anchors.fill: parent
      antialiasing: true
      // Four arms, all diagonal edge. Without multisampling they crawl.
      layer.enabled: true
      layer.samples: 4
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: root.color
        strokeWidth: 0
        // The four subpaths do not overlap, so winding and even-odd agree;
        // this is the QML default and was checked against both.
        fillRule: ShapePath.WindingFill

        PathSvg { path: "M 379.60 1.60 c -23.90 5.30 -36.60 13.90 -76.10 51.40 -14.40 13.60 -160.00 159.20 -191.50 191.50 -60.10 61.60 -91.80 94.10 -104.40 107.30 -7.30 7.60 -7.80 8.50 -7.20 11.50 0.30 1.70 1.40 3.80 2.30 4.40 1.30 1.00 14.90 1.30 60.20 1.30 54.50 -0.00 58.90 -0.20 62.60 -1.90 4.00 -1.80 14.70 -12.60 47.60 -48.20 31.90 -34.50 138.60 -139.60 177.40 -174.50 23.10 -20.80 28.00 -24.10 40.20 -27.00 13.00 -3.10 28.10 0.40 39.70 9.00 26.20 19.60 148.60 139.10 210.00 205.10 16.40 17.60 31.40 33.10 33.30 34.50 l 3.60 2.50 60.20 0.30 60.30 0.30 2.10 -2.70 c 1.20 -1.50 2.10 -3.60 2.10 -4.70 0.00 -1.20 -5.20 -7.30 -13.30 -15.60 -7.30 -7.50 -29.40 -30.20 -49.20 -50.60 -126.40 -129.90 -236.40 -239.50 -268.00 -267.00 -16.90 -14.80 -26.50 -20.30 -44.50 -25.70 -9.00 -2.70 -37.40 -3.40 -47.40 -1.20 Z M 364.30 181.20 c -34.20 32.20 -130.20 128.00 -155.20 154.80 -19.40 20.80 -24.50 27.60 -27.80 37.30 -2.20 6.30 -2.50 8.40 -2.10 16.90 0.80 16.70 4.40 22.40 34.80 54.80 30.60 32.60 124.40 125.70 155.00 153.90 5.80 5.40 8.70 6.20 11.20 3.10 1.80 -2.20 1.90 -4.90 1.60 -58.90 -0.30 -52.30 -0.40 -56.90 -2.10 -60.80 -1.30 -2.90 -6.90 -8.90 -19.00 -20.40 -27.30 -25.70 -57.70 -56.90 -60.80 -62.40 -3.80 -6.50 -4.00 -15.50 -0.70 -22.40 2.30 -4.80 41.00 -44.40 65.50 -67.10 18.40 -17.00 16.70 -9.50 17.10 -76.90 0.20 -49.70 0.10 -56.60 -1.30 -58.70 -2.80 -4.30 -5.60 -3.10 -16.20 6.80 Z M 421.00 174.00 c -0.70 1.40 -1.00 19.90 -0.80 59.30 l 0.30 57.20 2.70 4.50 c 1.50 2.60 13.20 14.50 27.30 28.00 27.00 25.70 49.40 49.00 52.00 54.00 2.20 4.30 3.00 12.60 1.60 17.70 -0.70 2.50 -3.30 6.90 -6.20 10.30 -6.10 7.30 -30.20 31.50 -54.80 55.00 -10.00 9.60 -19.30 19.30 -20.40 21.50 -2.20 4.00 -2.20 4.50 -2.20 62.30 0.00 50.70 0.20 58.40 1.50 59.20 4.10 2.60 4.20 2.50 40.50 -32.40 31.40 -30.20 93.20 -92.00 116.70 -116.60 23.70 -24.80 34.60 -37.40 38.00 -43.70 7.50 -13.80 7.60 -30.80 0.10 -44.60 -5.80 -10.50 -32.50 -39.10 -95.70 -102.20 -23.70 -23.70 -54.50 -53.90 -68.50 -67.30 -20.80 -19.80 -25.90 -24.20 -28.20 -24.20 -1.80 -0.00 -3.20 0.70 -3.90 2.00 Z M 2.50 409.50 c -5.20 5.10 -7.00 2.80 41.90 53.00 166.70 171.20 271.50 275.20 296.00 293.70 34.70 26.10 80.60 27.60 115.90 3.60 15.80 -10.70 50.80 -44.10 138.20 -132.00 73.30 -73.70 96.40 -97.10 172.60 -175.30 30.10 -31.00 34.90 -36.20 34.90 -38.50 0.00 -1.10 -1.10 -3.20 -2.50 -4.60 l -2.50 -2.50 -59.20 0.30 c -52.90 0.30 -59.60 0.50 -62.30 2.00 -2.80 1.50 -10.30 8.80 -22.30 21.80 -2.80 3.00 -12.90 13.90 -22.40 24.10 -20.20 21.80 -107.00 108.70 -136.80 136.90 -23.10 21.90 -49.20 45.80 -59.20 54.30 -18.20 15.30 -36.80 17.80 -56.90 7.70 -18.00 -9.10 -148.20 -135.30 -222.40 -215.50 -22.30 -24.10 -27.70 -29.20 -32.00 -30.40 -2.70 -0.70 -23.30 -1.10 -61.30 -1.10 l -57.30 -0.00 -2.40 2.50 Z" }
      }
    }
  }
}
