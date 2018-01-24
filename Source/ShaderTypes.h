#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

struct Control {
    vector_float2 base;
    float  zoom;
    float  cRe;
    float  cIm;
    float  cycleAmount;
    float  mult;
    float  ratio;
    bool   gray;
    bool   circle;
    int    shadow;
};

#endif /* ShaderTypes_h */

