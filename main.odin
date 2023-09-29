package sis

import "core:fmt"
import "vendor:glfw"
import gl "vendor:OpenGL"
import "core:math"
import "core:slice"

INIT_WIDTH   :: 1280
INIT_HEIGHT  :: 800
WINDOW_TITLE :: "Stvff's Image Splicer (getting somewhere)"

GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3
UI_SCALE :: 4
MINIMUM_SIZE :: [2]i32{200, 100}
UI_MINIMUM_SIZE :: [2]i32{MINIMUM_SIZE.x/UI_SCALE, MINIMUM_SIZE.y/UI_SCALE}

main :: proc() {
	if !bool(glfw.Init()) {
		fmt.eprintln("GLFW has failed to init")
		return
	} defer glfw.Terminate()

	window_size: [2]i32
	window_handle: glfw.WindowHandle
	{/* setup and open window */
//		glfw.WindowHint(glfw.MAXIMIZED, 1)
		glfw.WindowHint(glfw.RESIZABLE, 1)
		window_handle = glfw.CreateWindow(INIT_WIDTH, INIT_HEIGHT, WINDOW_TITLE, nil, nil)
		if window_handle == nil {
			fmt.eprintln("GLFW has failed to create a window")
			return
		}
		glfw.MakeContextCurrent(window_handle)

		glfw.SetFramebufferSizeCallback(window_handle, window_size_changed)
		glfw.SetWindowSizeLimits(window_handle, MINIMUM_SIZE.x, MINIMUM_SIZE.y, glfw.DONT_CARE, glfw.DONT_CARE)
		window_size.x, window_size.y = glfw.GetFramebufferSize(window_handle)
		gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)
	} defer glfw.DestroyWindow(window_handle)


	shader_program: u32
	{ /* compile and link shaders */
		success: i32
		log_backing: [512]u8
		log := cast([^]u8) &log_backing
		vertex_shader_source := #load("./vertex.glsl", cstring)
		fragment_shader_source := #load("./fragment.glsl", cstring)
		/* compile vertex shader */
		vertex_shader := gl.CreateShader(gl.VERTEX_SHADER)
		defer gl.DeleteShader(vertex_shader)
		gl.ShaderSource(vertex_shader, 1, &vertex_shader_source, nil)
		gl.CompileShader(vertex_shader)
		if gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &success); !bool(success) {
			gl.GetShaderInfoLog(vertex_shader, len(log_backing), nil, log)
			fmt.eprintln("vertex shader error:", cstring(log) )
		}
		/* compile fragment shader */
		fragment_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
		defer gl.DeleteShader(fragment_shader)
		gl.ShaderSource(fragment_shader, 1, &fragment_shader_source, nil)
		gl.CompileShader(fragment_shader)
		if gl.GetShaderiv(fragment_shader, gl.COMPILE_STATUS, &success); !bool(success) {
			gl.GetShaderInfoLog(fragment_shader, len(log_backing), nil, log)
			fmt.eprintln("fragment shader error:", cstring(log) )
		}
		/* link fragment shader */
		shader_program = gl.CreateProgram()
		gl.AttachShader(shader_program, vertex_shader)
		gl.AttachShader(shader_program, fragment_shader)
		gl.LinkProgram(shader_program)
		if gl.GetShaderiv(shader_program, gl.LINK_STATUS, &success); !bool(success) {
			gl.GetShaderInfoLog(shader_program, len(log_backing), nil, log)
			fmt.eprintln("shader linking error:", cstring(log) )
		}
	} defer gl.DeleteProgram(shader_program)

	vertex_buffer_o, vertex_array_o, element_buffer_o: u32
	{ /* do some frankly insane triangle definition stuff */
		vertices := [?]f32 {
			/* triangle vertices */  /* texture coords */
			-2.0, -1.0, 0.0,         -0.5, 0.0,  // bottom left
			 2.0, -1.0, 0.0,         1.5, 0.0,   // bottom right
			 0.0,  3.0, 0.0,         0.5,  2,    // top
		}
		indices := [?]u32 {
			0, 1, 2, // first
			0, 1, 2  // second
		}
		gl.GenVertexArrays(1, &vertex_array_o) /* this has info about how to read the buffer */
		gl.GenBuffers(1, &vertex_buffer_o)     /* this has the actual data */
		gl.GenBuffers(1, &element_buffer_o)    /* this is a decoupling layer for the actual data for re-using vertices */

		gl.BindVertexArray(vertex_array_o) /* global state indicators */
		gl.BindBuffer(gl.ARRAY_BUFFER, vertex_buffer_o)
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, element_buffer_o)

		gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices[0], gl.STATIC_DRAW)
		gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices[0], gl.STATIC_DRAW)

		gl.VertexAttribPointer(0, 3, gl.FLOAT, false, 5*size_of(f32), uintptr(0)) /* give info about how to read the buffer */
		gl.EnableVertexAttribArray(0) /* this zero is the same 0 as the first 0 in the call above */
		gl.VertexAttribPointer(1, 2, gl.FLOAT, false, 5*size_of(f32), uintptr(3*size_of(f32)))
		gl.EnableVertexAttribArray(1)
