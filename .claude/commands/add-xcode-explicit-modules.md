Add explicit module support for a new Xcode version in the `system_sdks/` directory.

If the user provided an Xcode version string (e.g. `26.5.0.17F42`), use it directly. Otherwise, detect it automatically.

## Step 1 — Determine the Xcode version string

Run:
```
xcode-select -p
```
Then get the build version from the active Xcode app. The version string format is `<marketing_version>.<build_version>` (e.g. `26.5.0.17F42`). You can extract it with:
```
xcrun xcodebuild -version
```
The build version (e.g. `17F42`) combined with the version number (e.g. `26.5.0`) forms the directory name `26.5.0.17F42`.

## Step 2 — Find the most recent existing version directory to copy from

Look at `system_sdks/` for existing version directories (e.g. `26.0.1.17A400`, `16.3.0.16E140`). Use the most recent one as the template — prefer one with `__BAZEL_XCODE_SDKROOT__` paths (26.x versions) over the older `__BAZEL_XCODE_DEVELOPER_DIR__` format.

## Step 3 — Copy the previous version's directory

```
cp -r system_sdks/<previous_version>/ system_sdks/<new_version>/
```

## Step 4 — Update the clang header path

The clang built-in headers path (e.g. `clang/17/include`) is hardcoded in some module map paths and changes between Xcode versions. Find the correct version:
```
ls /Applications/<Xcode_app>/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/
```
That directory contains a single versioned folder (e.g. `21`). Then update all BUILD.bazel files:
```
find system_sdks/<new_version>/ -name "BUILD.bazel" | xargs sed -i '' 's|clang/<old_version>/include|clang/<new_version>/include|g'
```

## Step 5 — Fix version references in `system_sdks/<new_version>/BUILD`

The copied `BUILD` file still has all `deps` pointing at the previous version's subdirectories. Update every reference to use the new version:

```
sed -i '' 's|system_sdks/<previous_version>/|system_sdks/<new_version>/|g' \
  system_sdks/<new_version>/BUILD
```

Verify no old version strings remain:
```
grep "<previous_version>" system_sdks/<new_version>/BUILD
```

This file controls which per-platform `BUILD.bazel` is selected for each CPU/OS combination. If these deps are wrong, the correct `xcode_version_flag_exact` config_setting will match but Bazel will still build the previous version's modules — causing clang path mismatches at execution time.

## Step 6 — Wire up the new version in `system_sdks/BUILD`

Add a new `config_setting` block and entries in both `select` statements:

```python
# Xcode <marketing_version>
config_setting(
    name = "xcode_<version_underscored>",
    flag_values = {
        "@bazel_tools//tools/osx:xcode_version_flag_exact": "<full_version_string>",
    },
)
```

Then add `":<config_setting_name>": ["//system_sdks/<new_version>:system_sdks"]` to the `system_sdks` select and the same pattern for `testonly_system_sdks`.

## Step 7 — Validate with `swiftc -scan-dependencies` on ALL platforms

**Validate every platform directory that exists under the new version** (e.g. `iPhoneSimulator/arm64`, `iPhoneOS/arm64`, `MacOSX/arm64`, `WatchOS`, `WatchSimulator/arm64`), not just iPhoneSimulator. And validate **dependency edges**, not just module names — a module can exist in the BUILD file but be missing a dep that is new in this SDK. With implicit modules disabled, a missing edge fails at build time with:

```
error: module '<X>' is needed but has not been provided, and implicit use of module files is disabled
```

(Real example: in Xcode 27.0 beta 27A5228h, `math.h` gained an include of the toolchain's `float.h` under `__need_infinity_nan`, adding a new `_DarwinFoundation1` → `_Builtin_float` edge that the copied BUILD didn't declare.)

For each platform, create a Swift file importing every module defined in that platform's BUILD.bazel:
```
gen_imports() {
  grep 'module_name = ' "$1" \
    | sed 's/.*module_name = "\(.*\)".*/import \1/' \
    | grep -v -e '^import _Builtin_' -e '^import _AvailabilityInternal' -e '^import _SwiftConcurrencyShims' \
              -e '^import SwiftShims' -e '^import ptrauth' -e '^import ptrcheck' -e '^import sys_types' \
              -e '^import os_object' -e '^import os_workgroup' \
              -e '^import XCTest$' -e '^import XCUIAutomation$' -e '^import StoreKitTest$' \
    | sort -u > "$2"
}
```

Run the scanner once per platform with the matching SDK and target triple (they can run in parallel with `&` + `wait`):

| Platform dir | SDK | `-target` |
|---|---|---|
| `iPhoneSimulator/arm64` | `iPhoneSimulator.sdk` | `arm64-apple-ios18.0-simulator` |
| `iPhoneOS/arm64` | `iPhoneOS.sdk` | `arm64-apple-ios18.0` |
| `MacOSX/arm64` | `MacOSX.sdk` | `arm64-apple-macos15.0` |
| `WatchOS` | `WatchOS.sdk` | `arm64_32-apple-watchos11.0` |
| `WatchSimulator/arm64` | `WatchSimulator.sdk` | `arm64-apple-watchos11.0-simulator` |

