const std = @import("std");
const png = @import("png");
const convertToRgba = @import("rgba.zig").convertToRgba;
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const WINDOW_WIDTH = 1024;
const WINDOW_HEIGHT = 768;
const THUMB_SIZE = 128;
const GRID_COLS = 6;
const PADDING = 16;

const Thumbnail = struct {
    texture: *c.SDL_Texture,
    filename: []const u8,
    orig_width: u32,
    orig_height: u32,
};

const ViewMode = enum { grid, full };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get directory path from args or use current directory
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const dir_path = if (args.len > 1) args[1] else ".";

    // Initialize SDL
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("SDL Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window and renderer
    var window: ?*c.SDL_Window = null;
    var renderer: ?*c.SDL_Renderer = null;

    if (!c.SDL_CreateWindowAndRenderer("PNG Browser", WINDOW_WIDTH, WINDOW_HEIGHT, 0, &window, &renderer)) {
        std.debug.print("Failed to create window: {s}\n", .{c.SDL_GetError()});
        return error.WindowCreationFailed;
    }
    defer c.SDL_DestroyRenderer(renderer);
    defer c.SDL_DestroyWindow(window);

    // Scan directory for PNG files
    var thumbnails = std.ArrayList(Thumbnail).initCapacity(allocator, 0) catch {
        return error.OutOfMemory;
    };
    defer {
        for (thumbnails.items) |*thumb| {
            c.SDL_DestroyTexture(thumb.texture);
            allocator.free(thumb.filename);
        }
        thumbnails.deinit(allocator);
    }

    try scanDirectory(allocator, renderer.?, dir_path, &thumbnails);

    if (thumbnails.items.len == 0) {
        std.debug.print("No PNG files found in: {s}\n", .{dir_path});
    } else {
        std.debug.print("Found {d} PNG files in: {s}\n", .{ thumbnails.items.len, dir_path });
    }

    std.debug.print("\nControls:\n", .{});
    std.debug.print("  Arrow keys - Navigate\n", .{});
    std.debug.print("  Enter      - View full size\n", .{});
    std.debug.print("  Escape     - Back to grid / Quit\n", .{});
    std.debug.print("  Mouse      - Click to select/view\n", .{});
    std.debug.print("  Scroll     - Scroll grid\n\n", .{});

    // State
    var selected: usize = 0;
    var scroll_y: i32 = 0;
    var view_mode: ViewMode = .grid;
    var full_texture: ?*c.SDL_Texture = null;
    var full_width: u32 = 0;
    var full_height: u32 = 0;
    defer if (full_texture) |t| c.SDL_DestroyTexture(t);

    // Main loop
    var running = true;
    while (running) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,

                c.SDL_EVENT_KEY_DOWN => {
                    const key = event.key.key;

                    if (view_mode == .full) {
                        if (key == c.SDLK_ESCAPE or key == c.SDLK_RETURN) {
                            view_mode = .grid;
                            if (full_texture) |t| {
                                c.SDL_DestroyTexture(t);
                                full_texture = null;
                            }
                        }
                    } else {
                        if (key == c.SDLK_ESCAPE) {
                            running = false;
                        } else if (key == c.SDLK_RETURN) {
                            if (thumbnails.items.len > 0) {
                                const result = loadFullImage(allocator, renderer.?, dir_path, thumbnails.items[selected].filename);
                                if (result) |info| {
                                    if (full_texture) |t| c.SDL_DestroyTexture(t);
                                    full_texture = info.texture;
                                    full_width = info.width;
                                    full_height = info.height;
                                    view_mode = .full;
                                } else |_| {}
                            }
                        } else if (key == c.SDLK_LEFT) {
                            if (selected > 0) selected -= 1;
                            ensureVisible(&scroll_y, selected);
                        } else if (key == c.SDLK_RIGHT) {
                            if (selected + 1 < thumbnails.items.len) selected += 1;
                            ensureVisible(&scroll_y, selected);
                        } else if (key == c.SDLK_UP) {
                            if (selected >= GRID_COLS) selected -= GRID_COLS;
                            ensureVisible(&scroll_y, selected);
                        } else if (key == c.SDLK_DOWN) {
                            if (selected + GRID_COLS < thumbnails.items.len) selected += GRID_COLS;
                            ensureVisible(&scroll_y, selected);
                        }
                    }
                },

                c.SDL_EVENT_MOUSE_WHEEL => {
                    if (view_mode == .grid) {
                        scroll_y -= @as(i32, @intFromFloat(event.wheel.y * 40));
                        scroll_y = clampScroll(scroll_y, thumbnails.items.len);
                    }
                },

                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    if (view_mode == .full) {
                        view_mode = .grid;
                        if (full_texture) |t| {
                            c.SDL_DestroyTexture(t);
                            full_texture = null;
                        }
                    } else {
                        const mx = event.button.x;
                        const my = event.button.y;
                        if (getThumbAtPos(mx, my, scroll_y, thumbnails.items.len)) |idx| {
                            selected = idx;
                            // Double-click or single click to view
                            const result = loadFullImage(allocator, renderer.?, dir_path, thumbnails.items[selected].filename);
                            if (result) |info| {
                                if (full_texture) |t| c.SDL_DestroyTexture(t);
                                full_texture = info.texture;
                                full_width = info.width;
                                full_height = info.height;
                                view_mode = .full;
                            } else |_| {}
                        }
                    }
                },

                else => {},
            }
        }

        // Render
        _ = c.SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255);
        _ = c.SDL_RenderClear(renderer);

        if (view_mode == .full) {
            renderFullView(renderer.?, full_texture, full_width, full_height);
        } else {
            renderGrid(renderer.?, thumbnails.items, selected, scroll_y);
        }

        _ = c.SDL_RenderPresent(renderer);
        c.SDL_Delay(16);
    }
}

