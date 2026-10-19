// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

/// Forwards to the engine's messenger until the plugin is torn down, then drops messages to Dart.
///
/// Teardown happens when the engine may already be shutting down, and sending to it then can
/// abort the app (https://github.com/flutter/flutter/issues/168535). `ignoreCallsToDart` stops the
/// calls made by the APIs, but not the instance manager's finalizer callbacks, which message Dart
/// when an instance is deallocated. Message handlers are still set and removed as usual, so
/// teardown can unregister them.
final class TeardownAwareBinaryMessenger: NSObject, FlutterBinaryMessenger {
  private let messenger: FlutterBinaryMessenger
  private let lock = NSLock()
  private var isTornDown = false

  init(_ messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  /// Drops every message sent to Dart from now on, the way the engine drops messages on a dead
  /// channel.
  func tearDown() {
    lock.lock()
    isTornDown = true
    lock.unlock()
  }

  private var canSend: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !isTornDown
  }

  func send(onChannel channel: String, message: Data?) {
    guard canSend else { return }
    messenger.send(onChannel: channel, message: message)
  }

  func send(
    onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply? = nil
  ) {
    guard canSend else { return }
    messenger.send(onChannel: channel, message: message, binaryReply: callback)
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler? = nil
  ) -> FlutterBinaryMessengerConnection {
    return messenger.setMessageHandlerOnChannel(channel, binaryMessageHandler: handler)
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
    messenger.cleanUpConnection(connection)
  }
}
