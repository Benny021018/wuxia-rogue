shader_type canvas_item;
// 墨色雙色調：依亮度在 dark 與 light 間插值（未選角色、背景圖）

uniform vec4 dark : source_color = vec4(0.02, 0.016, 0.027, 1.0);
uniform vec4 light : source_color = vec4(0.44, 0.42, 0.46, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = COLOR;
	float l = dot(c.rgb, vec3(0.3, 0.55, 0.15));
	vec3 toned = mix(dark.rgb, light.rgb, l);
	COLOR = vec4(mix(c.rgb, toned, amount), c.a);
}
