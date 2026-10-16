//
//  GlobalTapToDismiss.swift
// TileRate Installation Estimator
//
//  Created by Salvatore Militello on 9/1/25.
//

import SwiftUI

#if canImport(UIKit)
// iOS / iPadOS: attach a tap recognizer to the UIWindow
struct WindowTapToDismiss: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            guard let window = view.window, context.coordinator.gesture == nil else { return }
            let g = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
            g.cancelsTouchesInView = false      // don’t swallow taps
            g.delaysTouchesBegan = false
            g.delegate = context.coordinator     // filter taps on text inputs
            window.addGestureRecognizer(g)
            context.coordinator.gesture = g
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var gesture: UITapGestureRecognizer?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }

        // Don’t trigger when tapping inside text inputs — lets focus move without closing keyboard
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let v = touch.view else { return true }
            if v is UITextField || v is UITextView { return false }
            var s = v.superview
            while let sv = s {
                if sv is UITextField || sv is UITextView { return false }
                s = sv.superview
            }
            // Nor on a field's box around it (its padding), so a tap there goes
            // straight into the field instead of first closing the keyboard
            // (owner, 2026-10-16: tapping from width to length took two taps).
            if let window = v.window, Self.fields(in: window).contains(where: { f in
                f.convert(f.bounds, to: window).insetBy(dx: -16, dy: -16).contains(touch.location(in: window))
            }) { return false }
            return true
        }

        private static func fields(in view: UIView) -> [UIView] {
            var out: [UIView] = []
            for sub in view.subviews where !sub.isHidden && sub.alpha > 0.01 {
                if sub is UITextField || sub is UITextView { out.append(sub) } else { out += fields(in: sub) }
            }
            return out
        }
    }
}
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
// macOS: attach to NSWindow’s content view
struct MacWindowTapToDismiss: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window, context.coordinator.gesture == nil else { return }
            let g = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick))
            g.numberOfClicksRequired = 1
            window.contentView?.addGestureRecognizer(g)
            context.coordinator.gesture = g
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject {
        var gesture: NSClickGestureRecognizer?
        @objc func handleClick(_ sender: Any?) {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}
#endif

// One-line modifier to enable globally at the app root
extension View {
    func applyGlobalTapToDismiss() -> some View {
        #if canImport(UIKit)
        self.background(WindowTapToDismiss())
        #elseif canImport(AppKit)
        self.background(MacWindowTapToDismiss())
        #else
        self
        #endif
    }
}
