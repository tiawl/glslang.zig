const std = @import ("std");
const toolbox = @import ("toolbox");
const pkg = .{ .name = "glslang.zig", .version = "1.3.280", };

const Paths = struct
{
  glslang: [] const u8 = undefined,
  glslang_in: [] const u8 = undefined,
};

fn update (builder: *std.Build, path: *const Paths,
  target: *const std.Build.ResolvedTarget) !void
{
  std.fs.deleteTreeAbsolute (path.glslang) catch |err|
  {
    switch (err)
    {
      error.FileNotFound => {},
      else => return err,
    }
  };

  try toolbox.run (builder, .{ .argv = &[_][] const u8 { "git", "clone",
    "--branch", "vulkan-sdk-" ++ pkg.version ++ ".0", "--depth", "1",
    "https://github.com/KhronosGroup/glslang.git", path.glslang, }, });

  try toolbox.run (builder, .{ .argv = &[_][] const u8 { "python3",
    try std.fs.path.join (builder.allocator,
      &.{ path.glslang, "build_info.py", }), path.glslang,
    "-i", try std.fs.path.join (builder.allocator,
      &.{ path.glslang, "build_info.h.tmpl", }),
    "-o", try std.fs.path.join (builder.allocator,
      &.{ path.glslang_in, "build_info.h", }),
  }, });

  var glslang_dir =
    try std.fs.openDirAbsolute (path.glslang, .{ .iterate = true, });
  defer glslang_dir.close ();

  var it = glslang_dir.iterate ();
  while (try it.next ()) |entry|
  {
    if (!std.mem.eql (u8, "SPIRV", entry.name) and
      !std.mem.eql (u8, "StandAlone", entry.name) and
      !std.mem.eql (u8, "glslang", entry.name))
        try std.fs.deleteTreeAbsolute (try std.fs.path.join (
          builder.allocator, &.{ path.glslang, entry.name, }));
  }

  const osdependent_path = try std.fs.path.join (builder.allocator,
    &.{ path.glslang_in, "OSDependent", });
  var os: [] const u8 = undefined;

  switch (target.result.os.tag)
  {
    .linux => os = "Unix",
    .windows => os = "Windows",
    else => return error.UnsupportedOs,
  }

  var osdependent_dir =
    try std.fs.openDirAbsolute (osdependent_path, .{ .iterate = true, });
  defer osdependent_dir.close ();

  it = osdependent_dir.iterate ();
  while (try it.next ()) |entry|
  {
    if (!std.mem.eql (u8, os, entry.name) and entry.kind == .directory)
      try std.fs.deleteTreeAbsolute (try std.fs.path.join (builder.allocator,
        &.{ osdependent_path, entry.name, }));
  }

  const standalone_path = try std.fs.path.join (builder.allocator,
    &.{ path.glslang, "StandAlone", });

  var standalone_dir = try std.fs.openDirAbsolute (standalone_path,
    .{ .iterate = true, });
  defer standalone_dir.close ();

  it = standalone_dir.iterate ();
  while (try it.next ()) |entry|
  {
    if (!toolbox.is_c_header_file (entry.name) and entry.kind == .file)
      try std.fs.deleteFileAbsolute (try std.fs.path.join (builder.allocator,
        &.{ standalone_path, entry.name, }));
  }

  var walker = try glslang_dir.walk (builder.allocator);
  defer walker.deinit ();

  while (try walker.next ()) |entry|
  {
    switch (entry.kind)
    {
      .file => {
        const file = try std.fs.path.join (builder.allocator,
          &.{ path.glslang, entry.path, });
        if (std.mem.endsWith (u8, entry.basename, ".txt"))
          try std.fs.deleteFileAbsolute (file);
      },
      else => {},
    }
  }
}

pub fn build (builder: *std.Build) !void
{
  const target = builder.standardTargetOptions (.{});
  const optimize = builder.standardOptimizeOption (.{});

  var path: Paths = .{};
  path.glslang =
    try builder.build_root.join (builder.allocator, &.{ "glslang", });
  path.glslang_in =
    try std.fs.path.join (builder.allocator, &.{ path.glslang, "glslang", });

  if (builder.option (bool, "update", "Update binding") orelse false)
    try update (builder, &path, &target);

  const lib = builder.addStaticLibrary (.{
    .name = "glslang",
    .root_source_file = builder.addWriteFiles ().add ("empty.c", ""),
    .target = target,
    .optimize = optimize,
  });

  var sources = try std.BoundedArray ([] const u8, 256).init (0);

  for ([_] std.Build.LazyPath {
    .{ .path = "glslang", },
    .{ .path = try std.fs.path.join (builder.allocator,
      &.{ "glslang", "glslang", }), },
    .{ .path = try std.fs.path.join (builder.allocator,
      &.{ "glslang", "SPIRV", }), },
    .{ .path = try std.fs.path.join (builder.allocator,
      &.{ "glslang", "StandAlone", }), },
  }) |include| {
    std.debug.print ("[glslang include] {s}\n",
      .{ include.getPath (builder), });
    lib.addIncludePath (include);
  }

  lib.installHeadersDirectory (.{ .path = path.glslang_in, }, "glslang",
    .{ .include_extensions = &.{ ".h", }, });
  std.debug.print ("[glslang headers dir] {s}\n", .{ path.glslang_in, });

  const spirv_path = try std.fs.path.join (builder.allocator,
    &.{ path.glslang, "SPIRV", });
  lib.installHeadersDirectory (.{ .path = spirv_path, }, "SPIRV",
    .{ .include_extensions = &.{ ".h", }, });
  std.debug.print ("[glslang headers dir] {s}\n", .{ spirv_path, });

  lib.linkLibCpp ();

  var glslang_dir = try std.fs.openDirAbsolute (path.glslang,
    .{ .iterate = true, });
  defer glslang_dir.close ();

  var walker = try glslang_dir.walk (builder.allocator);
  defer walker.deinit ();

  while (try walker.next ()) |entry|
  {
    switch (entry.kind)
    {
      .file => if (toolbox.is_cpp_source_file (entry.basename))
      {
        const source_path = try std.fs.path.join (builder.allocator,
          &.{ path.glslang, entry.path, });
        std.debug.print ("[glslang source] {s}\n", .{ source_path, });
        try sources.append (try std.fs.path.relative (builder.allocator,
          builder.build_root.path.?, source_path));
      },
      else => {},
    }
  }

  lib.addCSourceFiles (.{
    .files = sources.slice (),
    .flags = &.{ "-DENABLE_HLSL", "-fno-sanitize=undefined", },
  });

  builder.installArtifact (lib);
}
