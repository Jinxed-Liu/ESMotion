import Combine
import ESMotionCore
import SwiftUI

#if os(iOS)
  import UIKit
#endif

enum MotionPortalRole: Hashable {
  case source
  case destination
}

struct MotionPortalKey: Hashable {
  let id: MotionTransitionID
  let role: MotionPortalRole
}

@MainActor
final class MotionElementVisibility: ObservableObject {
  @Published private(set) var hiddenKeys: Set<MotionPortalKey> = []

  func hide(_ keys: Set<MotionPortalKey>) {
    guard !keys.isSubset(of: hiddenKeys) else { return }
    hiddenKeys.formUnion(keys)
  }

  func show(_ keys: Set<MotionPortalKey>) {
    guard !hiddenKeys.isDisjoint(with: keys) else { return }
    hiddenKeys.subtract(keys)
  }

  func showAll() {
    guard !hiddenKeys.isEmpty else { return }
    hiddenKeys.removeAll()
  }

  func isHidden(_ key: MotionPortalKey) -> Bool {
    hiddenKeys.contains(key)
  }
}

#if os(iOS)
  @MainActor
  final class MotionElementRegistry {
    final class Entry {
      weak var view: MotionElementMarkerView?
      var cornerRadius: CGFloat
      var isOpaque: Bool
      var snapshotProvider: MotionPortalSnapshotProvider?

      init(
        view: MotionElementMarkerView,
        cornerRadius: CGFloat,
        isOpaque: Bool,
        snapshotProvider: MotionPortalSnapshotProvider?
      ) {
        self.view = view
        self.cornerRadius = cornerRadius
        self.isOpaque = isOpaque
        self.snapshotProvider = snapshotProvider
      }
    }

    private var entries: [MotionPortalKey: Entry] = [:]

    func upsert(
      view: MotionElementMarkerView,
      key: MotionPortalKey,
      cornerRadius: CGFloat,
      isOpaque: Bool,
      snapshotProvider: MotionPortalSnapshotProvider?
    ) {
      if let entry = entries[key], entry.view === view {
        entry.cornerRadius = max(cornerRadius, 0)
        entry.isOpaque = isOpaque
        entry.snapshotProvider = snapshotProvider
      } else {
        entries[key] = Entry(
          view: view,
          cornerRadius: max(cornerRadius, 0),
          isOpaque: isOpaque,
          snapshotProvider: snapshotProvider
        )
      }
    }

    func remove(view: MotionElementMarkerView, key: MotionPortalKey) {
      guard entries[key]?.view === view else { return }
      entries[key] = nil
    }

    func entry(for key: MotionPortalKey) -> Entry? {
      guard let entry = entries[key], entry.view != nil else {
        entries[key] = nil
        return nil
      }
      return entry
    }
  }
#else
  @MainActor
  final class MotionElementRegistry {}
#endif

private struct MotionElementRegistryEnvironmentKey: EnvironmentKey {
  static let defaultValue: MotionElementRegistry? = nil
}

private struct MotionElementVisibilityEnvironmentKey: EnvironmentKey {
  static let defaultValue: MotionElementVisibility? = nil
}

extension EnvironmentValues {
  var motionElementRegistry: MotionElementRegistry? {
    get { self[MotionElementRegistryEnvironmentKey.self] }
    set { self[MotionElementRegistryEnvironmentKey.self] = newValue }
  }

  var motionElementVisibility: MotionElementVisibility? {
    get { self[MotionElementVisibilityEnvironmentKey.self] }
    set { self[MotionElementVisibilityEnvironmentKey.self] = newValue }
  }
}

extension View {
  public func motionPortalSource(
    id: MotionTransitionID,
    cornerRadius: CGFloat,
    isOpaque: Bool = true,
    snapshotProvider: MotionPortalSnapshotProvider? = nil
  ) -> some View {
    modifier(
      MotionPortalElementModifier(
        key: MotionPortalKey(id: id, role: .source),
        cornerRadius: cornerRadius,
        isOpaque: isOpaque,
        snapshotProvider: snapshotProvider
      )
    )
  }

