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

- (NSIndexSet *)parseIndexSet:(NSString *)test {
    // TODO: replace all the NSLogs with error messages.
    NSNumberFormatter *nf = [NSNumberFormatter new];
    NSArray *ranges = [test componentsSeparatedByString:@","];
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
            NSLog(@"non-numerical values not allowed %@", sub);
            return nil;
        }
        NSInteger first = [[subrange firstObject] intValue];
        NSInteger last = [[subrange lastObject] intValue];
        if (first == 0 || last == 0) {
            NSLog(@"zero values not allowed %@", sub);
            return nil;
        }
        if (count == 1) {
            [indexSet addIndex:first];
        } else if (count == 2) {
            if (last < first) {
                NSLog(@"bad range %@", sub);
                return nil;
            } else if (last == first) {
                [indexSet addIndex:first];
            } else {
                NSRange range = NSMakeRange(first, last-first+1);
                [indexSet addIndexesInRange:range];
            }
        } else {
            NSLog(@"Too many sections %@", sub);
            return nil;
        }
    }
    // Return a non-mutable copy.
    return [indexSet copy];
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

