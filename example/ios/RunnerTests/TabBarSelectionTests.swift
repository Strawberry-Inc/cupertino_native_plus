import Flutter
import UIKit
import XCTest

@testable import cupertino_native_plus

/// CNTabBar のネイティブのタブバーが、ラベルを描き直す refresh の後も、今の選択を見せる。
///
/// refresh は各タブを 10ms ずつ順に選んで回り、最後に選択を戻す。Dart は作った直後に
/// refresh と setSelectedIndex を続けて送るので、setSelectedIndex は回っている間に届く。
/// 戻すのを回る前の選択にすると、その setSelectedIndex が消える。Loom では、閉じた状態から
/// リンクで起動して設定のタブを開くと、ページは設定なのに、タブバーは最初のタブのままに
/// なることがあった。
final class TabBarSelectionTests: XCTestCase {
  /// ビューのチャネルの受け口を取っておき、Dart の代わりにメソッドを呼べるようにする。
  private final class ChannelMessenger: NSObject, FlutterBinaryMessenger {
    var handlers: [String: FlutterBinaryMessageHandler] = [:]

    func send(onChannel channel: String, message: Data?) {}
    func send(
      onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply? = nil
    ) {}
    func setMessageHandlerOnChannel(
      _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler? = nil
    ) -> FlutterBinaryMessengerConnection {
      handlers[channel] = handler
      return 0
    }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
  }

  private let messenger = ChannelMessenger()
  private let labels = ["やること", "カレンダー", "設定"]

  /// [settle] が false なら、作った直後の非同期の処理を待たずに返す。
  private func makeView(
    selectedIndex: Int, split: Bool = false, splitRightAsButton: Bool = false,
    settle: Bool = true
  ) -> CupertinoTabBarPlatformView {
    let args: [String: Any] = [
      "labels": labels,
      "sfSymbols": ["checkmark.circle", "calendar", "gearshape"],
      "selectedIndex": NSNumber(value: selectedIndex),
      "split": NSNumber(value: split),
      "rightCount": NSNumber(value: 1),
      "splitRightAsButton": NSNumber(value: splitRightAsButton),
    ]
    let view = CupertinoTabBarPlatformView(
      frame: CGRect(x: 0, y: 0, width: 390, height: 50), viewId: 1, args: args,
      messenger: messenger)
    if settle {
      // 作った直後の非同期の処理（項目の付け直しと、その中で積む処理）を済ませる
      drainMainQueue()
      drainMainQueue()
    }
    return view
  }

  /// Dart がチャネルで送るのと同じように、ビューのメソッドを呼んで返事を返す。
  @discardableResult
  private func send(_ method: String, _ arguments: Any? = nil) throws -> Any? {
    let handler = try XCTUnwrap(messenger.handlers.values.first)
    let codec = FlutterStandardMethodCodec.sharedInstance()
    var reply: Any?
    handler(codec.encode(FlutterMethodCall(methodName: method, arguments: arguments))) { data in
      if let data = data { reply = codec.decodeEnvelope(data) }
    }
    return reply
  }

  private func bars(of view: CupertinoTabBarPlatformView) -> [UITabBar] {
    view.view().subviews.compactMap { $0 as? UITabBar }
  }