  public func motionPortalDestination(
    id: MotionTransitionID,
    cornerRadius: CGFloat = 0,
    isOpaque: Bool = true,
    snapshotProvider: MotionPortalSnapshotProvider? = nil
  ) -> some View {
    modifier(
      MotionPortalElementModifier(
        key: MotionPortalKey(id: id, role: .destination),
        cornerRadius: cornerRadius,
        isOpaque: isOpaque,
        snapshotProvider: snapshotProvider
      )
    )
  }
}

private struct MotionPortalElementModifier: ViewModifier {
  @Environment(\.motionElementRegistry) private var registry
  @Environment(\.motionElementVisibility) private var visibility

  let key: MotionPortalKey
  let cornerRadius: CGFloat
  let isOpaque: Bool
  let snapshotProvider: MotionPortalSnapshotProvider?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let registry, let visibility {
      MotionObservedPortalElement(
        content: content,
        registry: registry,
        visibility: visibility,
        key: key,
        cornerRadius: cornerRadius,
        isOpaque: isOpaque,
        snapshotProvider: snapshotProvider
      )
    } else {
      content
    }
  }
}

private struct MotionObservedPortalElement<Content: View>: View {
  let content: Content
  let registry: MotionElementRegistry
  @ObservedObject var visibility: MotionElementVisibility
  let key: MotionPortalKey
  let cornerRadius: CGFloat
  let isOpaque: Bool
  let snapshotProvider: MotionPortalSnapshotProvider?

  var body: some View {
    content
      .opacity(visibility.isHidden(key) ? 0 : 1)
      .background {
        #if os(iOS)
          MotionElementMarkerBridge(
            registry: registry,
            key: key,
            cornerRadius: cornerRadius,
            isOpaque: isOpaque,
            snapshotProvider: snapshotProvider
          )
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        #else
          Color.clear
        #endif
      }
  }
}

#if os(iOS)
  @MainActor
  final class MotionElementMarkerView: UIView {
    weak var registry: MotionElementRegistry?
    var key = MotionPortalKey(id: "", role: .source)
    var cornerRadius: CGFloat = 0
    var isOpaquePortal = true
    var snapshotProvider: MotionPortalSnapshotProvider?

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .clear
      isUserInteractionEnabled = false
      isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      updateRegistration()
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      updateRegistration()
    }

    func configure(
      registry: MotionElementRegistry,
      key: MotionPortalKey,
      cornerRadius: CGFloat,
      isOpaque: Bool,
      snapshotProvider: MotionPortalSnapshotProvider?
    ) {
      if self.registry !== registry || self.key != key {
        unregister()
      }
      self.registry = registry
      self.key = key
      self.cornerRadius = cornerRadius
      isOpaquePortal = isOpaque
      self.snapshotProvider = snapshotProvider
      updateRegistration()
    }

    func unregister() {
      registry?.remove(view: self, key: key)
    }

    private func updateRegistration() {
      guard window != nil, bounds.width > 0, bounds.height > 0 else {
        return
      }
      registry?.upsert(
        view: self,
        key: key,
        cornerRadius: cornerRadius,
        isOpaque: isOpaquePortal,
        snapshotProvider: snapshotProvider
      )
    }
  }

  private struct MotionElementMarkerBridge: UIViewRepresentable {
    let registry: MotionElementRegistry
    let key: MotionPortalKey
    let cornerRadius: CGFloat
    let isOpaque: Bool
    let snapshotProvider: MotionPortalSnapshotProvider?

    func makeUIView(context: Context) -> MotionElementMarkerView {
      MotionElementMarkerView()
    }

    func updateUIView(
      _ uiView: MotionElementMarkerView,
      context: Context
    ) {
      uiView.configure(
        registry: registry,
        key: key,
        cornerRadius: cornerRadius,
        isOpaque: isOpaque,
        snapshotProvider: snapshotProvider
      )
    }

    static func dismantleUIView(
      _ uiView: MotionElementMarkerView,
      coordinator: Void
    ) {
      uiView.unregister()
    }
  }
#endif
