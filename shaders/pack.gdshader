shader_type spatial;
render_mode cull_disabled;
uniform sampler2D cover : source_color, filter_linear;
uniform sampler2D back_cover : source_color, filter_linear;
uniform sampler2D foil_reference : source_color, filter_linear;
uniform float progress = 0.0;
uniform bool strip = false;
varying vec3 rest;
void vertex() {
 rest = VERTEX;
 if (strip) {
  float across = clamp((VERTEX.x+0.466)/0.932,0.0,1.0);
  float lifted = smoothstep(0.0,0.18,progress-across*0.8);
  VERTEX.y += lifted*(0.16+0.24*(1.0-across));
  VERTEX.z += lifted*0.18;
  VERTEX.x -= lifted*0.12;
 }
}
void fragment() {
 float cut = 0.718 + 0.004*sin(rest.x*180.0);
 if (strip && rest.y < cut) { discard; }
 if (!strip && rest.y >= cut) { discard; }
 bool silver = abs(rest.y) > 0.715;
 vec3 base;
 if (silver) {
  // Retain the supplied model's actual crimped-foil texture and UVs.
  vec3 reference = texture(foil_reference,UV).rgb;
  float grey = dot(reference,vec3(0.299,0.587,0.114));
  base = vec3(grey)*vec3(0.96,0.98,1.0);
  METALLIC = 0.38; ROUGHNESS = 0.62; SPECULAR = 0.16;
 } else {
  vec2 art_uv = vec2(rest.x/0.932+0.5,0.5-rest.y/1.43);
  if (UV.x < 0.5) { base = texture(cover,art_uv).rgb; }
  else { art_uv.x = 1.0-art_uv.x; base = texture(back_cover,art_uv).rgb; }
  METALLIC = 0.0; ROUGHNESS = 0.94; SPECULAR = 0.0;
 }
 ALBEDO = base*0.82;
}
