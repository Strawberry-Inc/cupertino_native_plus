import Flutter
import UIKit
import XCTest

@testable import cupertino_native_plus

/// CNGlassButtonGroup のボタンを、窓の安全領域で動かさない。
///
/// プラットフォームビューの位置と大きさは Flutter が決める。中のボタンまで窓の安全領域に
/// 合わせると、Flutter が置いた場所からずれる。iPhone Duo では、ヒンジを開く途中で窓の上に
/// 一瞬だけ安全領域ができ、ヘッダーのボタンが約 54pt 下がったまま戻らなかった。
final class GlassButtonGroupSafeAreaTests: XCTestCase {
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

  /// ボタンのガラスとみなすビューが出るまで待ち、その枠を [root] の座標で返す。
  ///
  /// SwiftUI のボタンそのものは UIView にならないが、iOS 27.2 のシミュレーターでは、
  /// ガラスがボタンの形の UIView で描かれていた。そのビューの作りに頼り、グループいっぱいに
  /// 広がる包みのビューと大きさのないビューを除いたものを、ガラスとみなす。
  private func waitForGlassFrames(in root: UIView, timeout: TimeInterval = 5) -> [CGRect] {
    let deadline = Date().addingTimeInterval(timeout)
    var frames: [CGRect] = []
    repeat {
      window?.layoutIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
      frames = glassFrames(in: root)
      // 描きかけの枠を拾わないよう、見つかってから少し待って読み直す
      if !frames.isEmpty {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        frames = glassFrames(in: root)
        if !frames.isEmpty { break }
      }
    } while Date() < deadline
    return frames
  }

  private func glassFrames(in root: UIView) -> [CGRect] {
    var frames: [CGRect] = []
    func visit(_ view: UIView) {
      for child in view.subviews where !child.isHidden && child.alpha > 0 {
        let frame = child.convert(child.bounds, to: root)
        let fillsGroup =
          abs(frame.minX - root.bounds.minX) < 0.5 && abs(frame.minY - root.bounds.minY) < 0.5
          && abs(frame.width - root.bounds.width) < 0.5
          && abs(frame.height - root.bounds.height) < 0.5
        if frame.width > 0 && frame.height > 0 && !fillsGroup { frames.append(frame) }
        visit(child)
      }
    }
    visit(root)
    return frames
  }

  func test_窓の上の安全領域に重なっても_ボタンをグループの外へ下げない() throws {
    guard #available(iOS 26.0, *) else {
      throw XCTSkip("ガラスのボタンは iOS 26 以降だけ")
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = try XCTUnwrap(
      scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)
    let window = UIWindow(windowScene: scene)
    self.window = window
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    // 上に安全領域のある端末（ステータスバーの下）で確かめる
    try XCTSkipIf(window.safeAreaInsets.top < 20, "上に安全領域のある端末で動かす")

    let group = GlassButtonGroupPlatformView(
      frame: .zero,
      viewId: 1,
      args: [
        "buttons": [
          ["label": "A", "minHeight": 44.0, "glassEffectUnionId": "group"],
          ["label": "B", "minHeight": 44.0, "glassEffectUnionId": "group"],
        ],
        "axis": "horizontal",
        "spacing": 0.0,
      ],
      messenger: StubMessenger())
    let groupView = group.view()
    // ヒンジを開く途中の Duo のヘッダーと同じく、上の安全領域にかかる位置に置く
    groupView.frame = CGRect(x: 16, y: 6, width: 96, height: 44)
    try XCTUnwrap(window.rootViewController?.view).addSubview(groupView)

    let frames = waitForGlassFrames(in: groupView)
    XCTAssertGreaterThan(groupView.safeAreaInsets.top, 0, "グループに上の安全領域がかかっていない")
    XCTAssertFalse(frames.isEmpty, "ボタンのガラスが描かれない")
    for frame in frames {
      XCTAssertGreaterThanOrEqual(frame.minY, -0.5, "ボタンがグループの上にはみ出した: \(frame)")
      XCTAssertLessThanOrEqual(
        frame.maxY, groupView.bounds.height + 0.5, "ボタンがグループの下にはみ出した: \(frame)")
    }
  }
}
