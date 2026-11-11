shader_type sky;

float ridge(vec2 dir, float offset) {
	float t = atan(dir.y, dir.x);
	return 0.5 + 0.22 * sin(5.0 * t + offset) + 0.13 * sin(11.0 * t - offset)
		+ 0.09 * sin(23.0 * t + offset) + 0.035 * sin(57.0 * t);
}

void sky() {
	float elevation = EYEDIR.y;
	vec3 color = mix(vec3(0.36, 0.45, 0.44), vec3(0.11, 0.20, 0.24), smoothstep(0.0, 0.8, elevation));
	float far_ridge = ridge(EYEDIR.xz, 2.1) * 0.55;
	float near_ridge = ridge(EYEDIR.xz, 4.5) * 0.32;
	color = mix(vec3(0.20, 0.30, 0.31), color, smoothstep(far_ridge - 0.003, far_ridge + 0.003, elevation));
	color = mix(vec3(0.11, 0.19, 0.19), color, smoothstep(near_ridge - 0.002, near_ridge + 0.002, elevation));
	COLOR = color;
}
