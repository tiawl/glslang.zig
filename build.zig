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

  try toolbox.clone (builder, "https://github.com/KhronosGroup/glslang.git",
    "vulkan-sdk-" ++ pkg.version ++ ".0", path.glslang);

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
    if (!toolbox.isCHeader (entry.name) and entry.kind == .file)
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

  const flags = [_][] const u8 { "-DENABLE_HLSL", "-fno-sanitize=undefined", };

  for ([_][] const u8 {
    "glslang",
    try std.fs.path.join (builder.allocator, &.{ "glslang", "glslang", }),
    try std.fs.path.join (builder.allocator, &.{ "glslang", "SPIRV", }),
    try std.fs.path.join (builder.allocator, &.{ "glslang", "StandAlone", }),
  }) |include| toolbox.addInclude (lib, include);

  toolbox.addHeader (lib, path.glslang_in, "glslang", &.{ ".h", });
  toolbox.addHeader (lib, try std.fs.path.join (builder.allocator,
    &.{ path.glslang, "SPIRV", }), "SPIRV", &.{ ".h", });

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
      .file => {
        if (toolbox.isCppSource (entry.basename))
          try toolbox.addSource (lib, path.glslang, entry.path, &flags);
      },
      else => {},
    }
  }

  builder.installArtifact (lib);
}
