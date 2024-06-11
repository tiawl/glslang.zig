# glslang.zig

This is a fork of [KhronosGroup/glslang][1] packaged for [Zig][2]

## Why this fork ?

The intention under this fork is to package [KhronosGroup/glslang][1] for [Zig][2]. So:
* Unnecessary files have been deleted,
* The build system has been replaced with `build.zig`,
* A cron runs every day to check [KhronosGroup/glslang][1]. Then it updates this repository if a new release is available.

## How to use it

The goal of this repository is not to provide a [Zig][2] binding for [KhronosGroup/glslang][1]. There are at least as many legit ways as possible to make a binding as there are active accounts on Github. So you are not going to find an answer for this question here. The point of this repository is to abstract the [KhronosGroup/glslang][1] compilation process with [Zig][2] (which is not new comers friendly and not easy to maintain) to let you focus on your application. So you can use **glslang.zig**:
- as raw (no available example, open an issue if you are interested in, we will be happy to help you),
- as a daily updated interface for your [Zig][2] binding of [KhronosGroup/glslang][1] (again: no available example).

## Important note

The current usage of this repository is centered around [tiawl/shaderc.zig][3] compilation. So for your usage it could break because some files have been filtered in the process. If it happens, open an issue: this repository is open to potential usage evolution.

## Dependencies

The [Zig][2] part of this package is relying on the latest [Zig][2] release (0.13.0) and will only be updated for the next one (so for the 0.14.0).

Here the repositories' version used by this fork:
* [KhronosGroup/glslang](https://github.com/tiawl/glslang.zig/blob/trunk/.references/glslang)

## CICD reminder

These repositories are automatically updated when a new release is available:
* [tiawl/shaderc.zig][3]

This repository is automatically updated when a new release is available from these repositories:
* [KhronosGroup/glslang][1]
* [tiawl/toolbox][4]
* [tiawl/spaceporn-action-bot][5]
* [tiawl/spaceporn-action-ci][6]
* [tiawl/spaceporn-action-cd-ping][7]
* [tiawl/spaceporn-action-cd-pong][8]

## `zig build` options

These additional options have been implemented for maintainability tasks:
```
  -Dfetch   Update .references folder and build.zig.zon then stop execution
  -Dupdate  Update binding
```

## License

The unprotected parts of this repository are under MIT License. For everything else, see with their respective owners.

[1]:https://github.com/KhronosGroup/glslang
[2]:https://github.com/ziglang/zig
[3]:https://github.com/tiawl/shaderc.zig
[4]:https://github.com/tiawl/toolbox
[5]:https://github.com/tiawl/spaceporn-action-bot
[6]:https://github.com/tiawl/spaceporn-action-ci
[7]:https://github.com/tiawl/spaceporn-action-cd-ping
[8]:https://github.com/tiawl/spaceporn-action-cd-pong
