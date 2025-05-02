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
    id indexSetObj = [coder decodeObjectForKey:@"indexSet"];
    if (indexSetObj) {
        self.indexSet = indexSetObj;
    } else {
        id rangeObj = [coder decodeObjectForKey:@"range"];
        if (rangeObj) {
            NSRange tempRange = NSRangeFromString(rangeObj);
            self.indexSet = [NSIndexSet indexSetWithIndexesInRange:tempRange];
        }
    }
    return self;
}

- (BOOL)matchesRange:(PTZCameraSceneRange *)object {
    return [self.indexSet isEqualTo:object.indexSet];
}

- (NSString *)displayIndexSet: (BOOL)pretty {
    // pretty has an en-dash; don't use it outside the UI unless you like seeing raw unicode.
    NSString *sep = pretty ? @"–" : @"-";
    if (self.indexSet) {
        NSInteger first = self.indexSet.firstIndex;
        NSInteger last = self.indexSet.lastIndex;
        NSRange all = NSMakeRange(first, last-first+1);
        NSMutableString *string = [NSMutableString new];
        [self.indexSet enumerateRangesInRange:all options:0 usingBlock:^(NSRange range, BOOL * _Nonnull stop) {
            if (string.length > 0) {
                [string appendString:@", "];
            }
            if (range.length == 1) {
                [string appendFormat:@"%ld", range.location];
            } else {
                [string appendFormat:@"%ld%@%ld", range.location, sep, range.location + range.length - 1];
            }
        }];
        if (string.length > 0) {
            return string;
        }
    }
    return sep;
}

- (NSString *)prettyRange {
    return [self displayIndexSet:YES];
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
    return [NSString stringWithFormat:@"%@ %@: %@", [self class], self.name, [self displayIndexSet:NO]];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (self.indexSet) {
        [coder encodeObject:self.indexSet forKey:@"indexSet"];
    }
    [coder encodeObject:self.name forKey:@"name"];
}

- (NSData *)encodedData {
    return [NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:YES error:nil];
}
@end