fn scanDirectory(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, dir_path: []const u8, thumbnails: *std.ArrayList(Thumbnail)) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        std.debug.print("Failed to open directory: {}\n", .{err});
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;

        // Check for .png extension
        if (std.mem.endsWith(u8, entry.name, ".png") or std.mem.endsWith(u8, entry.name, ".PNG")) {
            const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
            defer allocator.free(full_path);

            if (loadThumbnail(allocator, renderer, full_path)) |thumb| {
                const name_copy = try allocator.dupe(u8, entry.name);
                try thumbnails.append(allocator, .{
                    .texture = thumb.texture,
                    .filename = name_copy,
                    .orig_width = thumb.width,
                    .orig_height = thumb.height,
                });
            } else |_| {
                std.debug.print("Failed to load: {s}\n", .{entry.name});
            }
        }
    }
}

const ThumbInfo = struct {
    texture: *c.SDL_Texture,
    width: u32,
    height: u32,
};

fn loadThumbnail(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, path: []const u8) !ThumbInfo {
    var image = png.decodeFile(allocator, path) catch |err| {
        std.debug.print("Decode failed for {s}: {}\n", .{ path, err });
        return err;
    };
    defer image.deinit();

    const orig_w = image.width();
    const orig_h = image.height();

    // Convert to RGBA
    const rgba = convertToRgba(allocator, &image) catch |err| {
        std.debug.print("Convert failed for {s}: {}\n", .{ path, err });
        return err;
    };
    defer allocator.free(rgba);

    // Calculate scaled size maintaining aspect ratio
    var scale_w: u32 = THUMB_SIZE;
    var scale_h: u32 = THUMB_SIZE;

    if (orig_w > orig_h) {
        scale_h = @intCast(@as(u64, orig_h) * THUMB_SIZE / orig_w);
    } else {
        scale_w = @intCast(@as(u64, orig_w) * THUMB_SIZE / orig_h);
    }

    // Create texture at original size, SDL will scale when rendering
    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        @intCast(orig_w),
        @intCast(orig_h),
    );

    if (texture == null) return error.TextureCreationFailed;

    const pitch: c_int = @intCast(orig_w * 4);
    if (!c.SDL_UpdateTexture(texture, null, rgba.ptr, pitch)) {
        c.SDL_DestroyTexture(texture);
        return error.TextureUpdateFailed;
    }

    return ThumbInfo{
        .texture = texture.?,
        .width = orig_w,
        .height = orig_h,
    };
}

fn loadFullImage(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, dir_path: []const u8, filename: []const u8) !ThumbInfo {
    const full_path = try std.fs.path.join(allocator, &.{ dir_path, filename });
    defer allocator.free(full_path);

    var image = try png.decodeFile(allocator, full_path);
    defer image.deinit();

    const w = image.width();
    const h = image.height();

    const rgba = try convertToRgba(allocator, &image);
    defer allocator.free(rgba);

    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        @intCast(w),
        @intCast(h),
    );

    if (texture == null) return error.TextureCreationFailed;

    const pitch: c_int = @intCast(w * 4);
    if (!c.SDL_UpdateTexture(texture, null, rgba.ptr, pitch)) {
        c.SDL_DestroyTexture(texture);
        return error.TextureUpdateFailed;
    }

    std.debug.print("Viewing: {s} ({d}x{d})\n", .{ filename, w, h });

    return ThumbInfo{
        .texture = texture.?,
        .width = w,
        .height = h,
    };
}

