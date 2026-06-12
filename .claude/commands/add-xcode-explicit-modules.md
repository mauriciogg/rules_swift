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

## Step 7 — Validate with `swiftc -scan-dependencies`

Create a temporary Swift file that imports every module defined in the new BUILD files:
```
grep 'module_name = ' system_sdks/<new_version>/iPhoneSimulator/arm64/BUILD.bazel \
  | sed 's/.*module_name = "\(.*\)".*/import \1/' \
  | grep -v '^import _Builtin_' \
  | grep -v '^import _AvailabilityInternal' \
  | grep -v '^import _SwiftConcurrencyShims' \
  | grep -v '^import SwiftShims' \
  | grep -v '^import ptrauth' \
  | grep -v '^import ptrcheck' \
  | grep -v '^import sys_types' \
  | grep -v '^import os_object' \
  | grep -v '^import os_workgroup' \
  | sort -u > /tmp/check_sdks.swift
```

Run the scanner against the iPhoneSimulator SDK (adjust iOS version as needed):
```
swiftc -scan-dependencies \
  -sdk /Applications/<Xcode_app>/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk \
  -target arm64-apple-ios18.0-simulator \
  /tmp/check_sdks.swift \
  > /tmp/scan_output.json 2>/tmp/scan_stderr.txt
```

Then parse the output to find any clang modules discovered by the scanner that are **not** in the BUILD file:
```python
import json, subprocess

with open('/tmp/scan_output.json') as f:
    data = json.load(f)

scan_clang = {list(m.values())[0] for m in data['modules'] if 'clang' in m}

result = subprocess.run(
    ["grep", "module_name = ", "system_sdks/<new_version>/iPhoneSimulator/arm64/BUILD.bazel"],
    capture_output=True, text=True
)
build_modules = {line.strip().split('"')[1] for line in result.stdout.splitlines()}

missing = scan_clang - build_modules
print("Missing from BUILD:", sorted(missing))
```

## Step 8 — Add any missing modules

For each module found in Step 6 that is missing from the BUILD files:

1. Find which `module.modulemap` defines it:
   ```
   find /Applications/<Xcode_app>/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk \
     -name "*.modulemap" | xargs grep -l "<ModuleName>"
   ```

2. Check whether it's a new module (not in the previous version's SDK) or just missing from the copy.

3. Add a `swift_c_module` target to all relevant per-platform BUILD.bazel files using the same `module.modulemap` path as the framework it belongs to. Use `:FrameworkName` as a dep if it shares the same module map.

4. Add the new target to the `all_generated_targets` `swift_library_group` at the bottom of each BUILD.bazel file.

5. Repeat for all platforms that include the parent framework (typically iPhoneOS/arm64, iPhoneSimulator/arm64, iPhoneSimulator/x86_64, MacOSX/arm64, MacOSX/x86_64; WatchOS only if the framework exists there).

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
- `XCTest` and `XCUIAutomation` are testonly modules — they will fail in the scan but are intentionally handled separately in `testonly_system_sdks`.
- The `_Builtin_*`, `_AvailabilityInternal`, `SwiftShims`, `_SwiftConcurrencyShims`, `ptrauth`, `ptrcheck`, `sys_types`, `os_object`, and `os_workgroup` modules are low-level clang/system modules; exclude them from the import file used in Step 6.
