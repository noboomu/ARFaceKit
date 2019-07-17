// ****
// These are set by the editor
// We are using #defines to get both - if the feature
// needs to be turned on and the actual value of that feature
// ----
// The values below are [0 1] range
// This controls the amount of smoothing
//#define SMOOTHING_FACTOR 0.5
// This controls how much to brighten the eyes
//#define EYE_BRIGHTENING_FACTOR 0.3
// This controls the enhancement of the whites of teeth
//#define TEETH_WHITENING_FACTOR 0.2
// ---
//#define APPLY_COLOR_LUT 0
//#define APPLY_FULLSCREEN 0
//#define colorlut  colorlut // set this to the LUT's file name without its extension, e.g. colorlut.png
//#define colorlut_height  (16.0)
//#define colorlut_width  (256.0)
// ****

// This switches between our two algorithms, not
// currently set by the editor
#define BRIGHT_BASE 0

varying vec2 hdConformedUV;
varying vec2 uv;
uniform sampler2D inputImage;
uniform int passIndex;
uniform vec2 uInputImageSize;
uniform vec2 uRenderSize;
uniform float uTime;
uniform float skinSmoothingFactor;

uniform sampler2D colorlut;
uniform sampler2D faceMask;
uniform sampler2D passBuffer1;
uniform sampler2D passBuffer2;
uniform sampler2D passBuffer3;

float rgb2luma(vec3 color) {
  return dot(vec3(0.299, 0.587, 0.114), color);
}

float scurve(float v) {
  // Hermite cubic s-curve
  return v * v * (3.0 - 2.0 * v);
}

vec3 scurve(vec3 v) {
  // Hermite cubic s-curve
  return v * v * (3.0 - 2.0 * v);
}

vec3 scurve2(vec3 v) {
  return -0.4014452027 * v * v + 1.401445203 * v;
}

vec4 brighten(vec4 origPix, vec4 targetPix) {
  // Pass through the pixel values through a s-curve
  float lumaPix = scurve(rgb2luma(origPix.rgb));
  // Use the s-curved values to weight the whites
  return mix(origPix, targetPix, lumaPix);
}

vec4 hardLight(vec4 inpColor) {
  float color = inpColor.b;
  int i;
  for(i = 0; i < 3; i++) {
    if(color <= 0.5)
      color = color * color * 2.0;
    else
      color = 1.0 - ((1.0 - color)*(1.0 - color) * 2.0);
  }
  return vec4(vec3(color), inpColor.a);
}

float highPassLum(vec4 base, vec4 mean, float threshold) {
  float delta = rgb2luma(base.xyz - mean.xyz);

  float highpass = clamp((delta + threshold) / (2.0 * threshold), 0.0, 1.0);

  // apply a s-curve to amplify the low and high tones
  highpass = scurve(highpass);

  // shift so we capture both the low and high tones in the same range
  highpass = 2.0 * abs(highpass - 0.5);

  return highpass;
}

