const std = @import("std");
const png = @import("png");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize SDL
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("SDL Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window and renderer
    var window: ?*c.SDL_Window = null;
    var renderer: ?*c.SDL_Renderer = null;

    if (!c.SDL_CreateWindowAndRenderer("zig-png-examples", WINDOW_WIDTH, WINDOW_HEIGHT, 0, &window, &renderer)) {
        std.debug.print("Failed to create window: {s}\n", .{c.SDL_GetError()});
        return error.WindowCreationFailed;
    }
    defer c.SDL_DestroyRenderer(renderer);
    defer c.SDL_DestroyWindow(window);

    // Get command line args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Current texture and image info
    var texture: ?*c.SDL_Texture = null;
    var img_width: u32 = 0;
    var img_height: u32 = 0;
    var current_pixels: ?[]u8 = null;

    // Load PNG if provided as argument
    if (args.len > 1) {
        const result = loadPngTextureWithPixels(allocator, renderer.?, args[1]);
        if (result) |tex_info| {
            texture = tex_info.texture;
            img_width = tex_info.width;
            img_height = tex_info.height;
            current_pixels = tex_info.pixels;
            std.debug.print("Loaded: {s} ({d}x{d})\n", .{ args[1], img_width, img_height });
        } else |err| {
            std.debug.print("Failed to load PNG: {}\n", .{err});
        }
    } else {
        // Generate default gradient
        const result = generateGradientTextureWithPixels(allocator, renderer.?, 256, 256);
        if (result) |tex_info| {
            texture = tex_info.texture;
            img_width = tex_info.width;
            img_height = tex_info.height;
            current_pixels = tex_info.pixels;
            std.debug.print("Generated gradient ({d}x{d})\n", .{ img_width, img_height });
        } else |err| {
            std.debug.print("Failed to generate gradient: {}\n", .{err});
        }
    }
    defer if (texture) |t| c.SDL_DestroyTexture(t);
    defer if (current_pixels) |p| allocator.free(p);

    std.debug.print("\nControls:\n", .{});
    std.debug.print("  S - Save current image as output.png\n", .{});
    std.debug.print("  G - Generate new gradient\n", .{});
    std.debug.print("  Q - Quit\n\n", .{});

    // Main loop
    var running = true;
    while (running) {
        // Handle events
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_KEY_DOWN => {
                    const key = event.key.key;
                    if (key == c.SDLK_Q or key == c.SDLK_ESCAPE) {
                        running = false;
                    } else if (key == c.SDLK_S) {
                        // Save current image
                        if (current_pixels) |pixels| {
                            savePng(allocator, pixels, img_width, img_height) catch |err| {
                                std.debug.print("Failed to save PNG: {}\n", .{err});
                            };
                        }
                    } else if (key == c.SDLK_G) {
                        // Generate new gradient and update display
                        const result = generateGradientTextureWithPixels(allocator, renderer.?, 256, 256);
                        if (result) |tex_info| {
                            if (texture) |t| c.SDL_DestroyTexture(t);
                            if (current_pixels) |p| allocator.free(p);
                            texture = tex_info.texture;
                            img_width = tex_info.width;
                            img_height = tex_info.height;
                            current_pixels = tex_info.pixels;
                            std.debug.print("Generated new gradient ({d}x{d})\n", .{ img_width, img_height });
                        } else |err| {
                            std.debug.print("Failed to generate gradient: {}\n", .{err});
                        }
                    }
                },
                else => {},
            }
        }

        // Clear screen
        _ = c.SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255);
        _ = c.SDL_RenderClear(renderer);

        // Draw texture centered
        if (texture) |t| {
            const dst_rect = c.SDL_FRect{
                .x = @as(f32, @floatFromInt(WINDOW_WIDTH - img_width)) / 2.0,
                .y = @as(f32, @floatFromInt(WINDOW_HEIGHT - img_height)) / 2.0,
                .w = @floatFromInt(img_width),
                .h = @floatFromInt(img_height),
            };
            _ = c.SDL_RenderTexture(renderer, t, null, &dst_rect);
        }

        // Present
        _ = c.SDL_RenderPresent(renderer);

        // Small delay to reduce CPU usage
        c.SDL_Delay(16);
    }
}

const TextureInfo = struct {
    texture: *c.SDL_Texture,
    width: u32,
    height: u32,
    pixels: []u8,
};

