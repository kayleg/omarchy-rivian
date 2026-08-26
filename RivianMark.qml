import QtQuick
import QtQuick.Shapes
import qs.Commons

// Rivian's compass: two opposing chevrons north and south, two arrows east and
// west, around a diamond. The badge on the car, and what an owner recognises.
//
// It is a demanding mark at bar size. Six alternating bands of ink and gap sit
// across the width, and a 13px icon has about two pixels for each, so the
// arrows inside blur into a grey diamond. Rendering it heavier does not help —
// weight closes the gaps and makes it more of a blob, not less. What survives
// is the silhouette, and that is the part doing the work: nothing else in a
// bar is a diamond, so it reads as this car from across the room even when the
// compass inside it does not resolve.
//
// The mark is Rivian's trademark, reproduced to identify a Rivian. Same footing
// as the Tesla widget drawing Tesla's T — see NOTICE.
Item {
  id: root

  property real iconSize: Style.bar.iconFont
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize

  // A diamond reads smaller than a solid glyph of the same box, because most
  // of its bounding box is empty corner. The nudge puts it back on visual par
  // with the lettered icons either side of it, and buys back a little of the
  // detail lost at bar size.
  readonly property real opticalScale: 1.12

  Item {
    anchors.centerIn: parent
    // The artwork's own coordinate system, so the path below is untouched.
    width: 965.1
    height: 930.9
    // Fit by the wider axis, so the mark never exceeds the icon box.
    scale: root.iconSize * root.opticalScale / width

    Shape {
      anchors.fill: parent
      antialiasing: true
      // Four thin arms and a lot of diagonal edge: without multisampling every
      // one of them crawls at bar size.
      layer.enabled: true
      layer.samples: 4
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: root.color
        strokeWidth: 0
        fillRule: ShapePath.WindingFill

        // The source viewBox starts at x = -2.6; shifting it here keeps the
        // path exactly as published rather than rewriting its every coordinate.
        PathSvg { path: "m2.6 0 m951.9 442.5c-27.1 0-90.1.1-127.9.1-13.4 0-17.3-2.4-25.7-11.4s-50.2-53.8-50.2-53.8c-53.1-57.2-182.6-183.6-229.9-223.5-17.8-15-37.9-14.5-38.2-14.5s-20.4-.5-38.2 14.5c-47.3 39.9-176.8 166.3-229.9 223.5 0 0-41.8 44.8-50.2 53.8s-12.3 11.4-25.7 11.4c-37.9 0-100.8-.1-127.9-.1-6.6 0-10.7-8-6.2-13.1 54.3-56 348.1-359 403.1-402.7 19.2-15.4 43.9-26.7 75-26.7 31 0 55.8 11.3 75 26.7 55 43.7 348.8 346.7 403.1 402.7 4.4 5.1.5 13.1-6.2 13.1zm-943.9 45.9c27.1 0 90.1-.1 127.9-.1 13.4 0 17.3 2.3 25.7 11.3s50.2 53.8 50.2 53.8c53.1 57.2 182.6 183.6 229.9 223.5 17.8 15 37.9 14.5 38.2 14.5s20.4.5 38.2-14.5c47.3-39.8 176.8-166.2 229.9-223.5 0 0 41.8-44.8 50.2-53.8s12.3-11.3 25.7-11.3c37.9 0 100.8.1 127.9.1 6.6 0 10.7 8 6.2 13.1-54.3 56-348 358.9-403.1 402.7-19.1 15.4-43.9 26.7-75 26.7-31 0-55.7-11.3-74.9-26.7-55.1-43.8-348.8-346.7-403.1-402.7-4.5-5.1-.5-13.1 6.1-13.1zm448.8 103.6v125.5c0 5.9-5.7 8.5-10.5 4.3-54-50-174.3-169.2-214.7-215.4-19.2-20.5-17.5-41.2-17.5-41.2s-1.8-20.9 17.5-41.3c40.4-46.2 160.7-165.4 214.7-215.4 4.6-4.3 10.5-1.1 10.5 3.9v125.8c0 11.4-2.4 17.2-12.3 26.4-24.2 22.2-66.9 63.5-82.8 82.1-7.2 8.2-6.7 18.4-6.7 18.4s-.5 10.3 6.7 18.5c15.9 18.5 58.6 59.9 82.8 82 9.9 9.2 12.3 15 12.3 26.4zm58.7-26.3c24.2-22.1 66.9-63.5 82.8-82 7.2-8.2 6.7-18.5 6.7-18.5s.5-10.2-6.7-18.4c-15.9-18.6-58.6-59.9-82.8-82.1-9.9-9.2-12.3-15-12.3-26.4v-125.4c0-5.9 5.7-8.6 10.5-4.4 54 50 174.3 169.2 214.6 215.4 19.3 20.5 17.5 41.3 17.5 41.3s1.8 20.8-17.5 41.3c-40.3 46.2-160.6 165.4-214.6 215.4-4.8 4.2-10.5 1.6-10.5-4.4v-125.4c.1-11.4 2.4-17.2 12.3-26.4z" }
      }
    }
  }
}
