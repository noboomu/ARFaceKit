// varying vec2 uv;
// uniform sampler2D inputImage;
// uniform sampler2D colorlut;

float colorlut_width = 512.0;
float colorlut_height = 512.0;


vec4 colorLUT(vec4 color, sampler2D lut) {
  // this should come from a real uniform from the engine
  // hard-coded here for now
  vec4 uLutSize = vec4(colorlut_width, colorlut_height, 1.0/colorlut_width, 1.0/colorlut_height);

  vec3 scaledColor = color.xyz * uLutSize.y;
  
  float bFrac = fract(scaledColor.z);

  // offset by 0.5 pixel and fit within range [0.5, width-0.5]
  // to prevent bilinear filtering with adjacent colors

  vec2 texc = (0.5 + scaledColor.xy) * uLutSize.zw;


  // offset by the blue slice
  texc.x += (scaledColor.z - bFrac) * uLutSize.w;

  // sample the 2 adjacent blue slices
  vec3 b0 = texture2D(lut, texc).xyz;
  vec3 b1 = texture2D(lut, vec2(texc.x + uLutSize.w, texc.y)).xyz;

  // blend between the 2 adjacent blue slices
  color.xyz = mix(b0, b1, bFrac);

  return color;
}


void main() {



    vec2 uv = (gl_FragCoord.xy / iResolution.xy);



    vec4 outputPix = texture2D(iChannel0, uv);
 
  outputPix = colorLUT(outputPix, iChannel1);
 
    gl_FragColor = outputPix;
 
}

