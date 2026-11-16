shader_type spatial;
// 地坪：Blender 匯出的頂點色 R=草 G=岩 B=路面（壓暗），以世界座標每 6m 平鋪。
uniform sampler2D dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile_m = 6.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / tile_m;
	vec3 w = clamp(COLOR.rgb, 0.0, 1.0);
	vec3 d = texture(dirt, uv).rgb * mix(vec3(1.0), vec3(0.8, 0.74, 0.68), w.b);
	vec3 c = mix(d, texture(grass, uv * 1.3).rgb, w.r);
	c = mix(c, texture(rock, uv * 0.7).rgb, w.g);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
