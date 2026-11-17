// swift-tools-version: 5.9
import PackageDescription

// Was "DO NOT MODIFY THIS FILE - managed by Capacitor CLI commands". Nov 17 —
// it is edited by hand now, because the Capacitor CLI is no longer installed
// and must not be run: `cap sync` would put the three dead resources back that
// were taken out of the Xcode project this morning. This is the only place the
// iOS app's Capacitor version is set, so this is where it gets bumped.
//
// 8.5.0 -> 8.5.1 closes GHSA-rvm3-566m-v7fv (critical): "remote content can be
// loaded at the app origin via the internal HTTP proxy path". Almost certainly
// not reachable in Rex, which never constructs a CAPBridgeViewController and so
// has no WebView for the proxy to serve into — but "we think it is unreachable"
// is a worse position than being on the patched version, and this is a patch
// release.
let package = Package(
    name: "CapApp-SPM",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "CapApp-SPM",
            targets: ["CapApp-SPM"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", exact: "8.5.1")
    ],
    targets: [
        .target(
            name: "CapApp-SPM",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ]
        )
    ]
)