  /// メインキューに今まで積まれた処理を済ませる（キューは積んだ順に動く）。
  private func drainMainQueue() {
    let drained = expectation(description: "メインキューの処理が済む")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 2)
  }

  /// refresh が回り終えるまで待つ。回っている間は、バーの delegate が外れている。
  private func waitForRefresh(of bars: [UITabBar]) {
    let deadline = Date().addingTimeInterval(2)
    while bars.contains(where: { $0.delegate == nil }), Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    XCTAssertFalse(bars.contains { $0.delegate == nil }, "refresh が終わらない")
  }

  /// 利用者がタブを押したときと同じく、バーの選択を変えてから delegate に知らせる。
  private func tap(_ index: Int, in bar: UITabBar, of view: CupertinoTabBarPlatformView) throws {
    let item = try XCTUnwrap(bar.items?[index])
    bar.selectedItem = item
    view.tabBar(bar, didSelect: item)
  }

  private func selectedIndex(of bar: UITabBar) -> Int? {
    bar.items?.firstIndex { $0 === bar.selectedItem }
  }

  func test_refreshが回り終える前に届いた選択を_refreshの後も見せる() throws {
    let view = makeView(selectedIndex: 0)
    let bar = try XCTUnwrap(bars(of: view).first)

    try send("refresh")
    try send("setSelectedIndex", ["index": 2])
    waitForRefresh(of: [bar])

    XCTAssertEqual(selectedIndex(of: bar), 2)
  }

  func test_押されたタブを_refreshの後も見せる() throws {
    let view = makeView(selectedIndex: 0)
    let bar = try XCTUnwrap(bars(of: view).first)

    // 押されたタブは、Dart から setSelectedIndex で送り返されない
    try tap(1, in: bar, of: view)
    try send("refresh")
    waitForRefresh(of: [bar])

    XCTAssertEqual(selectedIndex(of: bar), 1)
  }

  func test_押した後にDartが別のタブを選んだら_refreshの後もそのタブを見せる() throws {
    let view = makeView(selectedIndex: 0)
    let bar = try XCTUnwrap(bars(of: view).first)

    try tap(1, in: bar, of: view)
    try send("setSelectedIndex", ["index": 2])
    try send("refresh")
    waitForRefresh(of: [bar])

    XCTAssertEqual(selectedIndex(of: bar), 2)
  }

  func test_refreshの途中に範囲外の選択が届いても_その前に届いた選択を見せる() throws {
    let view = makeView(selectedIndex: 0)
    let bar = try XCTUnwrap(bars(of: view).first)

    try send("refresh")
    try send("setSelectedIndex", ["index": 1])
    let reply = try send("setSelectedIndex", ["index": 99])
    waitForRefresh(of: [bar])

    XCTAssertTrue(reply is FlutterError, "範囲外はエラーを返す")
    XCTAssertEqual(selectedIndex(of: bar), 1)
  }

  func test_refreshの途中で項目が差し替わっても_新しい項目で今の選択を見せる() throws {
    let view = makeView(selectedIndex: 1)
    let bar = try XCTUnwrap(bars(of: view).first)

    try send("refresh")
    drainMainQueue()  // 回り始める（最初のタブを選び、次は 10ms 後）
    XCTAssertNil(bar.delegate, "まだ回っている")
    try send(
      "setItems",
      [
        "labels": labels,
        "sfSymbols": ["checkmark.circle.fill", "calendar", "gearshape"],
        "selectedIndex": 2,
      ])
    waitForRefresh(of: [bar])

    let items = try XCTUnwrap(bar.items)
    XCTAssertIdentical(bar.selectedItem, items[2])
    XCTAssertTrue(UIView.areAnimationsEnabled)
  }

  func test_分割表示でrefreshの途中に項目の数が変わっても_新しい項目で今の選択を見せる() throws {
    let view = makeView(selectedIndex: 0, split: true)
    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let left = try XCTUnwrap(split.first)
    let right = try XCTUnwrap(split.last)

    try send("refresh")
    drainMainQueue()
    XCTAssertNil(left.delegate, "まだ回っている")
    try send(
      "setItems",
      [
        "labels": ["やること", "カレンダー", "メモ", "設定"],
        "sfSymbols": ["checkmark.circle", "calendar", "note.text", "gearshape"],
        "selectedIndex": 3,
      ])
    waitForRefresh(of: split)

    XCTAssertEqual(left.items?.count, 3)
    XCTAssertNil(left.selectedItem)
    XCTAssertEqual(selectedIndex(of: right), 0)
    XCTAssertTrue(UIView.areAnimationsEnabled)
  }

  func test_分割表示でrefreshの途中に項目の数が減っても_新しい項目で今の選択を見せる() throws {
    let view = makeView(selectedIndex: 0, split: true)
    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let left = try XCTUnwrap(split.first)
    let right = try XCTUnwrap(split.last)

    try send("refresh")
    drainMainQueue()
    XCTAssertNil(left.delegate, "まだ回っている")
    try send(
      "setItems",
      [
        "labels": ["やること", "設定"],
        "sfSymbols": ["checkmark.circle", "gearshape"],
        "selectedIndex": 1,
      ])
    waitForRefresh(of: split)

    XCTAssertEqual(left.items?.count, 1)
    XCTAssertNil(left.selectedItem)
    XCTAssertEqual(selectedIndex(of: right), 0)
    XCTAssertTrue(UIView.areAnimationsEnabled)
  }

  func test_右をボタンにした分割表示を右のタブの位置で作ると_右の選択を外す() throws {
    let view = makeView(selectedIndex: 2, split: true, splitRightAsButton: true)
    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let right = try XCTUnwrap(split.last)

    XCTAssertNil(right.selectedItem)
  }

  func test_分割表示で作った直後に届いた選択を_作った後の処理で戻さない() throws {
    let view = makeView(selectedIndex: 0, split: true, settle: false)
    try send("setSelectedIndex", ["index": 2])
    drainMainQueue()
    drainMainQueue()

    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let left = try XCTUnwrap(split.first)
    let right = try XCTUnwrap(split.last)
    XCTAssertNil(left.selectedItem)
    XCTAssertEqual(selectedIndex(of: right), 0)
  }

  func test_レイアウトを変えた直後に届いた選択を_作り直した後の処理で戻さない() throws {
    let view = makeView(selectedIndex: 0)

    try send(
      "setLayout",
      ["split": true, "rightCount": 1, "selectedIndex": 0, "splitRightAsButton": false])
    try send("setSelectedIndex", ["index": 2])
    drainMainQueue()
    drainMainQueue()

    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let left = try XCTUnwrap(split.first)
    let right = try XCTUnwrap(split.last)
    XCTAssertNil(left.selectedItem)
    XCTAssertEqual(selectedIndex(of: right), 0)
  }

  func test_分割表示でも_refreshが回り終える前に届いた選択を_refreshの後も見せる() throws {
    let view = makeView(selectedIndex: 0, split: true)
    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let left = try XCTUnwrap(split.first)
    let right = try XCTUnwrap(split.last)

    try send("refresh")
    try send("setSelectedIndex", ["index": 2])
    waitForRefresh(of: split)

    XCTAssertNil(left.selectedItem)
    XCTAssertEqual(selectedIndex(of: right), 0)
  }

  func test_分割表示で押された右のタブを_refreshの後も見せる() throws {
    let view = makeView(selectedIndex: 0, split: true)
    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let left = try XCTUnwrap(split.first)
    let right = try XCTUnwrap(split.last)

    try tap(0, in: right, of: view)
    try send("refresh")
    waitForRefresh(of: split)

    XCTAssertNil(left.selectedItem)
    XCTAssertEqual(selectedIndex(of: right), 0)
  }

  func test_分割表示でrefreshの途中に右をボタンにしても_右のタブを選んだままにしない() throws {
    let view = makeView(selectedIndex: 2, split: true)
    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let right = try XCTUnwrap(split.last)

    try send("refresh")
    try send("setSplitRightAsButton", ["value": true])
    waitForRefresh(of: split)

    XCTAssertNil(right.selectedItem)
  }

  func test_レイアウトを変えた直後に右をボタンにしたら_作り直した後の処理で右を選ばない() throws {
    let view = makeView(selectedIndex: 0)

    try send(
      "setLayout",
      ["split": true, "rightCount": 1, "selectedIndex": 2, "splitRightAsButton": false])
    try send("setSplitRightAsButton", ["value": true])
    drainMainQueue()
    drainMainQueue()

    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let right = try XCTUnwrap(split.last)
    XCTAssertNil(right.selectedItem)
  }

  func test_右をボタンにした分割表示で_ボタンを押した後は_その前に押した左のタブに戻す() throws {
    let view = makeView(selectedIndex: 0, split: true, splitRightAsButton: true)
    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let left = try XCTUnwrap(split.first)
    let right = try XCTUnwrap(split.last)

    try tap(1, in: left, of: view)
    try tap(0, in: right, of: view)
    drainMainQueue()  // ボタンの選択は、次の回で外して左に戻す

    XCTAssertEqual(selectedIndex(of: left), 1)
    XCTAssertNil(right.selectedItem)
  }

  func test_右をボタンにした分割表示で_ボタンを押した直後に届いた選択を見せる() throws {
    let view = makeView(selectedIndex: 1, split: true, splitRightAsButton: true)
    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let left = try XCTUnwrap(split.first)
    let right = try XCTUnwrap(split.last)

    try tap(0, in: right, of: view)
    // ボタンの選択を外す次の回より前に、Dart から別のタブの選択が届く
    try send("setSelectedIndex", ["index": 0])
    drainMainQueue()

    XCTAssertEqual(selectedIndex(of: left), 0)
    XCTAssertNil(right.selectedItem)
  }

  func test_右をボタンにした分割表示で_ボタンを押した直後にボタンをやめて右を選んだら_右のタブを見せる() throws {
    let view = makeView(selectedIndex: 0, split: true, splitRightAsButton: true)
    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let left = try XCTUnwrap(split.first)
    let right = try XCTUnwrap(split.last)

    try tap(0, in: right, of: view)
    // ボタンの選択を外す次の回より前に、ボタンをやめて右のタブを選ぶ
    try send("setSplitRightAsButton", ["value": false])
    try send("setSelectedIndex", ["index": 2])
    drainMainQueue()

    XCTAssertNil(left.selectedItem)
    XCTAssertEqual(selectedIndex(of: right), 0)
  }

  func test_右をボタンにした分割表示で_ボタンを押した後のrefreshでも_左のタブを見せる() throws {
    let view = makeView(selectedIndex: 0, split: true, splitRightAsButton: true)
    let split = bars(of: view)
    XCTAssertEqual(split.count, 2)
    let left = try XCTUnwrap(split.first)
    let right = try XCTUnwrap(split.last)

    try tap(1, in: left, of: view)
    try tap(0, in: right, of: view)
    drainMainQueue()
    try send("refresh")
    waitForRefresh(of: split)

    XCTAssertEqual(selectedIndex(of: left), 1)
    XCTAssertNil(right.selectedItem)
  }
}
