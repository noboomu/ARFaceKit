#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 v_TexCoords;

uniform sampler2D u_Texture;
uniform float u_Alpha;
uniform float u_Value;

void main() {
  vec4 color = texture2D(u_Texture, v_TexCoords);
  color.rgb *= u_Value;
  color.a *= u_Alpha;
  gl_FragColor = color;
}
