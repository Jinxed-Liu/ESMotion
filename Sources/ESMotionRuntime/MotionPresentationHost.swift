import ESMotionCore
import SwiftUI

#if os(iOS)
  import UIKit

  @MainActor
  public struct MotionPresentationHost<
    Item: Identifiable,
    Root: View,
    Destination: View
  >: UIViewControllerRepresentable {
    @Binding private var item: Item?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let engine: MotionEngine
    private let transitionID: (Item) -> MotionTransitionID
    private let root: () -> Root
    private let destination: (Item) -> Destination

    public init(
      item: Binding<Item?>,
      engine: MotionEngine,
      transitionID: @escaping (Item) -> MotionTransitionID,
      @ViewBuilder root: @escaping () -> Root,
      @ViewBuilder destination: @escaping (Item) -> Destination
    ) {
      _item = item
      self.engine = engine
      self.transitionID = transitionID
      self.root = root
      self.destination = destination
    }

    public func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    public func makeUIViewController(
      context: Context
    ) -> UIViewController {
      let controller = MotionSceneContainerController(engine: engine)
      context.coordinator.controller = controller
      configureBinding(context.coordinator, controller: controller)
      controller.updateRoot(
        hosted(root(), in: controller)
      )
      engine.updateConditions(runtimeConditions)

      if let item {
        controller.showInitialDestination(
          selectionID: AnyHashable(item.id),
          transitionID: transitionID(item),
          content: hosted(destination(item), in: controller)
        )
        context.coordinator.lastSelectionID = AnyHashable(item.id)
      }
      return controller
    }

    public func updateUIViewController(
      _ uiViewController: UIViewController,
      context: Context
    ) {
      guard
        let uiViewController =
          uiViewController as? MotionSceneContainerController
      else {
        return
      }
      configureBinding(context.coordinator, controller: uiViewController)
      scheduleReconciliation(
        coordinator: context.coordinator,
        controller: uiViewController,
        rootContent: hosted(root(), in: uiViewController),
        selectedItem: item
      )
    }

    public static func dismantleUIViewController(
      _ uiViewController: UIViewController,
      coordinator: Coordinator
    ) {
      (uiViewController as? MotionSceneContainerController)?.tearDown()
      coordinator.cancelReconciliation()
      coordinator.controller = nil
    }

    public final class Coordinator {
      fileprivate weak var controller: MotionSceneContainerController?
      fileprivate var lastSelectionID: AnyHashable?
      fileprivate var clearSelection: (() -> Void)?
      fileprivate var reconciliationTask: Task<Void, Never>?
      fileprivate var reconciliationRevision = 0

      fileprivate func cancelReconciliation() {
        reconciliationRevision += 1
        reconciliationTask?.cancel()
        reconciliationTask = nil
      }
    }

    private func hosted<Content: View>(
      _ content: Content,
      in controller: MotionSceneContainerController
    ) -> AnyView {
      AnyView(
        content
          .environment(engine)
          .environment(
            \.motionElementRegistry,
            controller.registry
          )
          .environment(
            \.motionElementVisibility,
            controller.visibility
          )
      )
    }

    private func configureBinding(
      _ coordinator: Coordinator,
      controller: MotionSceneContainerController
    ) {
      let binding = _item
      coordinator.clearSelection = {
        binding.wrappedValue = nil
      }
      controller.clearSelection = { [weak coordinator] in
        coordinator?.clearSelection?()
      }
    }

    private func scheduleReconciliation(
      coordinator: Coordinator,
      controller: MotionSceneContainerController,
      rootContent: AnyView,
      selectedItem: Item?
    ) {
      coordinator.cancelReconciliation()
      let revision = coordinator.reconciliationRevision
      let conditions = runtimeConditions
      let selectedContent = selectedItem.map {
        (
          selectionID: AnyHashable($0.id),
          transitionID: transitionID($0),
          content: hosted(destination($0), in: controller)
        )
      }

      coordinator.reconciliationTask = Task {
        @MainActor [
          weak coordinator,
          weak controller
        ] in
        await Task.yield()
        guard
          !Task.isCancelled,
          let coordinator,
          coordinator.reconciliationRevision == revision,
          let controller
        else {
          return
        }

        controller.updateRoot(rootContent)
        engine.updateConditions(conditions)

        if let selectedContent {
          if coordinator.lastSelectionID
            == selectedContent.selectionID
          {
            controller.updateDestinationContent(
              selectedContent.content
            )
          } else {
            controller.presentDestination(
              selectionID: selectedContent.selectionID,
              transitionID: selectedContent.transitionID,
              content: selectedContent.content
            )
            coordinator.lastSelectionID =
              selectedContent.selectionID
          }
        } else if coordinator.lastSelectionID != nil {
          coordinator.lastSelectionID = nil
          controller.dismissDestination()
        }
        coordinator.reconciliationTask = nil
      }
    }

    private var runtimeConditions: MotionRuntimeConditions {
      MotionRuntimeConditions(
        isSceneActive: scenePhase == .active,
        prefersReducedMotion: reduceMotion,
        prefersPowerSaving:
          ProcessInfo.processInfo.isLowPowerModeEnabled,
        thermalPressure: MotionThermalPressure(
          ProcessInfo.processInfo.thermalState
        )
      )
    }
  }
#else
  @MainActor
  public struct MotionPresentationHost<
    Item: Identifiable,
    Root: View,
    Destination: View
  >: View {
    @Binding private var item: Item?
    private let root: () -> Root
    private let destination: (Item) -> Destination

    public init(
      item: Binding<Item?>,
      engine: MotionEngine,
      transitionID: @escaping (Item) -> MotionTransitionID,
      @ViewBuilder root: @escaping () -> Root,
      @ViewBuilder destination: @escaping (Item) -> Destination
    ) {
      _item = item
      self.root = root
      self.destination = destination
    }

    public var body: some View {
      ZStack {
        if let item {
          destination(item)
        } else {
          root()
        }
      }
    }
  }
#endif
