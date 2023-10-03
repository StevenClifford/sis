package sis

import "core:fmt"

Image :: struct {
	name: string,
	pos: [2]i32,
	size: [2]i32,
	data: [dynamic][4]byte,

	scale: f64
}

draw_images :: proc(l: Program_layer, imgs: []Image, on_screen: bool) {
	if len(imgs) == 0 {
		draw_preddy_gradient(l)
		return
	}
	origin := imgs[0].pos
	if on_screen do origin += l.size/2 - imgs[0].size/2

	for y in 0..<l.size.y {
	for x in 0..<l.size.x {
	tpix := [4]byte{255 - byte((210*x)/l.size.x), 0, 255 - byte((210*(l.size.y - 1 - y))/l.size.y), 255} if on_screen else 0
	for img, n in imgs {
		o := origin if n != 0 else origin - imgs[0].pos
		p := [2]i32{x, y} - o - img.pos
		if !is_in_space(p, img.size) do continue
		ipix := img.data[p.x + p.y*img.size.x]
		a := f64(ipix.a)/255
		tpix = [4]byte{
			byte(a*f64(ipix.r) + (1-a)*f64(tpix.r)),
			byte(a*f64(ipix.g) + (1-a)*f64(tpix.g)),
			byte(a*f64(ipix.b) + (1-a)*f64(tpix.b)),
			255
		}
	}
	if on_screen do l.tex[x + (l.size.y-1 - y)*l.size.x] = tpix
	else do l.tex[x + y*l.size.x] = tpix
	}}
}

draw_preddy_gradient :: proc(layer: Program_layer){
	y: i32 = 0
	for &pix, i in layer.tex {
		pix = [4]byte{255 - byte((210*y)/layer.size.x), 0, 255 - byte((210*i) / len(layer.tex)), 255}
		y = (y + 1)%layer.size.x
//		pix = [4]byte{0, 0, 255 - byte((255*i) / len(imgl.tex)), 255}
//		pix = {0, 0, 63, 255}
	}
}

import "core:slice"
import "core:image/qoi"
import "core:bytes"
load_qoi :: proc(name: string) -> (my_img: Image, ero: bool) {
	qimg, err := qoi.load(name) // TODO: check if file exists/is proper
	if err != nil {
		fmt.eprintln("load_qoi: file not found")
		return my_img, false
	}
	defer qoi.destroy(qimg)
	if qimg.channels != 4 {
		fmt.eprintln("load_qoi: wrong amount of channels")
		return my_img, false
	}
	if qimg.depth != 8 {
		fmt.eprintln("load_qoi: wrong depth")
		return my_img, false
	}
	my_img.name = name
	my_img.size.x = i32(qimg.width)
	my_img.size.y = i32(qimg.height)
	my_img.data = make([dynamic][4]byte, area(my_img.size))
	buf := slice.reinterpret([]byte, my_img.data[:])
	copy(buf, bytes.buffer_to_bytes(&qimg.pixels))
	return my_img, true
}

import "core:image"
write_qoi :: proc(img: Image) {
	buu := make([dynamic]byte, area(img.size)*4)
	defer delete(buu)
	aaa := slice.reinterpret([]byte, img.data[:])
	copy(buu[:], aaa)
	forqoi := image.Image{
		width = int(img.size.x),
		height = int(img.size.y),
		channels = 4,
		depth = 8,
		pixels = bytes.Buffer {
			buf = buu
		}
	}
	qoi.save(img.name, &forqoi)
}