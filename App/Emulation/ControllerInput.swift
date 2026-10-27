import Foundation
import GameController
import EmulationKit

/// Uses one extended gamepad at a time, switching to another connected pad when
/// it disconnects. Nintendo button names follow their physical positions.
@MainActor
final class ControllerInput {
    private weak var session: EmulationSession?
    private var controller: GCController?
    private var observers: [NSObjectProtocol] = []
    private var generation = UUID()
    private var pressedButtons: Set<EmulatorButton> = []
    private var bindings = ControllerBindings()
    private var swapSticks = false

    init(session: EmulationSession) {
        self.session = session
    }

    func connect() {
        guard observers.isEmpty else { return }
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshController() }
            })
        }
        refreshController()
    }

    func disconnect() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        detachController()
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    private func refreshController() {
        // A notification queued just before disconnect() must not reconnect input.
        guard !observers.isEmpty else { return }
        let connected = GCController.controllers().filter { $0.extendedGamepad != nil }
        if let controller, connected.contains(where: { $0 === controller }) { return }
        detachController()
        guard let next = connected.first, let gamepad = next.extendedGamepad else { return }
        controller = next
        bindings = ControllerBindings(serialized: UserDefaults.standard.string(forKey: ControllerBindings.storageKey) ?? "")
        swapSticks = UserDefaults.standard.bool(forKey: ControllerBindings.swapSticksKey)
        let token = generation

        for (input, button) in buttonMappings(for: gamepad) {
            input?.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.controller != nil else { return }
                    self.setButton(button, pressed: pressed)
                }
            }
        }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.controller != nil else { return }
                self.session?.setStick(self.swapSticks ? .right : .left, x: x, y: y)
            }
        }
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.controller != nil else { return }
                self.session?.setStick(self.swapSticks ? .left : .right, x: x, y: y)
            }
        }

        // Queue the snapshot so session startup can finish before forwarding it.
        // This also captures a button held while the controller was connected.
        Task { @MainActor [weak self] in
            guard let self, self.generation == token,
                  let gamepad = self.controller?.extendedGamepad else { return }
            for (input, button) in self.buttonMappings(for: gamepad) {
                self.setButton(button, pressed: input?.isPressed ?? false)
            }
            self.session?.setStick(self.swapSticks ? .right : .left, x: gamepad.leftThumbstick.xAxis.value, y: gamepad.leftThumbstick.yAxis.value)
            self.session?.setStick(self.swapSticks ? .left : .right, x: gamepad.rightThumbstick.xAxis.value, y: gamepad.rightThumbstick.yAxis.value)
        }
    }

    private func setButton(_ button: EmulatorButton, pressed: Bool) {
        if pressed { pressedButtons.insert(button) } else { pressedButtons.remove(button) }
        session?.setButton(button, pressed: pressed)
    }

    private func detachController() {
        // Invalidate queued callbacks before clearing handlers or releasing input.
        generation = UUID()
        if let gamepad = controller?.extendedGamepad {
            for (input, _) in buttonMappings(for: gamepad) { input?.pressedChangedHandler = nil }
            gamepad.leftThumbstick.valueChangedHandler = nil
            gamepad.rightThumbstick.valueChangedHandler = nil
        }
        for button in pressedButtons { session?.setButton(button, pressed: false) }
        pressedButtons.removeAll()
        session?.setStick(.left, x: 0, y: 0)
        session?.setStick(.right, x: 0, y: 0)
        controller = nil
    }

    private func buttonMappings(for gamepad: GCExtendedGamepad) -> [(GCControllerButtonInput?, EmulatorButton)] {
        let controls: [(GCControllerButtonInput?, ControllerControl)] = [
            // GameController uses Xbox positions: A south, B east, X west, Y north.
            (gamepad.buttonA, .south), (gamepad.buttonB, .east),
            (gamepad.buttonX, .west), (gamepad.buttonY, .north),
            (gamepad.dpad.up, .up), (gamepad.dpad.down, .down),
            (gamepad.dpad.left, .left), (gamepad.dpad.right, .right),
            (gamepad.leftShoulder, .leftShoulder), (gamepad.rightShoulder, .rightShoulder),
            (gamepad.leftTrigger, .leftTrigger), (gamepad.rightTrigger, .rightTrigger),
            (gamepad.buttonMenu, .menu), (gamepad.buttonOptions, .options),
            (gamepad.buttonHome, .home),
            (gamepad.leftThumbstickButton, .leftStick),
            (gamepad.rightThumbstickButton, .rightStick)
        ]
        return controls.compactMap { input, control in
            guard let button = EmulatorButton(rawValue: bindings[control].rawValue) else { return nil }
            return (input, button)
        }
    }
}
