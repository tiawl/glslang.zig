const std = @import ("std");
const toolbox = @import ("toolbox");

const Paths = struct
{
  // prefixed attributes
  __glslang: [] const u8 = undefined,
  __glslang_in: [] const u8 = undefined,

  // mandatory getters
  pub fn getGlslang (self: @This ()) [] const u8 { return self.__glslang; }
  pub fn getGlslangIn (self: @This ()) [] const u8 { return self.__glslang_in; }

  // mandatory init
  pub fn init (builder: *std.Build) !@This ()
  {
    var self = @This ()
    {
      .__glslang = try builder.build_root.join (builder.allocator,
        &.{ "glslang", }),
    };

    self.__glslang_in = try std.fs.path.join (builder.allocator,
      &.{ self.getGlslang (), "glslang", });

    return self;
  }
};

fn update (builder: *std.Build, path: *const Paths,
  dependencies: *const toolbox.Dependencies) !void
{
  std.fs.deleteTreeAbsolute (path.getGlslang ()) catch |err|
  {
    switch (err)
    {
      error.FileNotFound => {},
      else => return err,
    }
  };

  try dependencies.clone (builder, "glslang", path.getGlslang ());

  try toolbox.run (builder, .{ .argv = &[_][] const u8 { "python3",
    try std.fs.path.join (builder.allocator,
      &.{ path.getGlslang (), "build_info.py", }), path.getGlslang (),
    "-i", try std.fs.path.join (builder.allocator,
      &.{ path.getGlslang (), "build_info.h.tmpl", }),
    "-o", try std.fs.path.join (builder.allocator,
      &.{ path.getGlslangIn (), "build_info.h", }),
  }, });

  var glslang_dir =
    try std.fs.openDirAbsolute (path.getGlslang (), .{ .iterate = true, });
  defer glslang_dir.close ();

  var it = glslang_dir.iterate ();
  while (try it.next ()) |*entry|
  {
    if (!std.mem.eql (u8, "SPIRV", entry.name) and
      !std.mem.eql (u8, "StandAlone", entry.name) and
      !std.mem.eql (u8, "glslang", entry.name))
        try std.fs.deleteTreeAbsolute (try std.fs.path.join (
          builder.allocator, &.{ path.getGlslang (), entry.name, }));
  }

  const standalone_path = try std.fs.path.join (builder.allocator,
    &.{ path.getGlslang (), "StandAlone", });

  var standalone_dir = try std.fs.openDirAbsolute (standalone_path,
    .{ .iterate = true, });
  defer standalone_dir.close ();

  it = standalone_dir.iterate ();
  while (try it.next ()) |*entry|
  {
    if (!toolbox.isCHeader (entry.name) and entry.kind == .file)
      try std.fs.deleteFileAbsolute (try std.fs.path.join (builder.allocator,
        &.{ standalone_path, entry.name, }));
  }

  try toolbox.clean (builder, &.{ "glslang", }, &.{});
}

pub fn build (builder: *std.Build) !void
{
  const target = builder.standardTargetOptions (.{});
  const optimize = builder.standardOptimizeOption (.{});

  const path = try Paths.init (builder);

  const dependencies = try toolbox.Dependencies.init (builder, "glslang.zig",
  .{
     .toolbox = .{
       .name = "tiawl/toolbox",
       .host = toolbox.Repository.Host.github,
     },
   }, .{
     .glslang = .{
       .name = "KhronosGroup/glslang",
       .host = toolbox.Repository.Host.github,
     },
   });

  if (builder.option (bool, "update", "Update binding") orelse false)
    try update (builder, &path, &dependencies);

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

  toolbox.addHeader (lib, path.getGlslangIn (), "glslang", &.{ ".h", });
  toolbox.addHeader (lib, try std.fs.path.join (builder.allocator,
    &.{ path.getGlslang (), "SPIRV", }), "SPIRV", &.{ ".h", });

  lib.linkLibCpp ();

  var glslang_dir = try std.fs.openDirAbsolute (path.getGlslang (),
    .{ .iterate = true, });
  defer glslang_dir.close ();

  var walker = try glslang_dir.walk (builder.allocator);
  defer walker.deinit ();

  walk: while (try walker.next ()) |*entry|
  {
    switch (entry.kind)
    {
      .file => {
        var it = try std.fs.path.componentIterator (entry.path);
        while (it.next ()) |*component|
        {
          if (std.mem.eql (u8, component.name, "OSDependent")) continue :walk;
        }
        if (toolbox.isCppSource (entry.basename))
          try toolbox.addSource (lib, path.getGlslang (), entry.path, &flags);
      },
      else => {},
    }
  }

  const os = switch (target.result.os.tag)
  {
    .linux => "Unix",
    .windows => "Windows",
    else => return error.UnsupportedOs,
  };

  const os_path = try std.fs.path.join (builder.allocator,
    &.{ path.getGlslangIn (), "OSDependent", os, });

  var os_dir = try std.fs.openDirAbsolute (os_path,
    .{ .iterate = true, });
  defer os_dir.close ();

  var it = os_dir.iterate ();

  while (try it.next ()) |*entry|
  {
    switch (entry.kind)
    {
      .file => {
        if (toolbox.isCppSource (entry.name))
          try toolbox.addSource (lib, os_path, entry.name, &flags);
      },
      else => {},
    }
  }

  builder.installArtifact (lib);
}