```
swiftc -scan-dependencies \
  -sdk /Applications/<Xcode_app>/Contents/Developer/Platforms/<Platform>.platform/Developer/SDKs/<Platform>.sdk \
  -target <target_triple> \
  <imports_platform>.swift > scan_<platform>.json 2> err_<platform>.txt
```

A non-empty stderr means an unresolvable import (usually a testonly framework living outside the SDK, like XCTest/StoreKitTest) — exclude it from the import file and rescan.

Then compare the scanner output against each BUILD file — both **missing modules** (name level) and **missing edges** (each clang module's `directDependencies` must all appear in that target's `deps`). The scan JSON's `modules` array alternates identifier/detail entries:

```python
import json, re

def load_scan(path):
    mods = json.load(open(path))['modules']
    deps, mmaps = {}, {}
    for i in range(0, len(mods), 2):
        ident, detail = mods[i], mods[i+1]
        if 'clang' in ident:
            deps[ident['clang']] = [d['clang'] for d in detail.get('directDependencies', []) if 'clang' in d]
            mm = [s for s in detail.get('sourceFiles', []) if s.endswith('.modulemap')]
            mmaps[ident['clang']] = mm[0] if mm else None
    return deps, mmaps

scan_deps, scan_mmaps = load_scan('scan_<platform>.json')
src = open('system_sdks/<new_version>/<platform>/BUILD.bazel').read()
build_deps = {m.group(1): set(re.findall(r'":([^"]+)"', m.group(0)))
              for m in re.finditer(r'swift_c_module\(\s*name = "([^"]+)",.*?\n\)', src, re.S)}

missing_modules = set(scan_deps) - set(build_deps)
missing_edges = {m: sorted(set(d) - build_deps[m]) for m, d in scan_deps.items()
                 if m in build_deps and set(d) - build_deps[m]}
print("Missing modules:", sorted(missing_modules))
print("Missing edges:", missing_edges)
```

## Step 8 — Fix missing edges and missing modules

For each platform, until the Step 7 comparison is completely clean:

1. **Missing edges**: add each scanner-reported dep to the existing `swift_c_module` target's `deps` list (add a `deps` attribute if the target has none). Add *all* missing direct edges from the scanner, not just ones that fail today — an edge satisfied transitively can break when the SDK's dep graph shifts again.

2. **Missing modules**: add a `swift_c_module` target with `deps` taken directly from the scanner's `directDependencies` and `system_module_map` from the scanner's modulemap path, rewritten to the platform's prefix convention:
   - `iPhoneSimulator/*`: `__BAZEL_XCODE_SDKROOT__/...`
   - `iPhoneOS/*`: `__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/...`
   - `MacOSX/*`: `__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/...`
   - `WatchOS` / `WatchSimulator/*`: `__BAZEL_XCODE_SDKROOT__/...`

   Register each new target in the `all_generated_targets` `swift_library_group` at the bottom of the file.

3. **Re-run the Step 7 comparison** and repeat — adding new module targets typically surfaces a second round of missing edges, because edges pointing at not-yet-existing targets couldn't be added in the first pass (e.g. `ARKit` → `ARKitCore`).

4. As a final sanity check, verify the resulting dep graph has no cycles (DFS over `build_deps`).

Note: platforms differ — WatchOS/WatchSimulator BUILD files are much smaller and can be missing common frameworks (CoreAudio, CoreMedia, CoreMotion, XPC) that became reachable in a new SDK, and iPhoneOS/MacOSX can have SubFramework modules (e.g. `ARKitCore` under `System/Library/SubFrameworks/`) that don't exist on iPhoneSimulator.

## Step 9 — Commit and push

```
git add system_sdks/<new_version>/ system_sdks/BUILD
git commit -m "Add explicit module support for Xcode <version>"
git push
```

## Notes

- The `iPhoneOS/arm64` BUILD.bazel uses `__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/...` paths instead of `__BAZEL_XCODE_SDKROOT__/...`. This is expected and matches the pattern from prior versions.
- MacOSX BUILD files also use `__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/...` paths.
- WatchOS/WatchSimulator BUILD files use `__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/WatchOS.platform/...` paths for Darwin/DarwinFoundation entries.
- `XCTest`, `XCUIAutomation`, and `StoreKitTest` are testonly modules living outside the SDK — they will fail in the scan but are intentionally handled separately in `testonly_system_sdks`. Exclude them from the import files.
- The `_Builtin_*`, `_AvailabilityInternal`, `SwiftShims`, `_SwiftConcurrencyShims`, `ptrauth`, `ptrcheck`, `sys_types`, `os_object`, and `os_workgroup` modules are low-level clang/system modules; exclude them from the import files used in Step 7. They still show up as scanner deps of other modules, so their edges get validated regardless.
