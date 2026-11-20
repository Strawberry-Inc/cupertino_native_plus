import Flutter
import UIKit
import XCTest

@testable import cupertino_native_plus

/// LiquidGlassContainer のガラスを、窓の安全領域で縮めない。
///
/// プラットフォームビューの位置と大きさは Flutter が決める。中のガラスまで窓の安全領域に
/// 合わせると、画面の下端近くまで届く入れ物（下端から少し浮かせたシートなど）で、ホーム
/// インジケーターの領域にかかる下の部分だけ、ガラスが描かれなかった。
final class LiquidGlassContainerSafeAreaTests: XCTestCase {
  /// チャネルを使わないテスト用のメッセンジャー。
  private final class StubMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(
      onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply? = nil
    ) {}
    func setMessageHandlerOnChannel(
      _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler? = nil
    ) -> FlutterBinaryMessengerConnection { 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
  }

  private var window: UIWindow?

  override func tearDown() {
    window?.isHidden = true
    window = nil
    super.tearDown()
  }

  /// ガラスのレイヤーが出そろうまで待ち、入れ物と同じ幅のレイヤーの枠を [root] の座標で返す。
  ///
  /// SwiftUI のガラスは UIView にならず、ホスティングのビューの下のレイヤーで描かれる
  /// （iOS 26.5 のシミュレーターでは、ガラスの形の大きさを持つ CABackdropLayer などが
  /// 並んでいた）。そのレイヤーの作りに頼り、入れ物と同じ幅のレイヤーを、ガラスとその包みと
  /// みなす。
  private func waitForWideLayerFrames(in root: UIView, timeout: TimeInterval = 5) -> [CGRect] {
    let deadline = Date().addingTimeInterval(timeout)
    var frames: [CGRect] = []
    repeat {
      window?.layoutIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
      frames = wideLayerFrames(in: root)
      // 描きかけの枠を拾わないよう、ガラスのレイヤーが見つかってから少し待って読み直す
      if hasBackdropLayer(in: root.layer) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        frames = wideLayerFrames(in: root)
        break
      }
    } while Date() < deadline
    return frames
  }

  private func hasBackdropLayer(in layer: CALayer) -> Bool {
    // CABackdropLayer は公開されていないので、クラス名で見分ける
    if String(describing: type(of: layer)).contains("Backdrop") { return true }
    return (layer.sublayers ?? []).contains { hasBackdropLayer(in: $0) }
  }

  private func wideLayerFrames(in root: UIView) -> [CGRect] {
    var frames: [CGRect] = []
    func visit(_ layer: CALayer) {
      for child in layer.sublayers ?? [] where !child.isHidden && child.opacity > 0 {
        let frame = child.convert(child.bounds, to: root.layer)
        if frame.height > 0 && abs(frame.width - root.bounds.width) < 0.5 { frames.append(frame) }
        visit(child)
      }
    }
    visit(root.layer)
    return frames
  }

  func test_窓の下の安全領域に重なっても_ガラスを入れ物の下端まで描く() throws {
    guard #available(iOS 26.0, *) else {
      throw XCTSkip("ガラスの入れ物は iOS 26 以降だけ")
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = try XCTUnwrap(
      scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)
    let window = UIWindow(windowScene: scene)
    self.window = window
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    // 下に安全領域のある端末（ホームインジケーターのある端末）で確かめる
    try XCTSkipIf(window.safeAreaInsets.bottom < 20, "下に安全領域のある端末で動かす")

    let container = LiquidGlassContainerPlatformView(
      frame: .zero,
      viewId: 1,
      args: [
        "effect": "regular",
        "shape": "rect",
        "cornerRadius": 40.0,
        "interactive": false,
        "isDark": false,
      ],
      messenger: StubMessenger())
    let containerView = container.view()
    let root = try XCTUnwrap(window.rootViewController?.view)
    // 画面の下端から 8pt 浮かせたシートと同じく、下の安全領域にかかる位置に置く
    let height: CGFloat = 300
    containerView.frame = CGRect(
      x: 8, y: root.bounds.height - height - 8, width: root.bounds.width - 16, height: height)
    root.addSubview(containerView)

    let frames = waitForWideLayerFrames(in: containerView)
    XCTAssertGreaterThan(
      containerView.safeAreaInsets.bottom, 0, "入れ物に下の安全領域がかかっていない")
    XCTAssertTrue(hasBackdropLayer(in: containerView.layer), "ガラスが描かれない")
    XCTAssertFalse(frames.isEmpty, "ガラスのレイヤーが見つからない")
    for frame in frames {
      XCTAssertGreaterThanOrEqual(
        frame.maxY, containerView.bounds.height - 0.5, "ガラスが入れ物の下端まで届いていない: \(frame)")
      XCTAssertLessThanOrEqual(frame.minY, 0.5, "ガラスが入れ物の上端から始まっていない: \(frame)")
    }
  }
}
