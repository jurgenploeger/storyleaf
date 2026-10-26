import SwiftUI

/// A physical-looking analog thumbstick: bevelled base, recessed well, a domed rubber cap
/// that tilts toward where you push, a leaning shaft, springy return and haptics.
/// Writes a -1...1 direction (y up) into `input` for the world scene.
struct JoystickView: View {
    let input: InputState

    @State private var offset: CGSize = .zero
    @State private var isPressed = false
    @State private var direction: Direction?

    private let radius: CGFloat = 62
    private let capRadius: CGFloat = 30
    /// How far the cap can travel from the centre.
    private var travel: CGFloat { radius - capRadius * 0.55 }

    var body: some View {
        ZStack {
            JoystickBase(radius: radius, isPressed: isPressed, direction: direction)
            JoystickShaft(offset: offset, width: capRadius * 0.8)
            JoystickCap(radius: capRadius, isPressed: isPressed, tilt: tilt)
                .offset(offset)
        }
        .frame(width: radius * 2, height: radius * 2)
        // Flatten first so the stick fades as one piece (no layers showing through each other).
        .compositingGroup()
        .opacity(isPressed ? 1 : 0.9)
        .contentShape(Circle().inset(by: -30))
        .gesture(drag)
        .sensoryFeedback(.impact(weight: .light), trigger: isPressed) { _, pressed in pressed && GameSettings.haptics }
        .sensoryFeedback(.selection, trigger: direction) { _, new in new != nil && GameSettings.haptics }
        .accessibilityLabel(L("Movement joystick"))
    }

    /// 0...1 plus the direction to lean, for the cap's 3D tilt.
    private var tilt: (amount: CGFloat, dx: CGFloat, dy: CGFloat) {
        let length = hypot(offset.width, offset.height)
        guard length > 0.5 else { return (0, 1, 0) }
        return (min(1, length / travel), offset.width / length, offset.height / length)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isPressed { isPressed = true }
                var next = CGSize(width: value.location.x - radius, height: value.location.y - radius)
                let length = hypot(next.width, next.height)
                if length > travel {
                    next = CGSize(width: next.width / length * travel, height: next.height / length * travel)
                }
                offset = next
                input.move = CGVector(dx: next.width / travel, dy: -next.height / travel)
                let vector = CGVector(dx: next.width, dy: -next.height)
                direction = vector.length > travel * 0.3 ? Direction(vector, current: direction) : nil
            }
            .onEnded { _ in
                input.move = .zero
                direction = nil
                isPressed = false
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { offset = .zero }
            }
    }
}

/// The same joystick as a picture, pushed `push` (-1...1 each way, y up; zero when let go), for
/// How to play's picture of the game (StoryScene). It springs and tilts like the real one.
struct JoystickPreview: View {
    let push: CGVector

    private let radius: CGFloat = 62
    private let capRadius: CGFloat = 30
    private var travel: CGFloat { radius - capRadius * 0.55 }

    var body: some View {
        let offset = CGSize(width: push.dx * travel, height: -push.dy * travel)
        let length = hypot(offset.width, offset.height)
        let pressed = length > 0.5
        let toward = CGVector(dx: offset.width, dy: -offset.height)
        let direction: Direction? = toward.length > travel * 0.3 ? Direction(toward) : nil
        let tilt: (amount: CGFloat, dx: CGFloat, dy: CGFloat) = pressed
            ? (min(1, length / travel), offset.width / length, offset.height / length)
            : (0, 1, 0)
        ZStack {
            JoystickBase(radius: radius, isPressed: pressed, direction: direction)
            JoystickShaft(offset: offset, width: capRadius * 0.8)
            JoystickCap(radius: capRadius, isPressed: pressed, tilt: tilt)
                .offset(offset)
        }
        .frame(width: radius * 2, height: radius * 2)
        .compositingGroup()
        .opacity(pressed ? 1 : 0.9)
        .animation(.spring(response: 0.28, dampingFraction: 0.5), value: push)
    }
}

private struct JoystickBase: View {
    let radius: CGFloat
    let isPressed: Bool
    let direction: Direction?

