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

varying vec2 hdConformedUV;
varying vec2 uv;
uniform sampler2D inputImage;
uniform int passIndex;
uniform vec2 uInputImageSize;
uniform vec2 uRenderSize;
uniform float uTime;

uniform sampler2D colorlut;
uniform sampler2D faceMask;
uniform sampler2D passBuffer1;
uniform sampler2D passBuffer2;
uniform sampler2D passBuffer3;
uniform sampler2D passBuffer4;

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

vec4 brighten(vec4 origPix, vec4 targetPix) {
  // Pass through the pixel values through a s-curve
  float lumaPix = rgb2luma(scurve(origPix.rgb));
  // Use the s-curved values to weight the whites
  return mix(origPix, targetPix, lumaPix);
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

float scaleValue(float inVal, float outValMin, float outValMax) {
  float scale = outValMax - outValMin;
  return inVal * scale + outValMin;
}

// An implementation of the Fast Guided Filter
// - We operate at 1/8 the resolution of the original image
// - We do full color rgb guide
// - We add back high frequency components in to preserve things
// like facial hair
// Algorithm -
// ip4 = subsample(ip, 4)
// ip4b = subsample(ip4, 4) with blur 2x2
// since 1/16 gives bad output
// r' = r/4
// meanIp = fmean(p, r'), fmean(I, r')
// corrIp = fmean(I*p, r'), fmean(I*I, r')
// varI = corrIp.w - meanIp.w * meanIp.w
// covIp = corrIp.xyz - meanIp.w * meanIp.xyz
// a = covIp / (varI + epsilon)
// b = meanIp.xyz - a * meanIp.w
// meanA = fmean(a, r')
// meanB = fmean(b, r')
// q = meanA * meanIp.w + meanB
// -----

void main() {
  // This is the kernel size for blurring out the
  // a and b values. Just a fixed ratio of the image height.
  float maxDimension = max(uInputImageSize.x, uInputImageSize.y);
  float fSmallKernelSize = 0.0083*maxDimension;
  int smallKernelSize = int(fSmallKernelSize);

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
    //passBuffer2
    gl_FragColor = texture2D(passBuffer1, uv);
  } else if (passIndex == 2) {
#ifdef SMOOTHING_FACTOR
    // 0.06 is a magic number based on observation,
    //to make the range 0...1 look reasonable for skin smoothing
    float smoothFactorInternal = SMOOTHING_FACTOR * 0.06;
#else
    float smoothFactorInternal = 0.0;
#endif
    // This is the epsilon that governs the amount of smoothing
    float epsilon = smoothFactorInternal * smoothFactorInternal;
    vec2 duv = 4.0 / uInputImageSize;
    vec2 uv0 = uv - 0.5 * (float(smallKernelSize) - 1.0) * duv;
    MSQRD_HIGHP vec4 corrIp = vec4(0.0);
    MSQRD_HIGHP vec4 meanIp = vec4(0.0);
    float weight = 1.0 / (float(smallKernelSize)*float(smallKernelSize));
    for (j = 0; j < smallKernelSize; j++) {
      offset.y = uv0.y + float(j) * duv.y;

      for (i = 0; i < smallKernelSize; i++) {
        offset.x = uv0.x + float(i) * duv.x;

        vec4 tex = texture2D(passBuffer2, offset);

        meanIp += weight * tex;
        corrIp += weight * tex * tex;
      }
    }
    vec4 varIp = corrIp - meanIp * meanIp;
    vec3 a = varIp.xyz / (varIp.xyz + epsilon);

    // passBuffer3 = a
    gl_FragColor = vec4(a, 1.0);
  } else if (passIndex == 3) {
    vec4 meanIp = texture2D(passBuffer2, uv);
    vec4 a = texture2D(passBuffer3, uv);
    vec3 b = meanIp.xyz - a.xyz * meanIp.xyz;

    // passBuffer4 = b
    gl_FragColor = vec4(b, 1.0);
  } else if (passIndex == 4) {
    vec4 meanA = vec4(0.0);
    vec2 duv = 4.0 / uInputImageSize;
    vec2 uv0 = uv - 0.5 * (float(smallKernelSize) - 1.0) * duv;

    for (j = 0; j < smallKernelSize; j++) {
      offset.y = uv0.y + float(j) * duv.y;

      for (i = 0; i < smallKernelSize; i++) {
        offset.x = uv0.x + float(i) * duv.x;

        meanA += texture2D(passBuffer3, offset);
      }
    }
    meanA /= float(smallKernelSize) * float(smallKernelSize);

    // passBuffer2 = meanA
    gl_FragColor = meanA;
  } else if (passIndex == 5) {
    vec4 meanB = vec4(0.0);
    vec2 duv = 4.0 / uInputImageSize;
    vec2 uv0 = uv - 0.5 * (float(smallKernelSize) - 1.0) * duv;

    for (j = 0; j < smallKernelSize; j++) {
      offset.y = uv0.y + float(j) * duv.y;

      for (i = 0; i < smallKernelSize; i++) {
        offset.x = uv0.x + float(i) * duv.x;

        meanB += texture2D(passBuffer4, offset);
      }
    }
    meanB /= float(smallKernelSize) * float(smallKernelSize);

    // passBuffer3 = meanB
    gl_FragColor = meanB;

  } else if (passIndex == 6) {
    vec4 base = texture2D(inputImage, uv);
    vec4 face = texture2D(faceMask, uv);
    vec4 meanA = texture2D(passBuffer2, uv);
    vec4 meanB = texture2D(passBuffer3, uv);
    vec4 mean4 = texture2D(passBuffer1, uv);
    vec4 smoothed = meanA * base + meanB;

    // Compute the difference of the image and slightly blurred version
    vec4 diff = base - mean4;

    // Add the high frequencies back in based on the contrast
#ifdef SMOOTHING_FACTOR
    // The skin smoothing factor maps to both the internal smoothing
    // factor and the internal high frequency addition contrast
    // This contrast setting governs how much high frequency components
    // to bring in
    const float highFreqHigh = 0.4;
    const float highFreqContrastInternal = SMOOTHING_FACTOR * highFreqHigh;
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
