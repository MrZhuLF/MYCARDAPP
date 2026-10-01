shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
uniform vec4 aura_color : source_color = vec4(1.0);
void fragment() {
 vec2 p = abs(UV-0.5)*2.0;
 float glow = pow(max(0.0,1.0-length(p*vec2(0.88,0.75))),1.7);
 float rays = 0.75+0.25*sin(atan(UV.y-0.5,UV.x-0.5)*18.0+TIME*0.8);
 ALBEDO = aura_color.rgb;
 ALPHA = glow*rays*0.48;
}
