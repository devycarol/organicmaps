enum TrackRecordingState {
  case inactive
  case active
  case error(TrackRecordingError)
}

enum TrackRecordingSavingOption {
  case withoutSaving
  case saveWithName(String? = nil)
}

enum TrackRecordingError: Error {
  case locationIsProhibited
}

typealias TrackRecordingStateHandler = (TrackRecordingState) -> Void

protocol TrackRecordingObservation {
  func addObserver(_ observer: AnyObject, trackRecordingStateDidChange handler: @escaping TrackRecordingStateHandler)
  func removeObserver(_ observer: AnyObject)
}

@objcMembers
final class TrackRecordingManager: NSObject {

  fileprivate struct Observation {
    weak var observer: AnyObject?
    var recordingStateDidChangeHandler: TrackRecordingStateHandler?
  }

  static let shared: TrackRecordingManager = TrackRecordingManager(trackRecorder: FrameworkHelper.self)

  private let trackRecorder: TrackRecorder.Type
  private var observers = [ObjectIdentifier: TrackRecordingManager.Observation]()
  private(set) var recordingState: TrackRecordingState = .inactive {
    didSet {
      notifyObservers(recordingState)
    }
  }

  private init(trackRecorder: TrackRecorder.Type) {
    self.trackRecorder = trackRecorder
    super.init()
    self.recordingState = getCurrentRecordingState()
  }

  func toggleRecording() {
    let state = getCurrentRecordingState()
    switch state {
    case .inactive:
      start()
    case .active:
      stop()
    case .error(let error):
      handleError(error)
    }
  }

  private func handleError(_ error: TrackRecordingError) {
    switch error {
    case .locationIsProhibited:
      // Show alert to enable location
      LocationManager.checkLocationStatus()
    }
    stopRecording(.withoutSaving)
  }

  private func getCurrentRecordingState() -> TrackRecordingState {
    guard !LocationManager.isLocationProhibited() else {
      return .error(.locationIsProhibited)
    }
    return FrameworkHelper.isTrackRecordingEnabled() ? .active : .inactive
  }

  private func start() {
    FrameworkHelper.startTrackRecording()
    recordingState = .active
  }

  private func stop() {
    guard !FrameworkHelper.isTrackRecordingEmpty() else {
      // TODO:  localize
      Toast.toast(withText: "Track is empty - nothing to save").show()
      stopRecording(.withoutSaving)
      return
    }
    Self.showOnFinishRecordingAlert(onSave: { [weak self] in
      guard let self else { return }
      self.stopRecording(.saveWithName()) // TODO: pass the name if needed
    },
                                    onStop: { [weak self] in
      guard let self else { return }
      self.stopRecording(.withoutSaving)
    })
  }

  private func stopRecording(_ savingOption: TrackRecordingSavingOption) {
    switch savingOption {
    case .withoutSaving:
      FrameworkHelper.stopTrackRecordingWithoutSaving()
    case .saveWithName(let name):
      FrameworkHelper.stopTrackRecordingAndSave(withName: name)
    }
    recordingState = .inactive
  }
  
  // TODO:  localize
  private static func showOnFinishRecordingAlert(onSave: @escaping () -> Void, onStop: @escaping () -> Void) {
    let alert = UIAlertController(title: L("Save recording?"), message: "Your track will be saved to the latest list", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: L("Save"), style: .cancel, handler: { _ in onSave() }))
    alert.addAction(UIAlertAction(title: L("Stop Without Saving"), style: .default, handler: { _ in onStop() }))
    alert.addAction(UIAlertAction(title: L("Continue"), style: .default, handler: nil))
    UIViewController.topViewController().present(alert, animated: true)
  }
}

// MARK: - TrackRecorder + Observation
extension TrackRecordingManager: TrackRecordingObservation {
  func addObserver(_ observer: AnyObject, trackRecordingStateDidChange handler: @escaping TrackRecordingStateHandler) {
    let id = ObjectIdentifier(observer)
    observers[id] = Observation(observer: observer, recordingStateDidChangeHandler: handler)
    notifyObservers(recordingState)
  }

  func removeObserver(_ observer: AnyObject) {
    let id = ObjectIdentifier(observer)
    observers.removeValue(forKey: id)
  }

  private func notifyObservers(_ state: TrackRecordingState) {
    observers = observers.filter { $0.value.observer != nil }
    observers.values.forEach { $0.recordingStateDidChangeHandler?(state) }
  }
}
