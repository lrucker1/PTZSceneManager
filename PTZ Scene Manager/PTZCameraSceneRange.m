//
//  PTZCameraSceneRange.m
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 1/28/23.
//

#import "PTZCameraSceneRange.h"
#import "ObjCUtils.h"


@implementation PTZCameraSceneRange
+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)sceneRangeFromEncodedData:(NSData *)data error:(NSError **)error {
    if (data == nil) {
        return nil;
    }
    return [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithArray:[PTZCameraSceneRange allowedArchiveClasses]] fromData:data error:error];
}

+ (NSArray *)allowedArchiveClasses {
    return @[[PTZCameraSceneRange class], [NSString class], [NSIndexSet class]];
}

+ (NSIndexSet *)parseIndexSet:(NSString *)string validRange:(NSRange)validRange error:(NSError * _Nullable *)error {
    NSNumberFormatter *nf = [NSNumberFormatter new];
    NSArray *ranges = [string componentsSeparatedByString:@","];
    NSMutableIndexSet *indexSet = [NSMutableIndexSet new];
    for (NSString *sub in ranges) {
        NSArray *subrange = [sub componentsSeparatedByString:@"-"];
        NSInteger count = [subrange count];
        if (count == 0) {
            continue;
        }
        // If only one, first and last are the same object, so no extra test needed
        if ([nf numberFromString:[subrange firstObject]] == nil ||
            [nf numberFromString:[subrange lastObject]] == nil) {
            // Would also get caught by the zero check, but that's implementation specific.
            if (error != nil) {
                NSString *fmt = NSLocalizedString(@"Values must be numeric: %@", @"Bad IndexSet String: no numbers");
                NSString *errString = [NSString localizedStringWithFormat:fmt, sub];
                *error = OCUtilErrorWithDescription(errString, nil, @"PTZCameraSceneRange", 101);
            }
            return nil;
        }
        NSInteger first = [[subrange firstObject] intValue];
        NSInteger last = [[subrange lastObject] intValue];
        if (!NSLocationInRange(first, validRange) || !NSLocationInRange(last, validRange)) {
            if (error != nil) {
                NSString *fmt = NSLocalizedString(@"Value %@ is outside allowed range of %ld to %ld", @"Bad IndexSet String: range");
                NSString *errString = [NSString localizedStringWithFormat:fmt, sub, validRange.location, validRange.location+validRange.length];
                *error = OCUtilErrorWithDescription(errString, nil, @"PTZCameraSceneRange", 102);
            }
            return nil;
        }
        if (count == 1) {
            [indexSet addIndex:first];
        } else if (count == 2) {
            if (last < first) {
                if (error != nil) {
                    NSString *fmt = NSLocalizedString(@"End of range must be greater than beginning: %@", @"Bad IndexSet String: range");
                    NSString *errString = [NSString localizedStringWithFormat:fmt, sub];
                    *error = OCUtilErrorWithDescription(errString, nil, @"PTZCameraSceneRange", 103);
                }
                return nil;
            } else if (last == first) {
                [indexSet addIndex:first];
            } else {
                NSRange range = NSMakeRange(first, last-first+1);
                [indexSet addIndexesInRange:range];
            }
        } else {
            if (error != nil) {
                NSString *fmt = NSLocalizedString(@"Ranges must have only two values: %@", @"Bad IndexSet String: too many numbers");
                NSString *errString = [NSString localizedStringWithFormat:fmt, sub];
                *error = OCUtilErrorWithDescription(errString, nil, @"PTZCameraSceneRange", 104);
            }
            return nil;
        }
    }
    // Return a non-mutable copy.
    return [indexSet copy];
}

+ (NSString *)displayIndexSet:(NSIndexSet *)indexSet pretty:(BOOL)pretty {
    // pretty has an en-dash; don't use it outside the UI unless you like seeing raw unicode.
    NSString *sep = pretty ? @"–" : @"-";
    NSInteger first = indexSet.firstIndex;
    NSInteger last = indexSet.lastIndex;
    NSRange all = NSMakeRange(first, last-first+1);
    NSMutableString *string = [NSMutableString new];
    [indexSet enumerateRangesInRange:all options:0 usingBlock:^(NSRange range, BOOL * _Nonnull stop) {
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
    return sep;
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
    return [self.indexSet isEqualToIndexSet:object.indexSet];
}

- (NSString *)displayIndexSet:(BOOL)pretty {
    return [PTZCameraSceneRange displayIndexSet:self.indexSet pretty:pretty];
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

