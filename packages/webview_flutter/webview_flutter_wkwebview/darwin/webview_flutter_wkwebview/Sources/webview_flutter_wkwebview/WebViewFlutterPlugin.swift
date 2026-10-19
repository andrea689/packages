// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

public class WebViewFlutterPlugin: NSObject, FlutterPlugin {
  var proxyApiRegistrar: ProxyAPIRegistrar?

  init(binaryMessenger: FlutterBinaryMessenger) {
    proxyApiRegistrar = ProxyAPIRegistrar(
      binaryMessenger: binaryMessenger)
    proxyApiRegistrar?.setUp()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let binaryMessenger = registrar.messenger()
    #else
      let binaryMessenger = registrar.messenger
    #endif
    let plugin = WebViewFlutterPlugin(binaryMessenger: binaryMessenger)

    let viewFactory = FlutterViewFactory(instanceManager: plugin.proxyApiRegistrar!.instanceManager)

    #if os(iOS)
      registrar.addApplicationDelegate(plugin)
      registrar.addSceneDelegate(plugin)
    #endif

    registrar.register(viewFactory, withId: "plugins.flutter.io/webview")
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    tearDownProxyAPIRegistrar()
  }

  private func tearDownProxyAPIRegistrar() {
    guard let registrar = proxyApiRegistrar else { return }
    registrar.ignoreCallsToDart = true
    registrar.tearDown()
    proxyApiRegistrar = nil
    // A Dart message the engine has already dispatched to the main queue still runs its handler
    // after tearDown, and decodes its arguments through the instance manager. Clearing it now
    // would hand that handler a null instead of its object. Clear it once those messages have
    // drained; the main queue is FIFO and later messages no longer find a handler.
    DispatchQueue.main.async {
      try? registrar.instanceManager.removeAllObjects()
    }
  }
}

#if os(iOS)
  extension WebViewFlutterPlugin: FlutterApplicationLifeCycleDelegate, FlutterSceneLifeCycleDelegate
  {
    public func applicationWillTerminate(_ application: UIApplication) {
      tearDownProxyAPIRegistrar()
    }

    public func sceneDidDisconnect(_ scene: UIScene) {
      tearDownProxyAPIRegistrar()
    }
  }
#endif
