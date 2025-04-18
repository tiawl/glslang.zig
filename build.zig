const std = @import("std");
const toolbox_pkg = @import("toolbox");
const Toolbox = toolbox_pkg.Toolbox;

const Paths = struct {
    __glslang: []const u8,
    __glslang_in: []const u8,

    fn getGlslang(self: @This()) []const u8 {
        return self.__glslang;
    }

    fn getGlslangIn(self: @This()) []const u8 {
        return self.__glslang_in;
    }

    fn init(toolbox: *Toolbox) !@This() {
        const glslang_path = try toolbox.buildRootJoin(&.{
            "glslang",
        });

        return .{
            .__glslang = glslang_path,
            .__glslang_in = toolbox.pathJoin(&.{
                glslang_path, "glslang",
            }),
        };
    }
};

fn update(toolbox: *Toolbox, path: *const Paths) !void {
    std.fs.deleteTreeAbsolute(path.getGlslang()) catch |err| {
        switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
    };

    try toolbox.clone(.glslang, path.getGlslang());

    try toolbox.run(.{
        .argv = &[_][]const u8{
            "python3",
            toolbox.pathJoin(&.{
                path.getGlslang(), "build_info.py",
            }),
            path.getGlslang(), "-i",
            toolbox.pathJoin(&.{
                path.getGlslang(), "build_info.h.tmpl",
            }),
            "-o",
            toolbox.pathJoin(&.{
                path.getGlslangIn(), "build_info.h",
            }),
        },
    });

    try toolbox.run(.{
        .argv = &[_][]const u8{
            "python3",
            toolbox.pathJoin(&.{
                path.getGlslang(), "gen_extension_headers.py",
            }),
            "-i",
            toolbox.pathJoin(&.{
                path.getGlslangIn(), "ExtensionHeaders",
            }),
            "-o",
            toolbox.pathJoin(&.{
                path.getGlslangIn(), "glsl_intrinsic_header.h",
            }),
        },
    });

    var glslang_dir = try std.fs.openDirAbsolute(path.getGlslang(), .{
        .iterate = true,
    });
    defer glslang_dir.close();

    var it = glslang_dir.iterate();
    while (try it.next()) |*entry| {
        if (!std.mem.eql(u8, "SPIRV", entry.name) and !std.mem.eql(u8, "StandAlone", entry.name) and !std.mem.eql(u8, "glslang", entry.name)) {
            try std.fs.deleteTreeAbsolute(toolbox.pathJoin(&.{
                path.getGlslang(), entry.name,
            }));
        }
    }

    const standalone_path = toolbox.pathJoin(&.{
        path.getGlslang(), "StandAlone",
    });

    var standalone_dir = try std.fs.openDirAbsolute(standalone_path, .{
        .iterate = true,
    });
    defer standalone_dir.close();

    it = standalone_dir.iterate();
    while (try it.next()) |*entry| {
        if (std.mem.startsWith(u8, entry.name, "StandAlone")) continue;
        if (!toolbox_pkg.isCHeader(entry.name) and entry.kind == .file) {
            try std.fs.deleteFileAbsolute(toolbox.pathJoin(&.{
                standalone_path, entry.name,
            }));
        }
    }

    try toolbox.clean(&.{
        "glslang",
    }, &.{
        "glsl",
    });
}

const FromZon = toolbox_pkg.Repositories(.{
    .toolbox,
});

const DuringExec = toolbox_pkg.Repositories(.{
    .glslang,
});

