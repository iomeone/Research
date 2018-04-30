

#if defined( SOFTSHADOW ) && defined( SOFTSHADOW_HIGH_QUALITY )

#define NUM_PRE_TAPS 4
#define NUM_TAPS 12

/// The non-uniform poisson disk used in the
/// high quality shadow filtering.
vec2 sNonUniformTaps[NUM_TAPS] = vec2[]
(    
   // These first 4 taps are located around the edges
   // of the disk and are used to predict fully shadowed
   // or unshadowed areas.
   vec2( 0.992833, 0.979309 ),
   vec2( -0.998585, 0.985853 ),
   vec2( 0.949299, -0.882562 ),
   vec2( -0.941358, -0.893924 ),

   // The rest of the samples.
   vec2( 0.545055, -0.589072 ),
   vec2( 0.346526, 0.385821 ),
   vec2( -0.260183, 0.334412 ),
   vec2( 0.248676, -0.679605 ),
   vec2( -0.569502, -0.390637 ),
   vec2( -0.614096, 0.212577 ),
   vec2( -0.259178, 0.876272 ),
   vec2( 0.649526, 0.864333 )
);

#else

#define NUM_PRE_TAPS 5

/// The non-uniform poisson disk used in the
/// high quality shadow filtering.
vec2 sNonUniformTaps[NUM_PRE_TAPS] = vec2[]
(      
   vec2( 0.892833, 0.959309 ),
   vec2( -0.941358, -0.873924 ),
   vec2( -0.260183, 0.334412 ),
   vec2( 0.348676, -0.679605 ),
   vec2( -0.569502, -0.390637 )
);

#endif


/// The texture used to do per-pixel pseudorandom
/// rotations of the filter taps.
uniform sampler2D gTapRotationTex ;


float softShadow_sampleTaps(  sampler2D shadowMap,
                              vec2 sinCos,
                              vec2 shadowPos,
                              float filterRadius,
                              float distToLight,
                              float esmFactor,
                              int startTap,
                              int endTap )
{
   float shadow = 0;

   vec2 tap = vec2(0);
   for ( int t = startTap; t < endTap; t++ )
   {
      tap.x = ( sNonUniformTaps[t].x * sinCos.y - sNonUniformTaps[t].y * sinCos.x ) * filterRadius;
      tap.y = ( sNonUniformTaps[t].y * sinCos.y + sNonUniformTaps[t].x * sinCos.x ) * filterRadius;
      float occluder = tex2Dlod( shadowMap, vec4( shadowPos + tap, 0, 0 ) ).r;

      float esm = saturate( exp( esmFactor * ( occluder - distToLight ) ) );
      shadow += esm / float( endTap - startTap );
   }

   return shadow;
}


float softShadow_filter(   sampler2D shadowMap,
                           vec2 vpos,
                           vec2 shadowPos,
                           float filterRadius,
                           float distToLight,
                           float dotNL,
                           float esmFactor )
{
   #ifndef SOFTSHADOW

      // If softshadow is undefined then we skip any complex 
      // filtering... just do a single sample ESM.

      float occluder = tex2Dlod( shadowMap, vec4( shadowPos, 0, 0 ) ).r;
      float shadow = saturate( exp( esmFactor * ( occluder - distToLight ) ) );

   #else

      // Lookup the random rotation for this screen pixel.
      vec2 sinCos = ( tex2Dlod( gTapRotationTex, vec4( vpos * 16, 0, 0 ) ).rg - 0.5 ) * 2;

      // Do the prediction taps first.
      float shadow = softShadow_sampleTaps(  shadowMap,
                                             sinCos,
                                             shadowPos,
                                             filterRadius,
                                             distToLight,
                                             esmFactor,
                                             0,
                                             NUM_PRE_TAPS );

      // We live with only the pretap results if we don't
      // have high quality shadow filtering enabled.
      #ifdef SOFTSHADOW_HIGH_QUALITY

         // Only do the expensive filtering if we're really
         // in a partially shadowed area.
         if ( shadow * ( 1.0 - shadow ) * max( dotNL, 0 ) > 0.06 )
         {
            shadow += softShadow_sampleTaps( shadowMap,
                                             sinCos,
                                             shadowPos,
                                             filterRadius,
                                             distToLight,
                                             esmFactor,
                                             NUM_PRE_TAPS,
                                             NUM_TAPS );
                                             
            // This averages the taps above with the results
            // of the prediction samples.
            shadow *= 0.5;                              
         }

      #endif // SOFTSHADOW_HIGH_QUALITY

   #endif // SOFTSHADOW

   return shadow;
}