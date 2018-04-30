

#ifndef BGE_SHADERGEN

// These are the uniforms used by most lighting shaders.

uniform vec4 inLightPos[3];
uniform vec4 inLightInvRadiusSq;
uniform vec4 inLightColor[4];

#ifndef BGE_BL_NOSPOTLIGHT
   uniform vec4 inLightSpotDir[3];
   uniform vec4 inLightSpotAngle;
   uniform vec4 inLightSpotFalloff;
#endif

uniform vec4 ambient;
uniform float specularPower;
uniform vec4 specularColor;

#endif // !BGE_SHADERGEN


void compute4Lights( vec3 wsView, 
                     vec3 wsPosition, 
                     vec3 wsNormal,
                     vec4 shadowMask,

                     #ifdef BGE_SHADERGEN
                     
                        vec4 inLightPos[3],
                        vec4 inLightInvRadiusSq,
                        vec4 inLightColor[4],
                        vec4 inLightSpotDir[3],
                        vec4 inLightSpotAngle,
                        vec4 inLightSpotFalloff,
                        float specularPower,
                        vec4 specularColor,

                     #endif // BGE_SHADERGEN
                     
                     out vec4 outDiffuse,
                     out vec4 outSpecular )
{
   // NOTE: The light positions and spotlight directions
   // are stored in SoA order, so inLightPos[0] is the
   // x coord for all 4 lights... inLightPos[1] is y... etc.
   //
   // This is the key to fully utilizing the vector units and
   // saving a huge amount of instructions.
   //
   // For example this change saved more than 10 instructions 
   // over a simple for loop for each light.
   
   int i;

   vec4 lightVectors[3];
   for ( i = 0; i < 3; i++ )
      lightVectors[i] = wsPosition[i] - inLightPos[i];

   vec4 squareDists = vec4(0);
   for ( i = 0; i < 3; i++ )
      squareDists += lightVectors[i] * lightVectors[i];

   // Accumulate the dot product between the light 
   // vector and the normal.
   //
   // The normal is negated because it faces away from
   // the surface and the light faces towards the
   // surface... this keeps us from needing to flip
   // the light vector direction which complicates
   // the spot light calculations.
   //
   // We normalize the result a little later.
   //
   vec4 nDotL = vec4(0);
   for ( i = 0; i < 3; i++ )
      nDotL += lightVectors[i] * -wsNormal[i];

   vec4 rDotL = vec4(0);
   #ifndef BGE_BL_NOSPECULAR

      // We're using the Phong specular reflection model
      // here where traditionally Torque has used Blinn-Phong
      // which has proven to be more accurate to real materials.
      //
      // We do so because its cheaper as do not need to 
      // calculate the half angle for all 4 lights.
      //   
      // Advanced Lighting still uses Blinn-Phong, but the
      // specular reconstruction it does looks fairly similar
      // to this.
      //
      vec3 R = reflect( wsView, -wsNormal );

      for ( i = 0; i < 3; i++ )
         rDotL += lightVectors[i] * R[i];

   #endif
 
   // Normalize the dots.
   //
   // Notice we're using the half type here to get a
   // much faster sqrt via the rsq_pp instruction at 
   // the loss of some precision.
   //
   // Unless we have some extremely large point lights
   // i don't believe the precision loss will matter.
   //
   half4 correction = half4(inversesqrt( squareDists ));
   nDotL = saturate( nDotL * correction );
   rDotL = clamp( rDotL * correction, 0.00001, 1.0 );

   // First calculate a simple point light linear 
   // attenuation factor.
   //
   // If this is a directional light the inverse
   // radius should be greater than the distance
   // causing the attenuation to have no affect.
   //
   vec4 atten = saturate( 1.0 - ( squareDists * inLightInvRadiusSq ) );

   #ifndef BGE_BL_NOSPOTLIGHT

      // The spotlight attenuation factor.  This is really
      // fast for what it does... 6 instructions for 4 spots.

      vec4 spotAtten = vec4(0);
      for ( i = 0; i < 3; i++ )
         spotAtten += lightVectors[i] * inLightSpotDir[i];

      vec4 cosAngle = ( spotAtten * correction ) - inLightSpotAngle;
      atten *= saturate( cosAngle * inLightSpotFalloff );

   #endif

   // Finally apply the shadow masking on the attenuation.
   atten *= shadowMask;

   // Get the final light intensity.
   vec4 intensity = nDotL * atten;

   // Combine the light colors for output.
   outDiffuse = vec4(0);
   for ( i = 0; i < 4; i++ )
      outDiffuse += intensity[i] * inLightColor[i];

   // Output the specular power.
   vec4 specularIntensity = pow( rDotL, vec4(specularPower) ) * atten;
   
   // Apply the per-light specular attenuation.
   vec4 specular = vec4(0,0,0,1);
   for ( i = 0; i < 4; i++ )
      specular += vec4( inLightColor[i].rgb * inLightColor[i].a * specularIntensity[i], 1 );

   // Add the final specular intensity values together
   // using a single dot product operation then get the
   // final specular lighting color.
   outSpecular = specularColor * specular;
}


// This value is used in AL as a constant power to raise specular values
// to, before storing them into the light info buffer. The per-material 
// specular value is then computer by using the integer identity of 
// exponentiation: 
//
//    (a^m)^n = a^(m*n)
//
//       or
//
//    (specular^constSpecular)^(matSpecular/constSpecular) = specular^(matSpecular*constSpecular)   
//
#define AL_ConstantSpecularPower 12.0f

/// The specular calculation used in Advanced Lighting.
///
///   @param toLight    Normalized vector representing direction from the pixel 
///                     being lit, to the light source, in world space.
///
///   @param normal  Normalized surface normal.
///   
///   @param toEye   The normalized vector representing direction from the pixel 
///                  being lit to the camera.
///
float AL_CalcSpecular( vec3 toLight, vec3 normal, vec3 toEye )
{
   #ifdef PHONG_SPECULAR 
      // (R.V)^c
      float specVal = dot( normalize( -reflect( toLight, normal ) ), toEye );
   #else
      // (N.H)^c [Blinn-Phong, TGEA style, default]
      float specVal = dot( normal, normalize( toLight + toEye ) );
   #endif

   // Return the specular factor.
   return pow( max( specVal, 0.00001f ), AL_ConstantSpecularPower );
}
