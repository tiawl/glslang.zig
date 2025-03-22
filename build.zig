const std = @import("std");
const toolbox = @import("toolbox");

const Paths = struct {
    __glslang: []const u8,
    __glslang_in: []const u8,

    fn getGlslang(self: @This()) []const u8 {
        return self.__glslang;
    }

    fn getGlslangIn(self: @This()) []const u8 {
        return self.__glslang_in;
    }

    fn init() !@This() {
        const glslang_path = try toolbox.instance().getBuilder().build_root.join(toolbox.instance().getBuilder().allocator, &.{
            "glslang",
        });

        return .{
            .__glslang = glslang_path,
            .__glslang_in = toolbox.instance().ptrBuilder().pathJoin(&.{
                glslang_path, "glslang",
            }),
        };
    }
};

fn update(path: *const Paths, dependencies: *const toolbox.Dependencies) !void {
    std.fs.deleteTreeAbsolute(path.getGlslang()) catch |err| {
        switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
    };

    try dependencies.clone("glslang", path.getGlslang());

    try toolbox.instance().run(.{
        .argv = &[_][]const u8{
            "python3",
            toolbox.instance().ptrBuilder().pathJoin(&.{
                path.getGlslang(), "build_info.py",
            }),
            path.getGlslang(),
            "-i",
            toolbox.instance().ptrBuilder().pathJoin(&.{
                path.getGlslang(), "build_info.h.tmpl",
            }),
            "-o",
            toolbox.instance().ptrBuilder().pathJoin(&.{
                path.getGlslangIn(), "build_info.h",
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
            try std.fs.deleteTreeAbsolute(toolbox.instance().ptrBuilder().pathJoin(&.{
                path.getGlslang(), entry.name,
            }));
        }
    }

    const standalone_path = toolbox.instance().ptrBuilder().pathJoin(&.{
        path.getGlslang(), "StandAlone",
    });

    var standalone_dir = try std.fs.openDirAbsolute(standalone_path, .{
        .iterate = true,
    });
    defer standalone_dir.close();

    it = standalone_dir.iterate();
    while (try it.next()) |*entry| {
        if (!toolbox.isCHeader(entry.name) and entry.kind == .file) {
            try std.fs.deleteFileAbsolute(toolbox.instance().ptrBuilder().pathJoin(&.{
                standalone_path, entry.name,
            }));
        }
    }

    try toolbox.instance().clean(&.{
        "glslang",
    }, &.{});
}

pub fn build(builder: *std.Build) !void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    toolbox.init(builder, optimize);
    defer toolbox.deinit();
    const dependencies = try toolbox.Dependencies.init(.glslang_zig, "0xe15c80cea022542", &.{
        "glslang",
    }, .{
        .toolbox = .{
            .name = "tiawl/toolbox",
            .host = toolbox.Repository.Host.github,
            .ref = toolbox.Repository.Reference.tag,
        },
    }, .{
        .glslang = .{
            .name = "KhronosGroup/glslang",
            .host = toolbox.Repository.Host.github,
            .ref = toolbox.Repository.Reference.commit,
        },
    });

    const path = try Paths.init();

    if (toolbox.instance().ptrBuilder().option(bool, "update", "Update binding") orelse false) {
        try update(&path, &dependencies);
    }

    const lib = toolbox.instance().ptrBuilder().addStaticLibrary(.{
        .name = "glslang",
        .root_source_file = toolbox.instance().ptrBuilder().addWriteFiles().add("empty.c", ""),
        .target = target,
        .optimize = optimize,
    });

    const flags = [_][]const u8{
        "-DENABLE_HLSL", "-fno-sanitize=undefined",
    };

    for ([_][]const u8{
        "glslang",
        toolbox.instance().ptrBuilder().pathJoin(&.{
            "glslang", "glslang",
        }),
        toolbox.instance().ptrBuilder().pathJoin(&.{
            "glslang", "SPIRV",
        }),
        toolbox.instance().ptrBuilder().pathJoin(&.{
            "glslang", "StandAlone",
        }),
    }) |include| {
        toolbox.instance().addInclude(lib, include);
    }

    toolbox.instance().addHeader(lib, path.getGlslangIn(), "glslang", &.{
        ".h",
    });

    toolbox.instance().addHeader(lib, toolbox.instance().ptrBuilder().pathJoin(&.{
        path.getGlslang(), "SPIRV",
    }), "SPIRV", &.{
        ".h",
    });

    lib.linkLibCpp();

    var glslang_dir = try std.fs.openDirAbsolute(path.getGlslang(), .{
        .iterate = true,
    });
    defer glslang_dir.close();

    var walker = try glslang_dir.walk(toolbox.instance().getBuilder().allocator);
    defer walker.deinit();

    walk: while (try walker.next()) |*entry| {
        switch (entry.kind) {
            .file => {
                var it = try std.fs.path.componentIterator(entry.path);
                while (it.next()) |*component| {
                    if (std.mem.eql(u8, component.name, "OSDependent")) continue :walk;
                }
                if (toolbox.isCppSource(entry.basename)) {
                    try toolbox.instance().addSource(lib, path.getGlslang(), entry.path, &flags);
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

    const os_path = toolbox.instance().ptrBuilder().pathJoin(&.{
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
                if (toolbox.isCppSource(entry.name)) {
                    try toolbox.instance().addSource(lib, os_path, entry.name, &flags);
                }
            },
            else => {},
        }
    }

    toolbox.instance().ptrBuilder().installArtifact(lib);
}
