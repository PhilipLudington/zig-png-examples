//! Convert a decoded PNG image to 8-bit RGBA for display.
//!
//! Shared by the viewer (`main.zig`) and the folder browser (`browser.zig`).

const std = @import("std");
const png = @import("png");
const Allocator = std.mem.Allocator;
const testing = std.testing;

/// Color written for a pixel that cannot be read or has no valid palette entry.
const error_color = [4]u8{ 255, 0, 255, 255 };

/// Convert `image` to tightly packed RGBA, 4 bytes per pixel, row-major.
/// Handles every color type at every bit depth PNG allows: grayscale and
/// indexed images are read with `getSample` (which unpacks 1-, 2- and 4-bit
/// pixels), the rest with `getPixel`. 16-bit samples keep their high byte.
/// Caller owns the returned slice and must free it with `allocator`.
pub fn convertToRgba(allocator: Allocator, image: *const png.Image) ![]u8 {
    const width: usize = image.width();
    const height: usize = image.height();
    const pixel_count = std.math.mul(usize, width, height) catch return error.Overflow;
    const byte_count = std.math.mul(usize, pixel_count, 4) catch return error.Overflow;
    const rgba = try allocator.alloc(u8, byte_count);
    errdefer allocator.free(rgba);

    for (0..height) |y| {
        for (0..width) |x| {
            const out_idx = (y * width + x) * 4;
            const color = pixelColor(image, @intCast(x), @intCast(y)) catch error_color;
            @memcpy(rgba[out_idx..][0..4], &color);
        }
    }

    return rgba;
}

fn pixelColor(image: *const png.Image, x: u32, y: u32) ![4]u8 {
    const depth = image.header.bit_depth.toInt();
    switch (image.header.color_type) {
        .grayscale => {
            const gray = scaleSample(try image.getSample(x, y), depth);
            return .{ gray, gray, gray, 255 };
        },
        .indexed => {
            const index: usize = try image.getSample(x, y);
            const pal = image.palette orelse {
                // No PLTE chunk: show the index as gray.
                const gray = scaleSample(@intCast(index), depth);
                return .{ gray, gray, gray, 255 };
            };
            // getSample does not check the index against the palette length.
            if (index >= pal.len) return error_color;
            const entry = pal[index];
            return .{ entry.r, entry.g, entry.b, 255 };
        },
        .grayscale_alpha, .rgb, .rgba => {
            // These types only allow 8- or 16-bit samples; take the high byte.
            const pixel = try image.getPixel(x, y);
            const stride: usize = depth / 8;
            var s: [4]u8 = undefined;
            for (0..pixel.len / stride) |i| s[i] = pixel[i * stride];
            return switch (image.header.color_type) {
                .grayscale_alpha => .{ s[0], s[0], s[0], s[1] },
                .rgb => .{ s[0], s[1], s[2], 255 },
                .rgba => s,
                else => unreachable,
            };
        },
    }
}

/// Scale a raw sample of `depth` bits (1, 2, 4, 8 or 16) to 0..255.
fn scaleSample(value: u16, depth: u8) u8 {
    return switch (depth) {
        16 => @intCast(value >> 8),
        8 => @intCast(value),
        else => blk: {
            const max: u32 = (@as(u32, 1) << @intCast(depth)) - 1;
            break :blk @intCast(@as(u32, value) * 255 / max);
        },
    };
}

test "scaleSample maps every depth's full range to 0..255" {
    const cases = [_]struct { value: u16, depth: u8, expected: u8 }{
        .{ .value = 0, .depth = 1, .expected = 0 },
        .{ .value = 1, .depth = 1, .expected = 255 },
        .{ .value = 2, .depth = 2, .expected = 170 },
        .{ .value = 3, .depth = 2, .expected = 255 },
        .{ .value = 15, .depth = 4, .expected = 255 },
        .{ .value = 1, .depth = 4, .expected = 17 },
        .{ .value = 200, .depth = 8, .expected = 200 },
        .{ .value = 0xABCD, .depth = 16, .expected = 0xAB },
    };
    for (cases) |case| {
        try testing.expectEqual(case.expected, scaleSample(case.value, case.depth));
    }
}

fn testImage(
    pixels: []u8,
    width: u32,
    height: u32,
    color_type: png.ColorType,
    bit_depth: png.BitDepth,
    palette: ?[]png.PaletteEntry,
) png.Image {
    return .{
        .header = .{
            .width = width,
            .height = height,
            .bit_depth = bit_depth,
            .color_type = color_type,
            .compression_method = .deflate,
            .filter_method = .adaptive,
            .interlace_method = .none,
        },
        .pixels = pixels,
        .palette = palette,
        .allocator = testing.allocator,
    };
}

test "convertToRgba unpacks 1-bit grayscale" {
    // One row of 8 pixels packed into one byte: 1,0,1,0,0,0,0,1.
    var pixels = [_]u8{0b1010_0001};
    const image = testImage(&pixels, 8, 1, .grayscale, .@"1", null);

    const rgba = try convertToRgba(testing.allocator, &image);
    defer testing.allocator.free(rgba);

    const expected_gray = [_]u8{ 255, 0, 255, 0, 0, 0, 0, 255 };
    for (expected_gray, 0..) |gray, i| {
        try testing.expectEqualSlices(u8, &.{ gray, gray, gray, 255 }, rgba[i * 4 ..][0..4]);
    }
}

test "convertToRgba looks up 4-bit indexed pixels and flags bad indices" {
    // Two pixels in one byte: index 1, then index 3 (past the 2-entry palette).
    var pixels = [_]u8{0x13};
    var palette = [_]png.PaletteEntry{
        .{ .r = 10, .g = 20, .b = 30 },
        .{ .r = 40, .g = 50, .b = 60 },
    };
    const image = testImage(&pixels, 2, 1, .indexed, .@"4", &palette);

    const rgba = try convertToRgba(testing.allocator, &image);
    defer testing.allocator.free(rgba);

    try testing.expectEqualSlices(u8, &.{ 40, 50, 60, 255 }, rgba[0..4]);
    try testing.expectEqualSlices(u8, &error_color, rgba[4..8]);
}

test "convertToRgba keeps the high byte of 16-bit RGB samples" {
    var pixels = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC };
    const image = testImage(&pixels, 1, 1, .rgb, .@"16", null);

    const rgba = try convertToRgba(testing.allocator, &image);
    defer testing.allocator.free(rgba);

    try testing.expectEqualSlices(u8, &.{ 0x12, 0x56, 0x9A, 255 }, rgba);
}

test "convertToRgba copies 8-bit RGBA unchanged" {
    var pixels = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const image = testImage(&pixels, 2, 1, .rgba, .@"8", null);

    const rgba = try convertToRgba(testing.allocator, &image);
    defer testing.allocator.free(rgba);

    try testing.expectEqualSlices(u8, &pixels, rgba);
}
