// https://zenn.dev/drumato/books/learn-zig-to-be-a-beginner
const std = @import("std");

pub fn main() !void {
    var args = std.process.ArgIterator.init();
    std.debug.assert(args.next() != null);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const opt = try parseCmdArgs(allocator, &args);
    defer opt.targets.deinit();

    var stdout = std.io.getStdOut().writer();

    for (opt.targets.items) |target_path| {
        const cwd = std.fs.cwd();

        const target_dir = if (std.fs.path.isAbsolute(target_path)) blk: {
            break :blk try std.fs.openIterableDirAbsolute(target_path, std.fs.Dir.OpenDirOptions{});
        } else else_blk: {
            break :else_blk try cwd.openIterableDir(target_path, std.fs.Dir.OpenDirOptions{});
        };

        var target_dir_entries = try collectFileInformation(allocator, target_dir);
        const hide_file = !opt.all_files;
        for (target_dir_entries.items) |target_dir_entry| {
            if (hide_file and target_dir_entry.name[0] == '.') {
                continue;
            }

            if (opt.show_inode_number) {
                try stdout.print("{} {s}\n", .{ target_dir_entry.inode, target_dir_entry.name });
            } else {
                try stdout.print("{s}\n", .{target_dir_entry.name});
            }
        }
    }
}

const CommandLineOption = struct {
    targets: std.ArrayList([]const u8),
    all_files: bool = false,
    show_inode_number: bool = false,
};

const CmdArgsParseError = error{
    MaximumTargetCountReached,
} || std.mem.Allocator.Error;

fn parseCmdArgs(allocator: std.mem.Allocator, args: *std.process.ArgIterator) CmdArgsParseError!CommandLineOption {
    var opt = CommandLineOption{
        .targets = std.ArrayList([]const u8).init(allocator),
    };
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-a")) {
            opt.all_files = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-i")) {
            opt.show_inode_number = true;
            continue;
        }

        try opt.targets.append(arg);
    }

    return opt;
}

const FileInformation = struct {
    name: []const u8,
    inode: u64,
};

fn collectFileInformation(allocator: std.mem.Allocator, target_dir: std.fs.IterableDir) !std.ArrayList(FileInformation) {
    var files = std.ArrayList(FileInformation).init(allocator);

    var iterator = target_dir.iterate();
    while (try iterator.next()) |dir_entry| {
        const file = switch (dir_entry.kind) {
            .file => file_blk: {
                const file = try target_dir.dir.openFile(dir_entry.name, std.fs.File.OpenFlags{});
                const stat = try file.stat();
                break :file_blk FileInformation{
                    .name = dir_entry.name,
                    .inode = stat.inode,
                };
            },
            .directory => dir_blk: {
                const dir = try target_dir.dir.openDir(dir_entry.name, std.fs.Dir.OpenDirOptions{});
                const stat = try dir.stat();
                break :dir_blk FileInformation{
                    .name = dir_entry.name,
                    .inode = stat.inode,
                };
            },
            else => unreachable,
        };
        try files.append(file);
    }

    return files;
}
