shader_type canvas_item;
render_mode blend_premul_alpha;
// One full-screen pass over the background art: drifting fog, the game's own
// weather (rain, snow, ash, embers, petals), film grain, a flickering bulb or
// static, and a vignette. Cheap enough for the Compatibility renderer.
// mode: 0 none, 1 mist, 2 rain, 3 snow, 4 ash, 5 embers, 6 static, 7 petals, 8 flicker

uniform int mode = 1;
uniform vec4 tint : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform float fog_amount = 0.35;
uniform float particle_amount = 1.0;
uniform float grain = 0.06;
uniform float speed = 1.0;
uniform vec2 aspect = vec2(1.6, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// Falling or rising specks on a jittered grid. dir.y < 0 falls (SCREEN_UV.y grows downwards).
float specks(vec2 uv, float grid, vec2 dir, float size, float t, float seed) {
	vec2 p = uv * grid + dir * t;
	p.x += sin(p.y * 0.35 + seed) * 0.6;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float h = hash(cell + seed);
	if (h > 0.55) return 0.0;
	vec2 c = vec2(hash(cell + seed + 3.1), hash(cell + seed + 7.7)) * 0.8 + 0.1;
	float d = length((f - c) * vec2(1.0, 1.0));
	return smoothstep(size, 0.0, d) * (0.4 + 0.6 * hash(cell + 1.3));
}

float streaks(vec2 uv, float grid, float t, float seed) {
	vec2 p = uv * vec2(grid, grid * 0.12);
	p.x += p.y * 0.18;
	p.y -= t * 3.2;   // SCREEN_UV.y grows downwards: subtracting makes the streaks fall
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float h = hash(cell + seed);
	if (h > 0.18) return 0.0;
	float x = hash(cell + seed + 2.0) * 0.8 + 0.1;
	return smoothstep(0.035, 0.0, abs(f.x - x)) * smoothstep(0.0, 0.3, f.y) * smoothstep(1.0, 0.6, f.y);
}

vec4 over(vec4 acc, vec3 c, float a) {
	return vec4(c * a + acc.rgb * (1.0 - a), a + acc.a * (1.0 - a));
}

void fragment() {
	vec2 uv = SCREEN_UV * aspect;
	float t = TIME * speed;
	vec4 acc = vec4(0.0);   // premultiplied

	// Fog: two layers of slow fbm drifting sideways, heavier low on the screen.
	if (mode > 0) {
		float f1 = fbm(uv * 1.6 + vec2(t * 0.025, t * 0.01));
		float f2 = fbm(uv * 3.1 - vec2(t * 0.04, -t * 0.008));
		float fog = smoothstep(0.35, 0.95, f1 * 0.65 + f2 * 0.45) * fog_amount;
		fog *= mix(0.55, 1.15, SCREEN_UV.y);
		acc = over(acc, tint.rgb, clamp(fog, 0.0, 1.0));
	}

	float p = 0.0;
	vec3 pcol = vec3(0.92, 0.92, 0.9);
	if (mode == 2) {
		p = streaks(uv, 34.0, t, 1.0) * 0.55 + streaks(uv * 1.7, 34.0, t * 1.3, 5.0) * 0.35;
		pcol = vec3(0.8, 0.86, 0.92);
	} else if (mode == 3) {
		p = specks(uv, 9.0, vec2(0.15, -0.55), 0.09, t, 1.0) + specks(uv, 16.0, vec2(0.1, -0.8), 0.07, t, 4.0) * 0.6;
	} else if (mode == 4) {
		p = specks(uv, 11.0, vec2(0.25, -0.18), 0.06, t, 2.0) * 0.8 + specks(uv, 22.0, vec2(0.2, -0.25), 0.05, t, 9.0) * 0.4;
		pcol = vec3(0.75, 0.72, 0.68);
	} else if (mode == 5) {
		p = specks(uv, 12.0, vec2(-0.1, 0.35), 0.05, t, 3.0) + specks(uv, 24.0, vec2(-0.05, 0.5), 0.04, t, 6.0) * 0.5;
		p *= 0.6 + 0.4 * sin(t * 3.0 + uv.x * 20.0);
		pcol = vec3(1.0, 0.45, 0.15);
	} else if (mode == 7) {
		p = specks(uv, 7.0, vec2(0.35, -0.3), 0.08, t, 4.0) * 0.8;
		pcol = min(tint.rgb * 1.6, vec3(1.0));
	}
	acc = over(acc, pcol, clamp(p * particle_amount, 0.0, 1.0) * 0.9);

	if (mode == 6) {
		float s = hash(SCREEN_UV * 900.0 + fract(TIME) * 37.0);
		float band = step(0.985, hash(vec2(floor(SCREEN_UV.y * 120.0), floor(TIME * 12.0))));
		acc = over(acc, vec3(s), 0.07 + band * 0.22);
	}
	if (mode == 8) {
		float flick = step(0.93, hash(vec2(floor(TIME * 9.0), 1.0))) * 0.55;
		acc = over(acc, vec3(0.0), flick);
	}

	// Vignette, then film grain on top.
	vec2 v = SCREEN_UV - 0.5;
	float vig = smoothstep(0.35, 0.95, length(v * vec2(1.1, 1.3)));
	acc = over(acc, vec3(0.0), vig * 0.85);
	float g = (hash(SCREEN_UV * 1300.0 + fract(TIME * 0.7) * 91.0) - 0.5) * grain;
	acc.rgb += vec3(g) * 0.5;
	acc.a = max(acc.a, abs(g));

	COLOR = acc;
}
