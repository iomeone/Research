
#include "./../postFx.hlsl"
#include "shaders/common/bge.hlsl"


uniform float4 rtParams0;
uniform float4 rtParams1;
uniform float4 rtParams2;
uniform float4 rtParams3;
                    
PFXVertToPix main( PFXVert IN )
{
   PFXVertToPix OUT;
   
   OUT.hpos = float4(IN.pos, 1);
   OUT.uv0 = IN.uv; //viewportCoordToRenderTarget( IN.uv, rtParams0 ); 
   OUT.uv1 = IN.uv; //viewportCoordToRenderTarget( IN.uv, rtParams1 ); 
   OUT.uv2 = IN.uv; //viewportCoordToRenderTarget( IN.uv, rtParams2 ); 
   OUT.uv3 = IN.uv; //viewportCoordToRenderTarget( IN.uv, rtParams3 ); 

   OUT.wsEyeRay = IN.wsEyeRay;
   
   return OUT;
}