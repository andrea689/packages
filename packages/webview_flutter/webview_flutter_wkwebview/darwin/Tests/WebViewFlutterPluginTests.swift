// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation
import Testing

@testable import webview_flutter_wkwebview

#if os(iOS)
  import Flutter
  import UIKit
#endif

@Suite struct WebViewFlutterPluginTests {
  #if os(iOS)
    @MainActor @Test func instanceManagerIsDeallocatedInApplicationWillTerminate() async throws {
      let plugin = WebViewFlutterPlugin(binaryMessenger: TestBinaryMessenger())
      plugin.proxyApiRegistrar!.setUp()

      let view = UIView()
      _ = plugin.proxyApiRegistrar!.instanceManager.addHostCreatedInstance(view)

      // Attaches an associated object to the InstanceManager to listen for when it is deallocated.
      var finalizer: TestFinalizer? = TestFinalizer()

      let key = malloc(1)!
      defer {
        free(key)
      }
      objc_setAssociatedObject(
        plugin.proxyApiRegistrar!.instanceManager, key, finalizer, .OBJC_ASSOCIATION_RETAIN)

      await confirmation("Wait for InstanceManager to be deallocated.") { confirm in
        finalizer!.onDeinit = {
          confirm()
        }

        // Ensure method is from `FlutterApplicationLifeCycleDelegate`.
        (plugin as FlutterApplicationLifeCycleDelegate).applicationWillTerminate!(
          UIApplication.shared)
        #expect(plugin.proxyApiRegistrar == nil)

        finalizer = nil
        // The instance manager is cleared once the main queue has drained.
        await drainMainQueue()
      }
    }

    @MainActor @Test func instanceManagerIsDeallocatedInSceneDidDisconnect() async throws {
      let plugin = WebViewFlutterPlugin(binaryMessenger: TestBinaryMessenger())
      plugin.proxyApiRegistrar!.setUp()

      let view = UIView()
      _ = plugin.proxyApiRegistrar!.instanceManager.addHostCreatedInstance(view)

      // Attaches an associated object to the InstanceManager to listen for when it is deallocated.
      var finalizer: TestFinalizer? = TestFinalizer()

      let key = malloc(1)!
      defer {
        free(key)
      }
      objc_setAssociatedObject(
        plugin.proxyApiRegistrar!.instanceManager, key, finalizer, .OBJC_ASSOCIATION_RETAIN)

      await confirmation("Wait for InstanceManager to be deallocated.") { confirm in
        finalizer!.onDeinit = {
          confirm()
        }

        let scene = UIApplication.shared.connectedScenes.first!

        // Ensure method is from `FlutterSceneLifeCycleDelegate`.
        (plugin as FlutterSceneLifeCycleDelegate).sceneDidDisconnect?(scene)
        #expect(plugin.proxyApiRegistrar == nil)

        finalizer = nil
        // The instance manager is cleared once the main queue has drained.
        await drainMainQueue()
      }
    }

    @MainActor @Test func teardownKeepsInstancesForMessagesAlreadyQueued() async throws {
      let plugin = WebViewFlutterPlugin(binaryMessenger: TestBinaryMessenger())
      let registrar = plugin.proxyApiRegistrar!
      let codec = registrar.codec

      let view = UIView()
      let identifier = registrar.instanceManager.addHostCreatedInstance(view)
      // A message from Dart that names the instance, which the engine dispatched to the main
      // queue before the scene disconnected.
      let message = codec.encode([view])

      let scene = UIApplication.shared.connectedScenes.first!
      (plugin as FlutterSceneLifeCycleDelegate).sceneDidDisconnect?(scene)

      // Its handler decodes after teardown and must still find the instance: generated handlers
      // force-cast their arguments.
      let arguments = codec.decode(message) as? [Any?]
      #expect(arguments?.first as? UIView === view)

      await drainMainQueue()
      let cleared: UIView? = registrar.instanceManager.instance(forIdentifier: identifier)
      #expect(cleared == nil)
    }

    @MainActor @Test func codecOutlivesTeardown() async throws {
      var plugin: WebViewFlutterPlugin? = WebViewFlutterPlugin(
        binaryMessenger: TestBinaryMessenger())
      var codec: FlutterStandardMessageCodec? = plugin!.proxyApiRegistrar!.codec
      let registrarReference = WeakTestReference(plugin!.proxyApiRegistrar)

      let scene = UIApplication.shared.connectedScenes.first!
      (plugin! as FlutterSceneLifeCycleDelegate).sceneDidDisconnect?(scene)
      plugin = nil
      await drainMainQueue()

      // A reply still being encoded keeps the registrar alive instead of reading freed memory.
      #expect(registrarReference.value != nil)
      let reply = codec!.decode(codec!.encode(["result", UIView()])) as? [Any?]
      #expect(reply?.first as? String == "result")
      // Proxy API instances are no longer sent once calls to Dart are disabled.
      #expect(!(reply?[1] is UIView))

      codec = nil
      #expect(registrarReference.value == nil)
    }

    @MainActor @Test func callbackRegistrarCycleIsReleasedOnTeardown() async {
      let plugin = WebViewFlutterPlugin(binaryMessenger: TestBinaryMessenger())
      let registrarReference = WeakTestReference(plugin.proxyApiRegistrar)
      autoreleasepool {
        let handler = ScriptMessageHandlerImpl(
          api: plugin.proxyApiRegistrar!.apiDelegate.pigeonApiWKScriptMessageHandler(
            plugin.proxyApiRegistrar!),
          registrar: plugin.proxyApiRegistrar!)
        _ = plugin.proxyApiRegistrar!.instanceManager.addHostCreatedInstance(handler)
        #expect(registrarReference.value != nil)

        (plugin as FlutterApplicationLifeCycleDelegate).applicationWillTerminate!(
          UIApplication.shared)
      }
      await drainMainQueue()

      #expect(plugin.proxyApiRegistrar == nil)
      #expect(registrarReference.value == nil)
    }
  #endif
}

/// Lets the work already enqueued on the main queue run, such as the instance manager clear that
/// plugin teardown defers.
@MainActor func drainMainQueue() async {
  await withCheckedContinuation { continuation in
    DispatchQueue.main.async { continuation.resume() }
  }
}

class TestFinalizer {
  // Per instance: the instance manager is now released after the main queue drains, while
  // other tests run, so a shared callback would confirm the wrong test.
  var onDeinit: (() -> Void)?

  deinit {
    onDeinit?()
  }
}

final class WeakTestReference<Value: AnyObject> {
  weak var value: Value?

  init(_ value: Value?) {
    self.value = value
  }
}
