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

+ (instancetype)sceneRangeFromEncodedData:(NSData *)data error:(NSError **)error {
    if (data == nil) {
        return nil;
    }
    return [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithArray:@[[self class], [NSString class]]] fromData:data error:error];
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

- (NSString *)prettyRangeWithName:(NSString *)name {
    if ([name length] > 0) {
        return [NSString stringWithFormat:@"%@: %@", name, self.prettyRange];
    }
    return self.prettyRange;
}

- (NSString *)description {
    return [self prettyRangeWithName:self.name];
}

- (NSString *)debugDescription {
    // prettyRange has an en-dash; don't use it unless you like seeing raw unicode.
    return [NSString stringWithFormat:@"%@ %@: %ld-%ld", [self class], self.name, self.range.location, NSMaxRange(self.range) - 1];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:NSStringFromRange(self.range) forKey:@"range"];
    [coder encodeObject:self.name forKey:@"name"];
}

- (NSData *)encodedData {
    return [NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:YES error:nil];
}
@end