#ifdef APPLY_COLOR_LUT
// apply a color LUT to the input color
vec4 colorLUT(vec4 color, sampler2D lut) {
  // this should come from a real uniform from the engine
  // hard-coded here for now
  const vec4 uLutSize = vec4(colorlut_width, colorlut_height, 1.0/colorlut_width, 1.0/colorlut_height);

  vec3 scaledColor = color.xyz * (uLutSize.y - 1.0);
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
#endif

void main() {
  // Loop indices
  int i, j;
  vec2 offset;

  if (passIndex == 0) {
    vec4 mean4;
    vec2 duv = 1.0 / uInputImageSize;

    mean4  = texture2D(inputImage, uv + vec2(-duv.x, -duv.y));
    mean4 += texture2D(inputImage, uv + vec2( duv.x, -duv.y));
    mean4 += texture2D(inputImage, uv + vec2(-duv.x,  duv.y));
    mean4 += texture2D(inputImage, uv + vec2( duv.x,  duv.y));

    mean4 *= 0.25;

    // passBuffer1
    gl_FragColor = mean4;
  } else if (passIndex == 1) {
    vec4 mean8;
    vec2 duv = 2.0 / uInputImageSize;

    mean8  = texture2D(passBuffer1, uv + vec2(-duv.x, -duv.y));
    mean8 += texture2D(passBuffer1, uv + vec2( duv.x, -duv.y));
    mean8 += texture2D(passBuffer1, uv + vec2(-duv.x,  duv.y));
    mean8 += texture2D(passBuffer1, uv + vec2( duv.x,  duv.y));

    mean8 *= 0.25;
    //passBuffer2
    gl_FragColor = mean8;
  } else if (passIndex == 2) {
    vec2 duv = 4.0 / uInputImageSize;

    vec4 tex0 = texture2D(passBuffer2, uv + vec2(-duv.x, -duv.y));
    vec4 tex1 = texture2D(passBuffer2, uv + vec2( duv.x, -duv.y));
    vec4 tex2 = texture2D(passBuffer2, uv + vec2(-duv.x,  duv.y));
    vec4 tex3 = texture2D(passBuffer2, uv + vec2( duv.x,  duv.y));

    // passBuffer3
    gl_FragColor = 0.25 * (tex0 + tex1 + tex2 + tex3);
  } else if (passIndex == 3) {
    vec4 base = texture2D(inputImage, uv);
    vec4 face = texture2D(faceMask, uv);
    vec4 mean8 = texture2D(passBuffer2, uv);
    vec4 blur = texture2D(passBuffer3, uv);

#ifdef SMOOTHING_FACTOR
    // This switches between the two algos that either use a
    // brightened image or a blurred image as the one to blend with
    // using the highpass
#if BRIGHT_BASE
    // This uses an image that is brightned using a s-curve as the blend image
    // the intuition is that the blemishes are darker than skin pixels and
    // by brightening them, we can get them to be closer to skin color
    const float brightSmoothLow = 0.0;
    // We want the high to go from 0.1 - 0.5 (based on emperical evidence)
    // for input from 0-1
    float brightSmoothHigh = skinSmoothingFactor * (0.5 - 0.1) + 0.1;
    float brightSmoothFactorInternal = (1.0-SMOOTHING_FACTOR) *
    (brightSmoothHigh - brightSmoothLow) + brightSmoothLow;
    vec4 delta =  vec4((base.rgb - mean8.rgb + vec3(0.5,0.5,0.5)), base.a);
    vec4 highpass = clamp(delta + brightSmoothFactorInternal, 0.0, 1.0);
    highpass = hardLight(highpass);
    vec4 smoothed = mix(vec4(scurve2(base.rgb), 1.0), base, highpass);
#else
    // This uses a blurred version of the image to blend with the highpass
    // output
    const float blurSmoothLow = 0.0;
    // We want the high to go from 0.1 - 0.5 (based on emperical evidence)
    // for input from 0-1
    float blurSmoothHigh = skinSmoothingFactor * (1.0 - 0.1) + 0.1;
    float blurSmoothFactorInternal = SMOOTHING_FACTOR *
    (blurSmoothHigh - blurSmoothLow) + blurSmoothLow;
    float highpass = highPassLum(base, blur, blurSmoothFactorInternal);
    vec4 smoothed = mix(mean8, base, highpass);
#endif
    vec4 mean4 = texture2D(passBuffer1, uv);
    // Compute the difference of the image and slightly blurred version
    vec4 diff = base - mean4;

    // saturate slightly by blending towards the s-curve
    smoothed.xyz = mix(smoothed.xyz, scurve(smoothed.xyz), 0.125);

    // Add the high frequencies back in based on the contrast
    // The skin smoothing factor maps to both the internal smoothing
    // factor and the internal high frequency addition contrast
    // This contrast setting governs how much high frequency components
    // to bring in
    const float highFreqLow = 0.0;
    const float highFreqHigh = 0.6;
    const float highFreqContrastInternal = SMOOTHING_FACTOR *
    (highFreqHigh - highFreqLow) + highFreqLow;
    vec4 outputPix = smoothed + highFreqContrastInternal * diff;
#else
    vec4 outputPix = base;
#endif // SMOOTHING_FACTOR

    // Skin smoothing only for the face region
#ifndef APPLY_FULLSCREEN
    outputPix = mix(base, outputPix, face.x);
#endif

#ifdef EYE_BRIGHTENING_FACTOR
    const float eyeContrastLow = 1.0;
    const float eyeContrastHigh = 1.8;
    const float eyesContrastInternal = EYE_BRIGHTENING_FACTOR *
    (eyeContrastHigh - eyeContrastLow) + eyeContrastLow;
    // How much to enhance the whites
    // Up the contrast by multiplying by a factor
    vec4 enhancedPix = outputPix * eyesContrastInternal;
    // Pull the color pix towards the enhancedPix by using
    // the saturated s-curve as the blend factor
    vec4 brigtenPix = brighten(outputPix, enhancedPix);
    // Blend using eye mask
    outputPix =  mix(outputPix, brigtenPix, face.y);
#endif

#ifdef TEETH_WHITENING_FACTOR
    const float teethContrastLow = 1.0;
    const float teethContrastHigh = 1.5;
    const float teethContrastInternal = TEETH_WHITENING_FACTOR *
    (teethContrastHigh - teethContrastLow) + teethContrastLow;
    // Up the contrast by multiplying by a factor
    vec4 enhancedPix2 = outputPix * teethContrastInternal;
    // Increase the saturation so as to not brighten the lips so much
    vec4 saturated = vec4(mix(vec3(0.5), outputPix.rgb, 1.05), 1.0);
    // Pass through the pixel values through a s-curve
    float lumaPix = scurve(rgb2luma(outputPix.rgb));
    // Use the s-curved values to weight the whites more
    vec4 brigtenPix2 = mix(saturated, enhancedPix2, lumaPix);
    // Blend using lips mask
    outputPix = mix(outputPix, brigtenPix2, face.z);
#endif

#ifdef APPLY_COLOR_LUT
    outputPix = colorLUT(outputPix, colorlut);
#endif
    gl_FragColor = outputPix;
  }
}