fn renderGrid(renderer: *c.SDL_Renderer, thumbnails: []const Thumbnail, selected: usize, scroll_y: i32) void {
    const cell_size = THUMB_SIZE + PADDING;
    const start_x = (WINDOW_WIDTH - (GRID_COLS * cell_size - PADDING)) / 2;
    const start_y: i32 = PADDING;

    for (thumbnails, 0..) |thumb, i| {
        const col: i32 = @intCast(i % GRID_COLS);
        const row: i32 = @intCast(i / GRID_COLS);

        const x: i32 = @as(i32, @intCast(start_x)) + col * @as(i32, cell_size);
        const y: i32 = start_y + row * @as(i32, cell_size) - scroll_y;

        // Skip if off screen
        if (y + THUMB_SIZE < 0 or y > WINDOW_HEIGHT) continue;

        // Draw selection highlight
        if (i == selected) {
            _ = c.SDL_SetRenderDrawColor(renderer, 100, 150, 255, 255);
            const highlight = c.SDL_FRect{
                .x = @floatFromInt(x - 4),
                .y = @floatFromInt(y - 4),
                .w = THUMB_SIZE + 8,
                .h = THUMB_SIZE + 8,
            };
            _ = c.SDL_RenderFillRect(renderer, &highlight);
        }

        // Draw background
        _ = c.SDL_SetRenderDrawColor(renderer, 50, 50, 50, 255);
        const bg = c.SDL_FRect{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
            .w = THUMB_SIZE,
            .h = THUMB_SIZE,
        };
        _ = c.SDL_RenderFillRect(renderer, &bg);

        // Calculate scaled size to fit in thumbnail
        var draw_w: f32 = THUMB_SIZE;
        var draw_h: f32 = THUMB_SIZE;
        const orig_w: f32 = @floatFromInt(thumb.orig_width);
        const orig_h: f32 = @floatFromInt(thumb.orig_height);

        if (orig_w > orig_h) {
            draw_h = orig_h * THUMB_SIZE / orig_w;
        } else {
            draw_w = orig_w * THUMB_SIZE / orig_h;
        }

        const offset_x = (@as(f32, THUMB_SIZE) - draw_w) / 2;
        const offset_y = (@as(f32, THUMB_SIZE) - draw_h) / 2;

        const dst = c.SDL_FRect{
            .x = @as(f32, @floatFromInt(x)) + offset_x,
            .y = @as(f32, @floatFromInt(y)) + offset_y,
            .w = draw_w,
            .h = draw_h,
        };

        _ = c.SDL_RenderTexture(renderer, thumb.texture, null, &dst);
    }
}

fn renderFullView(renderer: *c.SDL_Renderer, texture: ?*c.SDL_Texture, width: u32, height: u32) void {
    if (texture == null) return;

    // Scale to fit window while maintaining aspect ratio
    var draw_w: f32 = @floatFromInt(width);
    var draw_h: f32 = @floatFromInt(height);

    const scale_x = @as(f32, WINDOW_WIDTH - 40) / draw_w;
    const scale_y = @as(f32, WINDOW_HEIGHT - 40) / draw_h;
    const scale = @min(scale_x, scale_y);

    if (scale < 1.0) {
        draw_w *= scale;
        draw_h *= scale;
    }

    const x = (@as(f32, WINDOW_WIDTH) - draw_w) / 2;
    const y = (@as(f32, WINDOW_HEIGHT) - draw_h) / 2;

    const dst = c.SDL_FRect{
        .x = x,
        .y = y,
        .w = draw_w,
        .h = draw_h,
    };

    _ = c.SDL_RenderTexture(renderer, texture, null, &dst);
}

fn getThumbAtPos(mx: f32, my: f32, scroll_y: i32, count: usize) ?usize {
    const cell_size = THUMB_SIZE + PADDING;
    const start_x = (WINDOW_WIDTH - (GRID_COLS * cell_size - PADDING)) / 2;
    const start_y: i32 = PADDING;

    const adj_y = my + @as(f32, @floatFromInt(scroll_y));

    if (mx < @as(f32, @floatFromInt(start_x))) return null;

    const col: i32 = @intFromFloat((mx - @as(f32, @floatFromInt(start_x))) / @as(f32, cell_size));
    const row: i32 = @intFromFloat((adj_y - @as(f32, @floatFromInt(start_y))) / @as(f32, cell_size));

    if (col < 0 or col >= GRID_COLS or row < 0) return null;

    const idx: usize = @intCast(row * GRID_COLS + col);
    if (idx >= count) return null;

    return idx;
}

fn ensureVisible(scroll_y: *i32, selected: usize) void {
    const cell_size = THUMB_SIZE + PADDING;
    const row: i32 = @intCast(selected / GRID_COLS);
    const item_y = PADDING + row * @as(i32, cell_size);
    const item_bottom = item_y + THUMB_SIZE;

    if (item_y < scroll_y.*) {
        scroll_y.* = item_y - PADDING;
    } else if (item_bottom > scroll_y.* + WINDOW_HEIGHT - PADDING) {
        scroll_y.* = item_bottom - WINDOW_HEIGHT + PADDING * 2;
    }
}

fn clampScroll(scroll_y: i32, count: usize) i32 {
    const rows = (count + GRID_COLS - 1) / GRID_COLS;
    const cell_size = THUMB_SIZE + PADDING;
    const content_height: i32 = @intCast(rows * cell_size + PADDING);
    const max_scroll = @max(0, content_height - WINDOW_HEIGHT);

    return std.math.clamp(scroll_y, 0, max_scroll);
}
