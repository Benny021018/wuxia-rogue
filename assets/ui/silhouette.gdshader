shader_type canvas_item;
// 招式剪影：把去背剪影塗成 fill_color，外圈描 rim_color（rim_px＝貼圖像素）
uniform vec4 fill_color : source_color = vec4(0.03, 0.02, 0.035, 1.0);
uniform vec4 rim_color : source_color = vec4(0.953, 0.929, 0.894, 1.0);
uniform float rim_px = 4.0;

void fragment() {
	float a = texture(TEXTURE, UV).a;
	float m = a;
	if (rim_px > 0.0) {
		vec2 px = TEXTURE_PIXEL_SIZE * rim_px;
		for (int i = 0; i < 16; i++) {
			float ang = float(i) * 0.3927;
			m = max(m, texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * px).a);
		}
	}
	vec4 col = mix(rim_color, fill_color, smoothstep(0.35, 0.75, a));
	COLOR = vec4(col.rgb, m * col.a);
}
