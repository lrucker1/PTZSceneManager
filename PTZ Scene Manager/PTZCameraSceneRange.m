//
//  PTZCameraSceneRange.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/28/23.
//

#import "PTZCameraSceneRange.h"


@implementation PTZCameraSceneRange
+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [self init];
    self.name = [coder decodeObjectForKey:@"name"];
    self.range = NSRangeFromString([coder decodeObjectForKey:@"range"]);
    return self;
}

- (NSString *)prettyRange {
    return [NSString stringWithFormat:@"%ld–%ld", self.range.location, NSMaxRange(self.range) - 1];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:NSStringFromRange(self.range) forKey:@"range"];
    [coder encodeObject:self.name forKey:@"name"];
}

@end

