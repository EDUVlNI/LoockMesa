import AppKit
import Combine

@main
struct MenuChecks {
    @MainActor static func main() {
        let screen = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        let size = CGSize(width: 300, height: 300)
        precondition(HUDPosition.left.origin(screen: screen, size: size).x == -1920)
        precondition(HUDPosition.right.origin(screen: screen, size: size).x == -300)
        precondition(HUDPosition.center.origin(screen: screen, size: size) == CGPoint(x: -1110, y: -100))
        let state = HUDState()
        var updates = 0
        let token = state.$value.dropFirst().sink { _ in updates += 1 }
        for _ in 0..<100 { state.show(style: .iOSVolume, value: 0.65) }
        precondition(updates == 1, "Repeated levels must not invalidate the view")
        withExtendedLifetime(token) {}
        precondition(IOSHUDView(value: 0.7, icon: "speaker", isVisible: true).currentIcon == "speaker.wave.3.fill", "Volume glyph must use the latest level before fill animation starts")
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        assert(CapsuleController.isMenuBarBounds(CGRect(x: 0, y: 0, width: 1440, height: 24), display: display))
        assert(CapsuleController.isMenuBarBounds(CGRect(x: 0, y: -18, width: 1440, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 0, y: -24, width: 1440, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 0, y: 0, width: 300, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 0, y: 60, width: 1440, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 1440, y: 0, width: 1920, height: 24), display: display))
        let second = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        assert(CapsuleController.isMenuBarBounds(CGRect(x: -1920, y: -100, width: 1920, height: 24), display: second))
        print("PASS menu visible, entering, hidden, unrelated windows and multiple-display coordinates")
    }
}
