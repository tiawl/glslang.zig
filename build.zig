const std = @import("std");
const build_zig_zon = @import("build.zig.zon");
const toolbox = @import("toolbox");
const VerboseBuilder = toolbox.VerboseBuilder;

fn updateFn(pkg_builder: *VerboseBuilder) !void {
    try pkg_builder.remove(&.{"glslang"});
    try pkg_builder.make(&.{"glslang"});
    try pkg_builder.make(&.{ "glslang", "glslang" });
    try pkg_builder.make(&.{ "glslang", "SPIRV" });
    try pkg_builder.make(&.{ "glslang", "StandAlone" });

    const glslang_dep = pkg_builder.verboseDependency("glslang");
    var glslang_builder = VerboseBuilder.initFromDependency(glslang_dep);

    _ = try glslang_builder.run(&.{ "python3", "build_info.py", ".", "-i", "build_info.h.tmpl", "-o", pkg_builder.resolve(&.{ "glslang", "build_info.h" }) }, glslang_builder.ptrCwd().*);
    _ = try glslang_builder.run(&.{ "python3", "gen_extension_headers.py", ".", "-i", pkg_builder.resolve(&.{ "glslang", "ExtensionHeaders" }), "-o", pkg_builder.resolve(&.{ "glslang", "glsl_intrinsic_header.h" }) }, glslang_builder.ptrCwd().*);

    for ([_][]const u8{ "glslang", "SPIRV", "StandAlone" }) |dir| {
        while (try glslang_builder.walk(&.{dir})) |entry| {
            switch (entry.kind) {
                .file => if (toolbox.isCOrCpp11File(entry.basename)) {
                    try pkg_builder.copy(&.{ "glslang", dir, entry.path }, &glslang_builder, &.{ dir, entry.path });
                },
                .directory => try pkg_builder.make(&.{ "glslang", dir, entry.path }),
                else => {},
            }
        }
    }
}

fn buildFn(pkg_builder: *VerboseBuilder) !void {
    const lib = pkg_builder.addLibrary("glslang");

    const flags = [_][]const u8{ "-DENABLE_HLSL", "-fno-sanitize=undefined" };

    pkg_builder.addInclude(lib, &.{"glslang"});
    pkg_builder.addInclude(lib, &.{ "glslang", "glslang" });
    pkg_builder.addInclude(lib, &.{ "glslang", "SPIRV" });
    pkg_builder.addInclude(lib, &.{ "glslang", "StandAlone" });

    for ([_][]const u8{ "glslang", "SPIRV" }) |dir| {
        while (try pkg_builder.walk(&.{ "glslang", dir })) |*entry| {
            if (toolbox.isCHeader(entry.basename)) pkg_builder.installHeader(lib, &.{ "glslang", dir, entry.path }, &.{ dir, entry.path });
        }
    }

    pkg_builder.linkLibCpp(lib);

    while (try pkg_builder.walk(&.{"glslang"})) |entry| {
        switch (entry.kind) {
            .file => {
                if (std.fs.path.dirname(entry.path)) |dirname| {
                    var it = try std.fs.path.componentIterator(dirname);
                    if (std.mem.eql(u8, it.next().?.name, "glslang")) {
                        if (it.next()) |component| {
                            if (std.mem.eql(u8, component.name, "OSDependent")) continue;
                        }
                    }
                }
                if (std.mem.eql(u8, entry.basename, "StandAlone.cpp")) continue;
                if (toolbox.isCppSource(entry.basename)) {
                    pkg_builder.addCSource(lib, &.{ "glslang", entry.path }, &flags);
                }
            },
            else => {},
        }
    }

    const os = switch (pkg_builder.getOs()) {
        .linux => "Unix",
        .windows => "Windows",
        else => return error.UnsupportedOs,
    };

    while (try pkg_builder.iterate(&.{ "glslang", "glslang", "OSDependent", os })) |entry| {
        switch (entry.kind) {
            .file => {
                if (toolbox.isCppSource(entry.name)) {
                    pkg_builder.addCSource(lib, &.{ "glslang", "glslang", "OSDependent", os, entry.name }, &flags);
                }
            },
            else => {},
        }
    }

    const validator = pkg_builder.addExecutable("glslangValidator");
    pkg_builder.linkLibC(validator);
    pkg_builder.linkLibrary(validator, lib);
    pkg_builder.addCSource(validator, &.{ "glslang", "StandAlone", "StandAlone.cpp" }, &.{ "-std=c++17", "-fno-exceptions", "-fno-exceptions" });
    pkg_builder.addInclude(validator, &.{"glslang"});
    pkg_builder.addInclude(validator, &.{ "glslang", "glslang" });
    pkg_builder.addCMacro(validator, "ENABLE_OPT", if (pkg_builder.option(bool, true, "enable-opt", "Enables spirv-opt capability if present")) "1" else "0");
    pkg_builder.installArtifact(validator);

    const glslang_run_cmd = pkg_builder.addRunArtifact(validator);
    pkg_builder.dependOn(&glslang_run_cmd.step, pkg_builder.getInstallStep());
    pkg_builder.addArgs(glslang_run_cmd, pkg_builder.getArgs());
    const glslang_run_step = pkg_builder.step("glslangValidator", "Run glslang");
    pkg_builder.dependOn(glslang_run_step, &glslang_run_cmd.step);

    pkg_builder.installArtifact(lib);
}

pub fn build(builder: *std.Build) !void {
    var pkg_builder = try VerboseBuilder.init(builder, build_zig_zon, buildFn, updateFn);

    try pkg_builder.fetch(build_zig_zon);
    try pkg_builder.update();
    try pkg_builder.build();
}
