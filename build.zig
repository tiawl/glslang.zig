const std = @import ("std");
const toolbox = @import ("toolbox");
const pkg = .{ .name = "glslang.zig", .version = "1.3.280", };

const Paths = struct
{
  include: [] const u8 = undefined,
  glslang: [] const u8 = undefined,
};

fn update (builder: *std.Build, path: *const Paths, target: *const std.Build.ResolvedTarget) !void
{
  std.fs.deleteTreeAbsolute (path.include) catch |err|
  {
    switch (err)
    {
      error.FileNotFound => {},
      else => return err,
    }
  };

  try toolbox.run (builder, .{ .argv = &[_][] const u8 { "git", "clone", "https://github.com/KhronosGroup/glslang.git", path.include, }, });
  try toolbox.run (builder, .{ .argv = &[_][] const u8 { "git", "-C", path.include, "checkout", "vulkan-sdk-" ++ pkg.version ++ ".0", }, });

  try toolbox.run (builder, .{ .argv = &[_][] const u8 { "python3",
    try std.fs.path.join (builder.allocator, &.{ path.include, "build_info.py", }), path.include,
    "-i", try std.fs.path.join (builder.allocator, &.{ path.include, "build_info.h.tmpl", }),
    "-o", try std.fs.path.join (builder.allocator, &.{ path.glslang, "build_info.h", }),
  }, });

  var include_dir = try std.fs.openDirAbsolute (path.include, .{ .iterate = true, });
  defer include_dir.close ();

  var it = include_dir.iterate ();
  while (try it.next ()) |entry|
  {
    if (!std.mem.eql (u8, "SPIRV", entry.name) and
      !std.mem.eql (u8, "StandAlone", entry.name) and
      !std.mem.eql (u8, "glslang", entry.name))
        try std.fs.deleteTreeAbsolute (try std.fs.path.join (builder.allocator, &.{ path.include, entry.name, }));
  }

  const osdependent_path = try std.fs.path.join (builder.allocator, &.{ path.glslang, "OSDependent", });
  var os: [] const u8 = undefined;

  switch (target.result.os.tag)
  {
    .linux => os = "Unix",
    .windows => os = "Windows",
    else => return error.UnsupportedOs,
  }

  var osdependent_dir = try std.fs.openDirAbsolute (osdependent_path, .{ .iterate = true, });
  defer osdependent_dir.close ();

  it = osdependent_dir.iterate ();
  while (try it.next ()) |entry|
  {
    if (!std.mem.eql (u8, os, entry.name) and entry.kind == .directory)
      try std.fs.deleteTreeAbsolute (try std.fs.path.join (builder.allocator, &.{ osdependent_path, entry.name, }));
  }

  const standalone_path = try std.fs.path.join (builder.allocator, &.{ path.include, "StandAlone", });

  var standalone_dir = try std.fs.openDirAbsolute (standalone_path, .{ .iterate = true, });
  defer standalone_dir.close ();

  it = standalone_dir.iterate ();
  while (try it.next ()) |entry|
  {
    if (!toolbox.is_c_header_file (entry.name) and entry.kind == .file)
      try std.fs.deleteFileAbsolute (try std.fs.path.join (builder.allocator, &.{ standalone_path, entry.name, }));
  }

  var walker = try include_dir.walk (builder.allocator);
  defer walker.deinit ();

  while (try walker.next ()) |entry|
  {
    switch (entry.kind)
    {
      .file => {
                 const file = try std.fs.path.join (builder.allocator, &.{ path.include, entry.path, });
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
  path.include = try builder.build_root.join (builder.allocator, &.{ "include", });
  path.glslang = try std.fs.path.join (builder.allocator, &.{ path.include, "glslang", });

  if (builder.option (bool, "update", "Update binding") orelse false) try update (builder, &path, &target);

  const lib = builder.addStaticLibrary (.{
    .name = "glslang",
    .root_source_file = builder.addWriteFiles ().add ("empty.c", ""),
    .target = target,
    .optimize = optimize,
  });

  var sources = try std.BoundedArray ([] const u8, 256).init (0);

  for ([_] std.Build.LazyPath {
      .{ .path = ".", },
      .{ .path = "include", },
      .{ .path = try std.fs.path.join (builder.allocator, &.{ "include", "glslang", }), },
      .{ .path = try std.fs.path.join (builder.allocator, &.{ "include", "SPIRV", }), },
      .{ .path = try std.fs.path.join (builder.allocator, &.{ "include", "StandAlone", }), },
    }) |include|
  {
    std.debug.print ("[glslang include] {s}\n", .{ include.getPath (builder), });
    lib.addIncludePath (include);
  }

  lib.installHeadersDirectory (.{ .path = path.glslang, }, "glslang", .{ .include_extensions = &.{ ".h", }, });
  std.debug.print ("[glslang headers dir] {s}\n", .{ path.glslang, });

  const spirv_path = try std.fs.path.join (builder.allocator, &.{ path.include, "SPIRV", });
  lib.installHeadersDirectory (.{ .path = spirv_path, }, "SPIRV", .{ .include_extensions = &.{ ".h", }, });
  std.debug.print ("[glslang headers dir] {s}\n", .{ spirv_path, });

  lib.linkLibCpp ();

  var include_dir = try std.fs.openDirAbsolute (path.include, .{ .iterate = true, });
  defer include_dir.close ();

  var walker = try include_dir.walk (builder.allocator);
  defer walker.deinit ();

  while (try walker.next ()) |entry|
  {
    switch (entry.kind)
    {
      .file => if (toolbox.is_cpp_source_file (entry.basename))
               {
                 try sources.append (try std.fs.path.join (builder.allocator, &.{ "include", builder.dupe (entry.path), }));
                 std.debug.print ("[glslang source] {s}\n", .{ try std.fs.path.join (builder.allocator, &.{ path.include, entry.path, }), });
               },
      else => {},
    }
  }

  lib.addCSourceFiles (.{
    .files = sources.slice (),
    .flags = &.{ "-DENABLE_HLSL", },
  });

  builder.installArtifact (lib);
}
