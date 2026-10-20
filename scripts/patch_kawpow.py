#!/usr/bin/env python3
"""Patch a kawpow-metal checkout so it can run from inside MacDualMiner.app.

Upstream locates its Metal shader template and epoch light-cache files via #filePath
(the source directory on the machine that compiled it). Inside an app bundle that
directory doesn't exist, so we read them from environment variables instead:

  KAWPOW_RESOURCE_DIR  folder containing KawpowShader.metal.template
  KAWPOW_CACHE_DIR     writable folder for epochNNN.light cache files

We also make stdout line-buffered so the app sees hashrate lines immediately
through a pipe, and build in Swift 5 language mode.

Usage: patch_kawpow.py <kawpow-metal checkout>
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
main = root / "Sources" / "main.swift"
package = root / "Package.swift"


def replace_once(text: str, old: str, new: str, what: str) -> str:
    count = text.count(old)
    if count != 1:
        sys.exit(f"patch_kawpow: expected exactly one match for {what}, found {count}. "
                 f"Upstream changed – update scripts/patch_kawpow.py or pin KAWPOW_COMMIT.")
    return text.replace(old, new)


src = main.read_text()
if "kawpowResourceDir()" in src:
    print("patch_kawpow: already patched")
    sys.exit(0)

src = replace_once(
    src,
    "// Parse args\n",
    "setvbuf(stdout, nil, _IOLBF, 0) // MacDualMiner: line-buffered output through pipes\n\n// Parse args\n",
    "args marker",
)
src = replace_once(
    src,
    'URL(fileURLWithPath: #filePath).deletingLastPathComponent()\n'
    '            .deletingLastPathComponent().appendingPathComponent("epoch\\(epoch).light").path',
    'kawpowCacheDir().appendingPathComponent("epoch\\(epoch).light").path',
    "light cache path",
)
src = replace_once(
    src,
    'URL(fileURLWithPath: #filePath).deletingLastPathComponent()\n'
    '            .appendingPathComponent("KawpowShader.metal.template").path',
    'kawpowResourceDir().appendingPathComponent("KawpowShader.metal.template").path',
    "shader template path",
)
main.write_text(src)

(root / "Sources" / "AppPaths.swift").write_text('''import Foundation

// Added by MacDualMiner's build (scripts/patch_kawpow.py).

func kawpowResourceDir() -> URL {
    if let dir = ProcessInfo.processInfo.environment["KAWPOW_RESOURCE_DIR"], !dir.isEmpty {
        return URL(fileURLWithPath: dir, isDirectory: true)
    }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
}

func kawpowCacheDir() -> URL {
    let dir: URL
    if let path = ProcessInfo.processInfo.environment["KAWPOW_CACHE_DIR"], !path.isEmpty {
        dir = URL(fileURLWithPath: path, isDirectory: true)
    } else {
        dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
''')

package.write_text('''// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "kawpow-metal",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "kawpow-metal", path: "Sources", exclude: ["KawpowShader.metal.template"]),
    ],
    swiftLanguageModes: [.v5]
)
''')
print("patch_kawpow: patched", root)