//		gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
	} defer {
		gl.DeleteVertexArrays(1, &vertex_array_o)
		gl.DeleteBuffers(1, &vertex_buffer_o)
		gl.DeleteBuffers(1, &element_buffer_o)
	}


	guil, imgl: Program_layer
	{/* initialize main program layers */
		guil.size = window_size/UI_SCALE
		imgl.size = window_size
//		fmt.println("sizes of texes", guil.size, imgl.size)
		guil.data = make([dynamic][4]byte, area(guil.size))
		imgl.data = make([dynamic][4]byte, area(imgl.size))
		guil.tex = guil.data[:]
		imgl.tex = imgl.data[:]
		draw_preddy_gradient(imgl)
	} defer {
		delete(guil.data)
		delete(imgl.data)
	}

	gui_tex_o, img_tex_o: u32
	{/* show the main program layers to the gpu */
		gl.GenTextures(1, &gui_tex_o)
		gl.BindTexture(gl.TEXTURE_2D, gui_tex_o)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST); gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, expand_values(guil.size), 0, gl.RGBA, gl.UNSIGNED_BYTE, &guil.tex[0])

		gl.GenTextures(1, &img_tex_o)
		gl.BindTexture(gl.TEXTURE_2D, img_tex_o)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST); gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, expand_values(imgl.size), 0, gl.RGBA, gl.UNSIGNED_BYTE, &imgl.tex[0])

		gl.UseProgram(shader_program)
		gl.Uniform1i(gl.GetUniformLocation(shader_program, "gui_texture"), 0)
		gl.Uniform1i(gl.GetUniformLocation(shader_program, "img_texture"), 1)
	}

	imgs := make([]Image, 2)
	defer {
		for img in imgs do delete(img.data)
		delete(imgs)
	}
	{
		imgs[0] = load_qoi("s/frame00100.qoi")
		imgs[1] = load_qoi("s/frame00100_sprite.qoi")
		imgs[1].pos = {40, 40}
	}

	mouse: Mouse

	t: u128 = 0
	for !glfw.WindowShouldClose(window_handle) { glfw.PollEvents()
		if glfw.GetKey(window_handle, glfw.KEY_ESCAPE) == glfw.PRESS do break
		{ /* if window size changes */
			new_window_size: [2]i32
			new_window_size.x, new_window_size.y = glfw.GetFramebufferSize(window_handle)
			if new_window_size != window_size {
				window_size = new_window_size
//				fmt.println("thing changed:", window_size)
				guil.size = vec_max(window_size/UI_SCALE, UI_MINIMUM_SIZE)
				imgl.size = vec_max(window_size, MINIMUM_SIZE)
//				fmt.println("gui size", guil.size)

				if area(guil.size) > len(guil.data) || area(imgl.size) > len(imgl.data) {
//					fmt.println("realloced")
					resize(&guil.data, area(guil.size))
					resize(&imgl.data, area(imgl.size))
					guil.tex = guil.data[:]
					imgl.tex = imgl.data[:]
				} else {
					guil.tex = guil.data[0:area(guil.size)]
					imgl.tex = imgl.data[0:area(imgl.size)]
				}

				slice.fill(guil.tex, 0)
//				slice.fill(imgl.tex, 0)
				draw_preddy_gradient(imgl)
//				fmt.println("---------------------- new frame -----------------")
			}
		}
		/* inputs */
		{/* mouse state */
			mouse.left  = glfw.GetMouseButton(window_handle, glfw.MOUSE_BUTTON_LEFT) == 1
			mouse.right = glfw.GetMouseButton(window_handle, glfw.MOUSE_BUTTON_RIGHT) == 1
			mouse.fpos.x, mouse.fpos.y = glfw.GetCursorPos(window_handle)
			mouse.pos = vec_clamp({i32(mouse.fpos.x), window_size.y - i32(mouse.fpos.y)}/UI_SCALE, {0, 0}, guil.size - 1)
		} defer {
			mouse.left_was = mouse.left
			mouse.right_was = mouse.right
			mouse.is_on = .nothing
		}

		/* drawing */
		slice.fill(guil.tex, 0)
//		draw_text_in_box(guil, mouse.pos, "Hello World!")
//		draw_text_in_box(guil, mouse.pos + {0, 9}, "The quick brown fox jumped over the lazy dog")
//		draw_text_in_box(guil, mouse.pos + {0, 18}, "I'm just offsetting every box, and clamping the position")
//		draw_ui_box(guil, cursor_pos + {-5, 0}, {50, 50})

		{/* draw_images_bins and manage layers */
			bin_height :: 18
			arrow_clr := UI_BORDER_COLOR
			activated_arrow_clr := [4]byte{230, 50, 50, 255}
			swap := -1
			y: i32 = guil.size.y/2 + (i32(len(imgs))*(bin_height + 1))/2
			#reverse for img, i in imgs {
				box_size := [2]i32{i32(len(img.name))*4 + SMALL_ARROW_SIZE.x + 4, bin_height}
				actual_pos := draw_ui_box(guil, {5, y}, box_size)
				draw_text(guil, actual_pos + {SMALL_ARROW_SIZE.x + 3, 9}, img.name)

				if i < len(imgs) - 1 {
				if is_in_rect(mouse.pos, actual_pos + {2, bin_height - 7}, SMALL_ARROW_SIZE) {
					draw_small_arrow(guil, actual_pos + {2, bin_height - 7}, .up, activated_arrow_clr)
					if !mouse.left && mouse.left_was do swap = i + 1
				} else do draw_small_arrow(guil, actual_pos + {2, bin_height - 7}, .up, arrow_clr)}

				if i > 0 {
				if is_in_rect(mouse.pos, actual_pos + {2, 2}, SMALL_ARROW_SIZE) {
					draw_small_arrow(guil, actual_pos + {2, 2}, .down, activated_arrow_clr)
					if !mouse.left && mouse.left_was do swap = i
				} else do draw_small_arrow(guil, actual_pos + {2, 2}, .down, arrow_clr)}

				y -= bin_height + 1
			}

			if swap > 0 {
				temp := imgs[swap]
				imgs[swap] = imgs[swap - 1]
				imgs[swap - 1] = temp
				draw_preddy_gradient(imgl)
				mouse.is_on = .image_bin_up_down_button
			}
		}

		{
			dial_pos := draw_ui_box(guil, guil.size/2, {49, 49})
			dial_middle := dial_pos + {24, 24}
			r := mouse.pos - dial_middle
			sproing: int
			for i in 0..<10 {
				on_circle := [2]i32{
					i32(20*math.sin(math.TAU*f64(i)/10)),
					i32(20*math.cos(math.TAU*f64(i)/10))
				}
				theta := math.mod(1.8 - (math.PI + math.atan2(f64(r.y), f64(r.x)))/math.TAU, 1)
				fmt.println(theta, f64(i)/10)

				char_clr := UI_TEXT_COLOR
				if f64(i)/10 < theta && f64(i + 1)/10 >= theta {
					char_clr = RED
					sproing = i
				}
				draw_char(guil, dial_middle + on_circle - {1, 3}, rune('0' + i), char_clr)
//				draw_line(guil, dial_middle, on_circle.yx, PASTEL_BLUE)
			}
			line_len :: 16
			if magsq(r) < line_len*line_len do r = line_len*r
			if r == 0 do r = {0, 1}
			sv := [2]i32{
				i32(line_len*math.sin(math.TAU*f64(sproing)/10)),
				i32(line_len*math.cos(math.TAU*f64(sproing)/10))
			}
			draw_line(guil, dial_middle, sv, UI_TEXT_COLOR)
			draw_line(guil, dial_middle, line_len*r/mag(r), UI_TEXT_COLOR)
		}






		draw_images(imgl, imgs)


		/* render to screen with openGL */
		gl.ClearColor(0.5, 0.5, 0.5, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		gl.ActiveTexture(gl.TEXTURE0)
		gl.BindTexture(gl.TEXTURE_2D, gui_tex_o)
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, expand_values(guil.size), 0, gl.RGBA, gl.UNSIGNED_BYTE, &guil.tex[0])
		gl.ActiveTexture(gl.TEXTURE1)
		gl.BindTexture(gl.TEXTURE_2D, img_tex_o)
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, expand_values(imgl.size), 0, gl.RGBA, gl.UNSIGNED_BYTE, &imgl.tex[0])

		gl.UseProgram(shader_program)
		gl.BindVertexArray(vertex_array_o)
		gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)

		t += 1
	glfw.SwapBuffers(window_handle) }
}

