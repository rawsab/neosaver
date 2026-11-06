import AppKit
import ScreenSaver

@objc(NeosaverView)
public final class NeosaverView: ScreenSaverView {
    private var scene: ClockSceneView!
    private var settingsController: SettingsController?
    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup()
    }
    public required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    private func setup() {
        animationTimeInterval = 1.0 / 30
        scene = ClockSceneView(frame: bounds)
        scene.autoresizingMask = [.width, .height]
        addSubview(scene)
    }
    public override func startAnimation() { super.startAnimation(); scene.start() }
    public override func stopAnimation() { scene.stop(); super.stopAnimation() }
    public override func animateOneFrame() { scene.tick() }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { scene?.stop() }
    }
    public override var hasConfigureSheet: Bool { true }
    public override var configureSheet: NSWindow? {
        if settingsController == nil {
            settingsController = SettingsController()
            settingsController?.onSave = { [weak self] in self?.scene.reloadSettings() }
        }
        settingsController?.prepare()
        return settingsController?.window
    }
}
