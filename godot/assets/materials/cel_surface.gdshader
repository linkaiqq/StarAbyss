shader_type spatial;
render_mode specular_disabled;

uniform vec4 base_color : source_color = vec4(0.3, 0.5, 0.6, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.46, 0.57, 0.72, 1.0);
uniform vec4 glow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float glow_energy : hint_range(0.0, 2.0) = 0.0;
uniform float shade_threshold : hint_range(0.0, 1.0) = 0.35;
uniform float highlight_threshold : hint_range(0.0, 1.0) = 0.75;
// P7 telegraph readability: a per-instance charge-up glow driven by
// ActorPresentation from the enemy brain's authoritative windup clock. Because it
// is an instance uniform, the shared cached cel materials stay untouched and only
// the charging actor lights up — it never implies a larger damage area.
uniform vec4 threat_color : source_color = vec4(1.0, 0.45, 0.14, 1.0);
uniform float threat_strength : hint_range(0.0, 4.0) = 1.7;
instance uniform float threat_pulse = 0.0;

void fragment() {
	float threat = clamp(threat_pulse, 0.0, 1.0);
	ALBEDO = mix(base_color.rgb, threat_color.rgb, threat * 0.32);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = glow_color.rgb * glow_energy + threat_color.rgb * threat_strength * threat;
}

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float band = mix(0.40, 0.72, step(shade_threshold, facing));
	band = mix(band, 1.0, step(highlight_threshold, facing));
	vec3 tint = mix(shadow_tint.rgb, vec3(1.0), step(shade_threshold, facing));
	DIFFUSE_LIGHT += tint * LIGHT_COLOR * band * ATTENUATION / PI;
}
