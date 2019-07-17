attribute vec3 a_Position;
attribute vec2 a_TexCoords;

uniform mat4 u_MVPMatrix;
uniform mat4 u_MVMatrix;
uniform mat4 u_NormalMatrix;

varying vec2 v_TexCoords;

vec4 projectedPosition() {
  return u_MVPMatrix * vec4(a_Position, 1.0);
}

void main() {
  gl_Position = projectedPosition();
  v_TexCoords = a_TexCoords;
}
