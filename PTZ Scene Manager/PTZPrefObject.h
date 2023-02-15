//
//  PTZPrefObject.h
//  PTZ Scene Manager
//
//  Created by Lee Ann Rucker on 2/14/23.
//
// PTZPrefObject manages NSUserDefaults for specific object instances.
// For example, objects of a given subclass might use a prefKey format "[uniqueID].key". Values for key "foo" would be stored as "[ThisObj].foo".
// If "[ThisObj].foo" doesn't exist in defaults, it would fall back to the optional registerDefaults value for "foo".

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PTZPrefObject : NSObject

- (NSString *)prefKeyForKey:(NSString *)key;

- (id)prefValueForKey:(NSString *)key;
- (void)setPrefValue:(id)obj forKey:(NSString *)key;
- (void)setPrefValue:(id)obj forKeyWithSelector:(NSString *)key;
- (void)removePrefValueForKey:(NSString *)key;
- (void)removePrefValueForKeyWithSelector:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
