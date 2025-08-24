package dinamp

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:os"
import "core:path/filepath"
import "vendor:raylib"

WIDTH  :: 640
HEIGHT :: 480

main :: proc () {
	raylib.InitWindow(WIDTH, HEIGHT, "DINAMP")
	defer raylib.CloseWindow()

	raylib.InitAudioDevice()
	defer raylib.CloseAudioDevice()

	raylib.SetTargetFPS(60)

	music : raylib.Music
	loaded := false
	playing := false
    started := false
	volume: f32 = 1.0
	seek_pos: f32 = 0.0
	file_name: string = "Drop music files here..."
	file_name_allocated := false

    seek_bar_rect := raylib.Rectangle{10, 90, 315, 20}

    queue: [dynamic]string
    defer {
        for path in queue {
            delete(path)
        }
        clear(&queue)
    }

    play_next :: proc(using_queue: ^[dynamic]string, music: ^raylib.Music, loaded: ^bool, playing: ^bool, started: ^bool, seek_pos: ^f32, file_name: ^string, file_name_allocated: ^bool) {
        if len(using_queue) == 0 do return

        next_path := using_queue[0]
        ordered_remove(using_queue, 0)

        data, ok := os.read_entire_file(next_path)
        if !ok {
            delete(next_path)
            play_next(using_queue, music, loaded, playing, started, seek_pos, file_name, file_name_allocated)
            return
        }
        defer delete(data)

        ext := filepath.ext(next_path)
        ext_cstr := strings.clone_to_cstring(ext, context.temp_allocator)

        music^ = raylib.LoadMusicStreamFromMemory(ext_cstr, raw_data(data), i32(len(data)))

        if music.frameCount > 0 {
            loaded^ = true
            playing^ = false
            started^ = false
            seek_pos^ = 0.0
            if file_name_allocated^ {
                delete(file_name^)
            }
            file_name^ = strings.clone(filepath.base(next_path))
            file_name_allocated^ = true
        } else {
            play_next(using_queue, music, loaded, playing, started, seek_pos, file_name, file_name_allocated)
        }

        delete(next_path)
    }

    for !raylib.WindowShouldClose() {
        current_time: f32 = 0.0
        total_time: f32 = 0.0

        // Handle file drop
        if raylib.IsFileDropped() {
            dropped_files := raylib.LoadDroppedFiles()
            defer raylib.UnloadDroppedFiles(dropped_files)

            if dropped_files.count > 0 {
                for i in 0..<dropped_files.count {
                    path_cstr := dropped_files.paths[i]
                    path_str := strings.clone_from_cstring(path_cstr)
                    append(&queue, path_str)
                }

                if !loaded {
                    play_next(&queue, &music, &loaded, &playing, &started, &seek_pos, &file_name, &file_name_allocated)
                }
            }
        }

        if loaded {
            raylib.UpdateMusicStream(music)

            if playing {
                if !raylib.IsMusicStreamPlaying(music) {
                    if started {
                        raylib.ResumeMusicStream(music)
                    } else {
                        raylib.PlayMusicStream(music)
                        started = true
                    }
                }
            } else {
                raylib.PauseMusicStream(music)
            }

            raylib.SetMusicVolume(music, volume)

            current_time = raylib.GetMusicTimePlayed(music)
            total_time = raylib.GetMusicTimeLength(music)

            if playing && current_time >= total_time - 0.1 {
                raylib.StopMusicStream(music)
                raylib.UnloadMusicStream(music)
                if file_name_allocated {
                    delete(file_name)
                    file_name_allocated = false
                }
                file_name = "Drop music files here..."
                loaded = false
                play_next(&queue, &music, &loaded, &playing, &started, &seek_pos, &file_name, &file_name_allocated)
                if loaded {
                    playing = true
                }
            }
        }

        raylib.BeginDrawing()
        raylib.ClearBackground(raylib.RAYWHITE)

        // GUI Layout
        file_cstr := strings.clone_to_cstring(file_name, context.temp_allocator)
        raylib.GuiLabel(raylib.Rectangle{10, 10, 380, 20}, file_cstr)

        if loaded {

            current_time := raylib.GetMusicTimePlayed(music)
            total_time := raylib.GetMusicTimeLength(music)

            // Play/Pause Button
            btn_text := playing ? "Pause" : "Play"
            if raylib.GuiButton(raylib.Rectangle{10, 40, 100, 30}, cstring(raw_data(btn_text))) {
                playing = !playing
            }

            // Volume Slider
            raw_volume: string = "Volume"
            raw_0: string = "0"
            raw_1: string = "1"
            raylib.GuiLabel(raylib.Rectangle{125, 30, 100, 30}, cstring(raw_data(raw_volume)))
            volume : = raylib.GuiSlider(raylib.Rectangle{125, 50, 200, 20}, cstring(raw_data(raw_0)), cstring(raw_data(raw_1)), &volume, 0.0, 1.0)

            // Seek Bar
            seek_pos_new := f32(raylib.GuiSliderBar(seek_bar_rect, nil, nil, &current_time, 0.0, total_time))
            if seek_pos_new == 1 {
                is_seeking := raylib.CheckCollisionPointRec(raylib.GetMousePosition(), seek_bar_rect) && raylib.IsMouseButtonDown(.LEFT)
                if is_seeking {
                    raylib.PauseMusicStream(music)
                }
                raylib.SeekMusicStream(music, current_time)
            }

            // Time Display
            current_min := i32(current_time / 60)
            current_sec := i32(current_time) % 60
            total_min := i32(total_time / 60)
            total_sec := i32(total_time) % 60

            builder: strings.Builder
            strings.builder_init(&builder, context.temp_allocator)
            fmt.sbprintf(&builder, "%02d:%02d / %02d:%02d", current_min, current_sec, total_min, total_sec)
            time_text := strings.to_string(builder)
            time_cstr := strings.clone_to_cstring(time_text, context.temp_allocator)
            raylib.GuiLabel(raylib.Rectangle{10, 120, 380, 20}, time_cstr)
        } else {
            drop_cstr := strings.clone_to_cstring("Drop MP3/OGG/WAV files to play", context.temp_allocator)
            raylib.GuiLabel(raylib.Rectangle{10, 50, 380, 20}, drop_cstr)
        }

        // Up Next Panel
        raylib.GuiLabel(raylib.Rectangle{380, 10, 240, 20}, "Up Next")

        list_builder: strings.Builder
        strings.builder_init(&list_builder, context.temp_allocator)
        for path, i in queue {
            if i > 0 {
                strings.write_byte(&list_builder, ';')
            }
            base := filepath.base(path)
            strings.write_string(&list_builder, base)
        }
        list_text := strings.to_string(list_builder)
        list_cstr := strings.clone_to_cstring(list_text, context.temp_allocator)

        scroll_index: i32 = 0
        active: i32 = -1
        raylib.GuiListView(raylib.Rectangle{380, 40, 240, 400}, list_cstr, &scroll_index, &active)

        raylib.EndDrawing()

        mem.free_all(context.temp_allocator)
    }

    if loaded {
        raylib.UnloadMusicStream(music)
        if file_name_allocated {
            delete(file_name)
        }
    }
}