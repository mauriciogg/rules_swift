features(
  trigger_controller = "snapci", # make sure you have on_cool() defined if you turn on this flag
)

MAC_EXEC_REQUIREMENTS = {
    "os": "macos",
    "arch": "arm64",
    "vm_image": "snap-macos",
    # Newest release this VM image offers (`snapci config validate` lists them).
    # rules_swift 4.x precompiles the SDK's explicit modules through the upstream
    # `system_sdk` extension, and Xcode 16.0's SDK cannot build them: its
    # prebuilt Swift modules are x86_64-only, so SwiftCompileModuleInterface
    # fails with "module 'Swift' was created for incompatible target
    # x86_64-apple-macosx15.0".
    "xcode_version": "26.0_17A400"
}

on_pr(
    execs = [
        exec("run_cool", params = {
            "IS_COOL": False,
        }),
    ],
)

on_cool(
    execs = [
        exec("run_cool"),
    ],
)

on_comment(
    name = "on_comment_deploy",
    body = match.command("/deploy"),
    description = "Manually run a deploy command to dev GCS bucket",
    execs = [
        exec("run_deploy"),
    ],
)

on_comment(
    name = "on_comment_notcool",
    body = match.command("/notcool"),
    description = "Manually run cool script to upload ruleset archive to prod GCS bucket",
    execs = [
        exec("run_cool"),
    ],
)

run(
    name = "run_cool",
    description = "Runs the cool process",
    steps = [
        process("snapci/cool.sh"),
    ],
    params = {
        "IS_COOL": param.bool(default = True),
    },
    exec_requirements = MAC_EXEC_REQUIREMENTS,
)

run(
    name = "run_deploy",
    description = "Runs the deploy dev process",
    steps = [
        process("snapci/deploy.sh"),
    ],
    exec_requirements = MAC_EXEC_REQUIREMENTS,
)

