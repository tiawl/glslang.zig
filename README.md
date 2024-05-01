# glslang.zig

This is a fork of [KhronosGroup/glslang][1] packaged for [Zig][2]

## Why this fork ?

The intention under this fork is to package [KhronosGroup/glslang][1] for [Zig][2]. So:
* Unnecessary files have been deleted,
* The build system has been replaced with `build.zig`,
* A cron runs every day to check [KhronosGroup/glslang][1]. Then it updates this repository if a new release is available.

Here the repositories' version used by this fork:
* [KhronosGroup/glslang](https://github.com/tiawl/glslang.zig/blob/trunk/.versions/glslang)

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
  -Dfetch   Update .versions folder and build.zig.zon then stop execution
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