area :: proc(v: [2]i32) -> int {
	return int(v.x)*int(v.y)
}

vec_max :: proc(v: [2]i32, m: [2]i32) -> [2]i32 {
	return [2]i32{max(v.x, m.x), max(v.y, m.y)}
}

vec_clamp :: proc(v: [2]i32, l, h: [2]i32) -> [2]i32 {
	return {
		clamp(v.x, l.x, h.x),
		clamp(v.y, l.y, h.y)
	}
}

mag :: proc(v: [2]i32) -> i32 {
	return cast(i32) math.sqrt(f64(v.x*v.x + v.y*v.y))
}
magsq :: proc(v: [2]i32) -> i32 {
	return v.x*v.x + v.y*v.y
}

// TODO: place these in all the places where it should be
is_in_space :: proc(point_pos, size: [2]i32) -> bool {
	if 0 > point_pos.x || point_pos.x >= size.x do return false
	if 0 > point_pos.y || point_pos.y >= size.y do return false
	return true
}
is_in_rect :: proc(point_pos, rect_pos, rect_size: [2]i32) -> bool {
	if rect_pos.x > point_pos.x || point_pos.x >= rect_pos.x + rect_size.x do return false
	if rect_pos.y > point_pos.y || point_pos.y >= rect_pos.y + rect_size.y do return false
	return true
}

window_size_changed :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
}
