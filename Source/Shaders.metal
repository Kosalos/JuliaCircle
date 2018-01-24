#include <metal_stdlib>
#import "ShaderTypes.h"

using namespace metal;

constant float pi = 3.141592654;

kernel void juliaShader
(
    texture2d<float, access::write> outTexture [[texture(0)]],
    constant Control &params [[buffer(0)]],
    constant float3 *color [[buffer(1)]],
    uint2 p [[thread_position_in_grid]])
{
    int i;
    float newRe, newIm, oldRe, oldIm;
    
    float px = float(p.x);
    float py = float(p.y);
    
    if(params.circle) {
        float center = 512;
        float dx = float(p.x - center);
        float dy = float(p.y - center);
        
        float angle = atan2(dy,dx);
        angle = fabs(angle);

        float dRatio = 0.01 + params.ratio * pi;
        while(angle > dRatio) angle -= dRatio;
        if(angle > dRatio/2) angle = dRatio - angle;

        float dist = sqrt(dx * dx + dy * dy);
        
        px = center + cos(angle) * dist;
        py = center + sin(angle) * dist;
    }
    
    newRe = params.base.x + px / params.zoom;
    newIm = params.base.y + py / params.zoom;

    for(i = 0; i < 256; ++i) {
        oldRe = newRe;
        oldIm = newIm;
        newRe = oldRe * oldRe - oldIm * oldIm + params.cRe;
        newIm = params.mult * oldRe * oldIm + params.cIm;

        if((newRe * newRe + newIm * newIm) > 4) break;
    }

    i = (int)((float)i + params.cycleAmount) & 255;

    if(params.gray) {
        float gray = sin(float(i) / 200);
        outTexture.write(float4(gray,gray,gray,1),p);
    }
    else {
        outTexture.write(float4(color[i],1),p);
    }
}

kernel void shadowShader
(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant Control &params [[buffer(0)]],
    constant float3 *color [[buffer(1)]],
    uint2 p [[thread_position_in_grid]])
{
    float4 v = src.read(p);

    if(!params.shadow) {
        dst.write(v,p);
        return;
    }
    
    if(p.x > 1 && p.y > 1) {
        bool shadow = false;
        
        {
        uint2 p2 = p;
        p2.x -= 1;
        float4 vx = src.read(p2);
        if(v.x < vx.x || v.y < vx.y) shadow = true;
        }
        
        if(!shadow)
        {
            uint2 p2 = p;
            p2.y -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }

        if(!shadow)
        {
            uint2 p2 = p;
            p2.x -= 1;
            p2.y -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }

        if(shadow) {
            if(params.shadow == 2)
                v = float4(0,0,0,1);
            else {
                v.x /= 4;
                v.y /= 4;
                v.z /= 4;
            };
        }
    }
    
    dst.write(v,p);
}
