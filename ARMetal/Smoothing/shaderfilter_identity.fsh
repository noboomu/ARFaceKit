varying vec2 hdConformedUV;
varying vec2 uv;
uniform sampler2D inputImage;
uniform int passIndex;
uniform vec2 uRenderSize;
uniform float uTime;

void main() {
  gl_FragColor = texture2D(inputImage, uv);
}