pub fn build(builder: *std.Build) !void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    var toolbox = try Toolbox.init(FromZon, DuringExec, builder, optimize, .glslang_zig, "0xe15c80cea022542", &.{
        "glslang",
    }, .{
        .toolbox = .{
            .name = "tiawl/toolbox",
            .host = .github,
            .ref = .tag,
        },
    }, .{
        .glslang = .{
            .name = "KhronosGroup/glslang",
            .host = .github,
            .ref = .commit,
        },
    });
    defer toolbox.deinit();

    const path = try Paths.init(&toolbox);

    if (toolbox.getUpdate()) try update(&toolbox, &path);

    const lib = builder.addStaticLibrary(.{
        .name = "glslang",
        .root_source_file = builder.addWriteFiles().add("empty.c", ""),
        .target = target,
        .optimize = optimize,
    });

    const flags = [_][]const u8{
        "-DENABLE_HLSL", "-fno-sanitize=undefined",
    };

    for ([_][]const u8{
        "glslang",
        builder.pathJoin(&.{
            "glslang", "glslang",
        }),
        builder.pathJoin(&.{
            "glslang", "SPIRV",
        }),
        builder.pathJoin(&.{
            "glslang", "StandAlone",
        }),
    }) |include| {
        toolbox.addInclude(lib, include);
    }

    toolbox.addHeader(lib, path.getGlslangIn(), "glslang", &.{
        ".h",
    });

    toolbox.addHeader(lib, builder.pathJoin(&.{
        path.getGlslang(), "SPIRV",
    }), "SPIRV", &.{
        ".h",
    });

    lib.linkLibCpp();

    var glslang_dir = try std.fs.openDirAbsolute(path.getGlslang(), .{
        .iterate = true,
    });
    defer glslang_dir.close();

    var walker = try glslang_dir.walk(builder.allocator);
    defer walker.deinit();

    walk: while (try walker.next()) |*entry| {
        switch (entry.kind) {
            .file => {
                var it = try std.fs.path.componentIterator(entry.path);
                while (it.next()) |*component| {
                    if (std.mem.eql(u8, component.name, "OSDependent")) continue :walk;
                }
                if (std.mem.startsWith(u8, entry.basename, "StandAlone")) continue :walk;
                if (toolbox_pkg.isCppSource(entry.basename)) {
                    try toolbox.addSource(lib, path.getGlslang(), entry.path, &flags);
                }
            },
            else => {},
        }
    }

    const os = switch (target.result.os.tag) {
        .linux => "Unix",
        .windows => "Windows",
        else => return error.UnsupportedOs,
    };

    const os_path = builder.pathJoin(&.{
        path.getGlslangIn(), "OSDependent", os,
    });

    var os_dir = try std.fs.openDirAbsolute(os_path, .{
        .iterate = true,
    });
    defer os_dir.close();

    var it = os_dir.iterate();

    while (try it.next()) |*entry| {
        switch (entry.kind) {
            .file => {
                if (toolbox_pkg.isCppSource(entry.name)) {
                    try toolbox.addSource(lib, os_path, entry.name, &flags);
                }
            },
            else => {},
        }
    }

    const exe = builder.addExecutable(.{
        .name = "glslangValidator",
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibCpp();
    exe.linkLibrary(lib);
    exe.addCSourceFiles(.{
        .root = .{
            .cwd_relative = toolbox.pathJoin(&.{
                path.getGlslang(), "StandAlone",
            }),
        },
        .files = &.{
            "StandAlone.cpp",
        },
        .flags = &[_][]const u8{
            "-std=c++17", "-fno-exceptions", "-fno-exceptions",
        },
    });
    exe.addIncludePath(.{
        .cwd_relative = path.getGlslang(),
    });
    exe.addIncludePath(.{
        .cwd_relative = path.getGlslangIn(),
    });
    exe.root_module.addCMacro("ENABLE_OPT", if (builder.option(bool, "enable-opt", "Enables spirv-opt capability if present") orelse true) "1" else "0");
    builder.installArtifact(exe);
    const glslang_run_cmd = builder.addRunArtifact(exe);
    glslang_run_cmd.step.dependOn(builder.getInstallStep());
    if (builder.args) |args| glslang_run_cmd.addArgs(args);
    const glslang_run_step = builder.step("glslangValidator", "Run glslang");
    glslang_run_step.dependOn(&glslang_run_cmd.step);

    builder.installArtifact(lib);
}
