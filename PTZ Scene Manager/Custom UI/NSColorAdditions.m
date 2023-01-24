//
//  NSColorAdditions.m
//  ColorSpace
//
//  Created by Lee Ann Rucker on 1/9/23.
//
/*

    Algorithm taken from Tanner Helland's post: http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code/
    Code translated from Swift:
        https://github.com/davidf2281/ColorTempToRGB

*/

#import "NSColorAdditions.h"

static CGFloat ptz_clamp(CGFloat value) {
    return (value) > 255 ? 255 : (value < 0 ? 0 : value);
}

@implementation NSColor (PTZAdditions)


+ (instancetype)ptz_colorWithTemperature:(CGFloat)temp alpha:(CGFloat)alpha {
    CGFloat tmpKelvin = temp / 100;
    CGFloat red, green, blue;
    red = ptz_clamp(tmpKelvin <= 66 ? 255 : (329.698727446 * pow(tmpKelvin - 60, -0.1332047592)));
    green = ptz_clamp(tmpKelvin <= 66 ? (99.4708025861 * log(tmpKelvin) - 161.1195681661) : 288.1221695283 * pow(tmpKelvin - 60, -0.0755148492));
    blue = ptz_clamp(tmpKelvin >= 66 ? 255 : (tmpKelvin <= 19 ? 0 : 138.5177312231 * log(tmpKelvin - 10) - 305.0447927307));

    return [[self class] colorWithDeviceRed:red/255 green:green/255 blue:blue/255 alpha:alpha];
}

@end
