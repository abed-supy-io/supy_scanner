import Foundation

/// Observes `ProcessInfo.thermalStateDidChangeNotification` and surfaces a
/// pause/throttle signal to the camera analyzers.
///
/// Mirrors `ThermalGovernor.kt`: even a flagship downgrades when the OS
/// reports `.serious`, but state-clean devices stay uncapped.
final class SupyThermalGovernor {

  enum State: String {
    case nominal
    case fair
    case serious
    case critical
  }

  typealias Listener = (_ state: State, _ shouldPause: Bool, _ shouldThrottle: Bool) -> Void

  private let listener: Listener
  private var observer: NSObjectProtocol?

  private(set) var state: State = .nominal

  init(listener: @escaping Listener) {
    self.listener = listener
  }

  func start() {
    let center = NotificationCenter.default
    observer = center.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.publish()
    }
    publish()
  }

  func stop() {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
  }

  var shouldPause: Bool { state == .serious || state == .critical }
  var shouldThrottle: Bool { state == .fair || state == .serious || state == .critical }

  private func publish() {
    state = Self.map(ProcessInfo.processInfo.thermalState)
    listener(state, shouldPause, shouldThrottle)
  }

  private static func map(_ raw: ProcessInfo.ThermalState) -> State {
    switch raw {
    case .nominal: return .nominal
    case .fair: return .fair
    case .serious: return .serious
    case .critical: return .critical
    @unknown default: return .serious
    }
  }
}
