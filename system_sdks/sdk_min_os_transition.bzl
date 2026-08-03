"""Builds this layer's pcms at the SDK min OS rather than the app's.

clang validates a precompiled module against the SDK version, not the consuming
translation unit's deployment target, so a single pcm per SDK serves every
consumer. Building them at the app's deployment target instead makes them
unloadable by any TU compiled for a different one -- notably the
COMPILE_MODULE_INTERFACE actions for imported xcframeworks, which inherit the
deployment target recorded in the vendored .swiftinterface.
"""

_SDK_VERSION_FLAG = "//system_sdks:sdk_version"

_MIN_OS_OPTIONS = [
    "//command_line_option:ios_minimum_os",
    "//command_line_option:macos_minimum_os",
    "//command_line_option:tvos_minimum_os",
    "//command_line_option:watchos_minimum_os",
    "//command_line_option:minimum_os_version",
]

def _sdk_min_os_transition_impl(settings, _attr):
    sdk_version = settings[_SDK_VERSION_FLAG]
    values = {option: settings[option] for option in _MIN_OS_OPTIONS}
    if not sdk_version:
        return values
    for option in _MIN_OS_OPTIONS:
        values[option] = sdk_version
    return values

sdk_min_os_transition = transition(
    implementation = _sdk_min_os_transition_impl,
    inputs = _MIN_OS_OPTIONS + [_SDK_VERSION_FLAG],
    outputs = _MIN_OS_OPTIONS,
)