    var body: some View {
        ZStack {
            // Glossy light-blue rim, lit from above.
            Circle()
                .fill(LinearGradient(colors: [HUDStyle.frameLight, HUDStyle.frameMid], startPoint: .top, endPoint: .bottom))
            Circle()
                .strokeBorder(HUDStyle.frameDark.opacity(0.85), lineWidth: 1.5)

            // Recessed well, with a soft shadow just under its top edge.
            Circle()
                .inset(by: 9)
                .fill(RadialGradient(
                    colors: [Color(red: 0.17, green: 0.34, blue: 0.57), Color(red: 0.08, green: 0.18, blue: 0.35)],
                    center: .center, startRadius: 2, endRadius: radius - 9
                ))
            Circle()
                .inset(by: 9)
                .strokeBorder(LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .center), lineWidth: 5)
            Circle()
                .inset(by: 9)
                .strokeBorder(HUDStyle.orange.opacity(isPressed ? 0.75 : 0), lineWidth: 1.5)

            // Direction chevrons; the one you're pushing toward lights up.
            ForEach(Direction.allCases, id: \.self) { mark in
                IconImage(.chevronUp, size: 15)
                    .foregroundStyle(mark == direction ? HUDStyle.orange : HUDStyle.frameLight.opacity(0.4))
                    .shadow(color: mark == direction ? HUDStyle.orange.opacity(0.9) : .clear, radius: 4)
                    .offset(y: -radius * 0.74)
                    .rotationEffect(.degrees(mark.angle))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 2)
        .animation(.easeOut(duration: 0.12), value: direction)
        .animation(.easeOut(duration: 0.15), value: isPressed)
    }
}

/// The stick column between the base and the cap, leaning toward the push.
private struct JoystickShaft: View {
    let offset: CGSize
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let tip = CGPoint(x: center.x + offset.width * 0.9, y: center.y + offset.height * 0.9)
            var path = Path()
            path.move(to: center)
            path.addLine(to: tip)
            context.stroke(path, with: .color(Color(red: 0.03, green: 0.08, blue: 0.18)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            context.stroke(path, with: .color(.white.opacity(0.08)), style: StrokeStyle(lineWidth: width * 0.35, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// Domed rubber cap with a concave grip, ridges and a specular highlight.
private struct JoystickCap: View {
    let radius: CGFloat
    let isPressed: Bool
    let tilt: (amount: CGFloat, dx: CGFloat, dy: CGFloat)

    var body: some View {
        let size = radius * 2
        ZStack {
            // Body: warm cream dome, lit from the top-left.
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 1, green: 0.98, blue: 0.9), HUDStyle.cream, Color(red: 0.72, green: 0.62, blue: 0.5)],
                    center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: radius * 1.35
                ))
            // Rim thickness.
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.9), Color(red: 0.5, green: 0.4, blue: 0.32)], startPoint: .top, endPoint: .bottom), lineWidth: 2.5)
            // Concave thumb rest.
            Circle()
                .inset(by: radius * 0.28)
                .fill(RadialGradient(
                    colors: [Color(red: 0.78, green: 0.68, blue: 0.56), Color(red: 0.98, green: 0.93, blue: 0.82)],
                    center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1, endRadius: radius * 0.75
                ))
            // Grip ridges.
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .inset(by: radius * 0.34 + CGFloat(ring) * radius * 0.13)
                    .stroke(Color(red: 0.45, green: 0.36, blue: 0.28).opacity(0.22), lineWidth: 1)
            }
            // Gold accent dot, like a game-console stick.
            Circle()
                .fill(HUDStyle.gold)
                .frame(width: radius * 0.22, height: radius * 0.22)
                .overlay(Circle().stroke(Color(red: 0.6, green: 0.45, blue: 0.1), lineWidth: 1))
            // Specular highlight.
            Ellipse()
                .fill(.white.opacity(0.6))
                .frame(width: size * 0.42, height: size * 0.2)
                .offset(x: -radius * 0.22, y: -radius * 0.5)
                .blur(radius: 1.5)
        }
        .frame(width: size, height: size)
        .rotation3DEffect(
            .degrees(Double(tilt.amount) * 22),
            axis: (x: -tilt.dy, y: tilt.dx, z: 0),
            perspective: 0.6
        )
        .scaleEffect(isPressed ? 0.94 : 1)
        .shadow(color: .black.opacity(0.35), radius: isPressed ? 1.5 : 3, x: 0, y: isPressed ? 1 : 3)
        .animation(.easeOut(duration: 0.12), value: isPressed)
    }
}

private extension Direction {
    /// Degrees clockwise from up, for placing the chevrons.
    var angle: Double {
        switch self {
        case .up: 0
        case .right: 90
        case .down: 180
        case .left: 270
        }
    }
}
