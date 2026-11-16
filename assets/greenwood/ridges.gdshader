shader_type sky;
// 綠林天空：淡藍天頂、霧白地平線，兩層遠山越遠越淡（參考《綠林山寨》組裝圖的空氣遠近感）。

float ridge(vec2 dir, float offset) {
	float t = atan(dir.y, dir.x);
	return 0.5 + 0.22 * sin(5.0 * t + offset) + 0.13 * sin(11.0 * t - offset)
		+ 0.09 * sin(23.0 * t + offset) + 0.035 * sin(57.0 * t);
}

void sky() {
	float elevation = EYEDIR.y;
	vec3 horizon = vec3(0.80, 0.84, 0.85);
	vec3 zenith = vec3(0.40, 0.56, 0.72);
	vec3 color = mix(horizon, zenith, smoothstep(0.0, 0.7, elevation));
	float far_ridge = ridge(EYEDIR.xz, 2.1) * 0.42;
	float near_ridge = ridge(EYEDIR.xz, 4.5) * 0.26;
	vec3 far_col = mix(vec3(0.60, 0.68, 0.72), horizon, 0.25);
	vec3 near_col = vec3(0.44, 0.53, 0.56);
	color = mix(mix(far_col, horizon, smoothstep(far_ridge - 0.2, far_ridge, elevation) * 0.0), color, smoothstep(far_ridge - 0.003, far_ridge + 0.003, elevation));
	color = mix(near_col, color, smoothstep(near_ridge - 0.002, near_ridge + 0.002, elevation));
	// 山谷霧帶：近地平線處把山腳洗白
	color = mix(color, horizon, (1.0 - smoothstep(0.0, 0.12, abs(elevation - 0.03))) * 0.65);
	COLOR = color;
}