fn loadPngTextureWithPixels(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, path: []const u8) !TextureInfo {
    // Decode PNG file
    var image = png.decodeFile(allocator, path) catch |err| {
        std.debug.print("PNG decode error: {}\n", .{err});
        return error.PngDecodeError;
    };
    defer image.deinit();

    const width = image.width();
    const height = image.height();

    // Convert to RGBA for SDL (keep ownership)
    const rgba_pixels = try convertToRgba(allocator, &image);

    // Create SDL texture
    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        @intCast(width),
        @intCast(height),
    );

    if (texture == null) {
        std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
        allocator.free(rgba_pixels);
        return error.TextureCreationFailed;
    }

    // Upload pixel data
    const pitch: c_int = @intCast(width * 4);
    if (!c.SDL_UpdateTexture(texture, null, rgba_pixels.ptr, pitch)) {
        c.SDL_DestroyTexture(texture);
        allocator.free(rgba_pixels);
        return error.TextureUpdateFailed;
    }

    return TextureInfo{
        .texture = texture.?,
        .width = width,
        .height = height,
        .pixels = rgba_pixels,
    };
}

fn convertToRgba(allocator: std.mem.Allocator, image: *const png.Image) ![]u8 {
    const width = image.width();
    const height = image.height();
    const rgba = try allocator.alloc(u8, width * height * 4);

    const color_type = image.header.color_type;

    for (0..height) |y| {
        for (0..width) |x| {
            const pixel = image.getPixel(@intCast(x), @intCast(y));
            const out_idx = (y * width + x) * 4;

            switch (color_type) {
                .grayscale => {
                    rgba[out_idx + 0] = pixel[0];
                    rgba[out_idx + 1] = pixel[0];
                    rgba[out_idx + 2] = pixel[0];
                    rgba[out_idx + 3] = 255;
                },
                .grayscale_alpha => {
                    rgba[out_idx + 0] = pixel[0];
                    rgba[out_idx + 1] = pixel[0];
                    rgba[out_idx + 2] = pixel[0];
                    rgba[out_idx + 3] = pixel[1];
                },
                .rgb => {
                    rgba[out_idx + 0] = pixel[0];
                    rgba[out_idx + 1] = pixel[1];
                    rgba[out_idx + 2] = pixel[2];
                    rgba[out_idx + 3] = 255;
                },
                .rgba => {
                    rgba[out_idx + 0] = pixel[0];
                    rgba[out_idx + 1] = pixel[1];
                    rgba[out_idx + 2] = pixel[2];
                    rgba[out_idx + 3] = pixel[3];
                },
                .indexed => {
                    // Use palette lookup
                    if (image.palette) |pal| {
                        const idx = pixel[0];
                        if (idx < pal.len) {
                            const entry = pal[idx];
                            rgba[out_idx + 0] = entry.r;
                            rgba[out_idx + 1] = entry.g;
                            rgba[out_idx + 2] = entry.b;
                            rgba[out_idx + 3] = 255;
                        }
                    }
                },
            }
        }
    }

    return rgba;
}

fn generateGradientTextureWithPixels(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, width: u32, height: u32) !TextureInfo {
    // Generate gradient pixels (keep ownership)
    const pixels = try allocator.alloc(u8, width * height * 4);

    for (0..height) |y| {
        for (0..width) |x| {
            const idx = (y * width + x) * 4;
            pixels[idx + 0] = @intCast(x); // R
            pixels[idx + 1] = @intCast(y); // G
            pixels[idx + 2] = 128; // B
            pixels[idx + 3] = 255; // A
        }
    }

    // Create SDL texture
    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        @intCast(width),
        @intCast(height),
    );

    if (texture == null) {
        allocator.free(pixels);
        return error.TextureCreationFailed;
    }

    // Upload pixel data
    const pitch: c_int = @intCast(width * 4);
    if (!c.SDL_UpdateTexture(texture, null, pixels.ptr, pitch)) {
        c.SDL_DestroyTexture(texture);
        allocator.free(pixels);
        return error.TextureUpdateFailed;
    }

    return TextureInfo{
        .texture = texture.?,
        .width = width,
        .height = height,
        .pixels = pixels,
    };
}

fn savePng(allocator: std.mem.Allocator, pixels: []const u8, width: u32, height: u32) !void {
    // Create PNG header
    const header = png.Header{
        .width = width,
        .height = height,
        .bit_depth = .@"8",
        .color_type = .rgba,
        .compression_method = .deflate,
        .filter_method = .adaptive,
        .interlace_method = .none,
    };

    // Allocate output buffer
    const max_size = png.maxEncodedSize(header);
    const output = try allocator.alloc(u8, max_size);
    defer allocator.free(output);

    // Encode to PNG
    const encoded_len = try png.encodeRaw(allocator, header, pixels, null, output, .{});

    // Write to file
    const file = try std.fs.cwd().createFile("output.png", .{});
    defer file.close();
    try file.writeAll(output[0..encoded_len]);

    std.debug.print("Saved: output.png ({d} bytes)\n", .{encoded_len});
}
