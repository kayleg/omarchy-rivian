import QtQuick
import qs.Commons

// The R1's face: two vertical stadium headlights with a light bar between
// them. Drawn rather than typed, for the same reason the Tesla widget draws
// its T — no Nerd Font ships a Rivian glyph, and a generic car icon in the bar
// would say "a car" when the whole point is that it says "your car".
//
// This is the vehicle's face rather than the company's wordmark, which is the
// better mark for the job on both counts: it is what an owner recognises from
// across a car park, and it is a shape rather than a trademark. Simple Icons
// has no Rivian path to borrow, so every number here is chosen rather than
// copied, on the same 24×24 grid the other marks use.
//
// Rectangles rather than a Shape: the whole mark is two stadiums and a bar,
// and rounded rectangles are exactly that with none of the curve arithmetic.
// They also stay crisp at bar sizes without multisampling.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize

  Item {
    anchors.centerIn: parent
    width: 24
    height: 24
    scale: root.iconSize / 24

    // The headlights carry the recognition, so they get the full height and
    // the bar is kept thin enough to read as a join rather than a third shape.
    Rectangle {
      x: 2.5; y: 5.5
      width: 4.6; height: 13
      radius: width / 2
      color: root.color
      antialiasing: true
    }

    Rectangle {
      x: 16.9; y: 5.5
      width: 4.6; height: 13
      radius: width / 2
      color: root.color
      antialiasing: true
    }

    // Slightly above centre, where it sits on the car: dead centre reads as a
    // minus sign between two pills, and a fraction high reads as a face.
    Rectangle {
      x: 7.1; y: 10.4
      width: 9.8; height: 2.6
      radius: height / 2
      color: root.color
      antialiasing: true
    }
  }
}
