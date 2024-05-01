# glslang.zig

This is a fork of [KhronosGroup/glslang](https://github.com/KhronosGroup/glslang) packaged for @ziglang

## Why this fork ?

The intention under this fork is to package [KhronosGroup/glslang](https://github.com/KhronosGroup/glslang) for @ziglang. So:
* Unnecessary files have been deleted,
* The build system has been replaced with `build.zig`,
* A cron runs every day to check [KhronosGroup/glslang](https://github.com/KhronosGroup/glslang). Then it updates this repository if a new release is available.

Here the repositories' version used by this fork:
* [KhronosGroup/glslang](https://github.com/tiawl/glslang.zig/blob/trunk/.versions/glslang)

## CICD reminder

These repositories are automatically updated when a new release is available:
* [tiawl/shaderc.zig](https://github.com/tiawl/shaderc.zig)

This repository is automatically updated when a new release is available from these repositories:
* [KhronosGroup/glslang](https://github.com/KhronosGroup/glslang)
* [tiawl/toolbox](https://github.com/tiawl/toolbox)
* [tiawl/spaceporn-dep-action-bot](https://github.com/tiawl/spaceporn-dep-action-bot)
* [tiawl/spaceporn-dep-action-ci](https://github.com/tiawl/spaceporn-dep-action-ci)
* [tiawl/spaceporn-dep-action-cd-ping](https://github.com/tiawl/spaceporn-dep-action-cd-ping)
* [tiawl/spaceporn-dep-action-cd-pong](https://github.com/tiawl/spaceporn-dep-action-cd-pong)

## `zig build` options

These additional options have been implemented for maintainability tasks:
```
  -Dfetch   Update .versions folder and build.zig.zon then stop execution
  -Dupdate  Update binding
```

## License

The unprotected parts of this repository are under MIT License. For everything else, see with their respective owners.
