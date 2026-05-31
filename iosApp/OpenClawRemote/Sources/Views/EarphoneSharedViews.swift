import SwiftUI
import UIKit

struct CompatibleNavigationStack<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
            }
        } else {
            NavigationView {
                content()
            }
            .navigationViewStyle(.stack)
        }
    }
}

struct EarphoneSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

struct EmptyStateView: View {
    let systemName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

extension Date {
    var earphoneListTimeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(self) ? "HH:mm" : "MM月dd日 HH:mm"
        return formatter.string(from: self)
    }
}

extension View {
    @ViewBuilder
    func hideTabBarWhileVisible() -> some View {
        if #available(iOS 16.0, *) {
            toolbar(.hidden, for: .tabBar)
        } else {
            background(TabBarVisibilityController(isHidden: true))
        }
    }
}

private struct TabBarVisibilityController: UIViewControllerRepresentable {
    let isHidden: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller(isHidden: isHidden)
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.isHidden = isHidden
        uiViewController.applyVisibility()
    }

    final class Controller: UIViewController {
        var isHidden: Bool
        private weak var adjustedController: UIViewController?
        private var originalAdditionalSafeAreaBottom: CGFloat?

        init(isHidden: Bool) {
            self.isHidden = isHidden
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyVisibility()
        }

        override func viewSafeAreaInsetsDidChange() {
            super.viewSafeAreaInsetsDidChange()
            applyVisibility()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restoreVisibility()
        }

        func applyVisibility() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let tabBarController = self.tabBarController else { return }
                guard self.isHidden else {
                    self.restoreVisibility()
                    return
                }

                let targetController = self.targetController(in: tabBarController)
                if self.adjustedController !== targetController {
                    self.restoreAdjustedSafeArea()
                    self.adjustedController = targetController
                    self.originalAdditionalSafeAreaBottom = targetController.additionalSafeAreaInsets.bottom
                }

                var insets = targetController.additionalSafeAreaInsets
                let originalBottom = self.originalAdditionalSafeAreaBottom ?? 0
                insets.bottom = originalBottom - self.collapsedTabBarSafeAreaInset(in: tabBarController)
                targetController.additionalSafeAreaInsets = insets
                tabBarController.tabBar.isHidden = true
                targetController.view.setNeedsLayout()
                targetController.view.layoutIfNeeded()
            }
        }

        private func restoreVisibility() {
            restoreAdjustedSafeArea()
            tabBarController?.tabBar.isHidden = false
        }

        private func restoreAdjustedSafeArea() {
            guard let adjustedController, let originalAdditionalSafeAreaBottom else { return }
            var insets = adjustedController.additionalSafeAreaInsets
            insets.bottom = originalAdditionalSafeAreaBottom
            adjustedController.additionalSafeAreaInsets = insets
            adjustedController.view.setNeedsLayout()
            self.adjustedController = nil
            self.originalAdditionalSafeAreaBottom = nil
        }

        private func targetController(in tabBarController: UITabBarController) -> UIViewController {
            if let navigationController = tabBarController.selectedViewController as? UINavigationController {
                return navigationController.topViewController ?? navigationController
            }
            return tabBarController.selectedViewController ?? tabBarController
        }

        private func collapsedTabBarSafeAreaInset(in tabBarController: UITabBarController) -> CGFloat {
            let tabBarHeight = tabBarController.tabBar.bounds.height
            let bottomSafeAreaInset = tabBarController.view.window?.safeAreaInsets.bottom
                ?? view.window?.safeAreaInsets.bottom
                ?? 0
            return max(0, tabBarHeight - bottomSafeAreaInset)
        }
    }
}
