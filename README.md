# WKWebSQL
This is an add-on for Apple's WKWebView that adds support for WebSQL. Recommended for iOS 9+

This code is under the MIT License.

The package requires 3 external libraries

https://github.com/stephencelis/SQLite.swift

https://github.com/SwiftyJSON/SwiftyJSON

https://github.com/XWebView

Because this is my first real go at Xcode and iOS dev beyond a small toy problem, I admit I didn't really know what I was doing coco pod wise. May come back to that in a bit.

This project allows you to use WebSQL inside of WKWebView via the openDatabase or window.openDatabase method. Loading it is as simple as

    var webView = WKWebView(frame: view.frame, configuration: WKWebViewConfiguration())
    WKWebSQL.LoadPlugin(webView)
It works with iOS 8.* but I wouldn't recommend using it on anything less than iOS 9.* because they changed how JSContexts are handled and greatly improved things in iOS 9.
