load("@bazel_skylib//rules:common_settings.bzl", "string_flag")
load("//swift:swift.bzl", "swift_library_group")

package(default_visibility = ["//visibility:public"])

# Pins the min OS that this layer's pcms are built at. clang validates a pcm
# against the SDK version rather than the consuming TU's deployment target, so
# building them at the app's deployment target makes them unusable by any TU on
# a different one (e.g. compiling a vendored .swiftinterface that records its
# own, older deployment target). Empty keeps the previous behaviour.
string_flag(
    name = "sdk_version",
    build_setting_default = "",
)

# Xcode 16.3
config_setting(
    name = "xcode_16_3_0_16E140",
    flag_values = {
        "@bazel_tools//tools/osx:xcode_version_flag_exact": "16.3.0.16E140",
    },
)

# Xcode 26.0.1
config_setting(
    name = "xcode_26_0_1_17A400",
    flag_values = {
        "@bazel_tools//tools/osx:xcode_version_flag_exact": "26.0.1.17A400",
    },
)

# Xcode 26.5
config_setting(
    name = "xcode_26_5_0_17F42",
    flag_values = {
        "@bazel_tools//tools/osx:xcode_version_flag_exact": "26.5.0.17F42",
    },
)

# Xcode 27.0
config_setting(
    name = "xcode_27_0_0_27A5218g",
    flag_values = {
        "@bazel_tools//tools/osx:xcode_version_flag_exact": "27.0.0.27A5218g",
    },
)

swift_library_group(
    name = "system_sdks",
    deps = select({
        ":xcode_16_3_0_16E140": ["//system_sdks/16.3.0.16E140:system_sdks"],
        ":xcode_26_0_1_17A400": ["//system_sdks/26.0.1.17A400:system_sdks"],
        ":xcode_26_5_0_17F42": ["//system_sdks/26.5.0.17F42:system_sdks"],
        ":xcode_27_0_0_27A5218g": ["//system_sdks/27.0.0.27A5218g:system_sdks"],
        "//conditions:default": [],
    }),
)

swift_library_group(
    name = "testonly_system_sdks",
    testonly = True,
    deps = select({
        ":xcode_16_3_0_16E140": ["//system_sdks/16.3.0.16E140:testonly_system_sdks"],
        ":xcode_26_0_1_17A400": ["//system_sdks/26.0.1.17A400:testonly_system_sdks"],
        ":xcode_26_5_0_17F42": ["//system_sdks/26.5.0.17F42:testonly_system_sdks"],
        ":xcode_27_0_0_27A5218g": ["//system_sdks/27.0.0.27A5218g:testonly_system_sdks"],
        "//conditions:default": [],
    }),
)
