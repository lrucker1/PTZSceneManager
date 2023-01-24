//
//  PTZOutlineViewDictionaryDataSource.h
//  PTZ Backup
//
//  Created by Lee Ann Rucker on 1/10/23.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const LAR_OUTLINE_CHILDREN_KEY;
extern NSString * const LAR_OUTLINE_KVC_NAME_KEY;
extern NSString * const LAR_OUTLINE_KVC_HAS_VALUE_KEY;
extern NSString * const LAR_OUTLINE_KVC_SELECT_NAME_KEY;
extern NSString * const LAR_OUTLINE_SELECT_KEY; // Used in nib
extern NSString * const LAR_OUTLINE_TYPE_KEY;
extern NSString * const LAR_OUTLINE_VALUE_KEY; // Used in nib.
extern NSString * const LAR_OUTLINE_CUSTOM_VALUE_KEY;
extern NSString * const LAR_OUTLINE_ENUM_TITLES_KEY;
// If you use ENUM_TAG_VALUES you must set TAG_VALUE; basic VALUE is what's used in the outlineView, and for popups that is always the item index.
// The KVC key will be set to the tag value.
extern NSString * const LAR_OUTLINE_TAG_VALUE_KEY;
extern NSString * const LAR_OUTLINE_ENUM_TAG_VALUES_KEY;
extern NSString * const LAR_OUTLINE_ENUM_DISABLED_INDEXES_KEY;
extern NSString * const LAR_OUTLINE_DESCRIPTION_KEY; // Used in nib.
extern NSString * const LAR_OUTLINE_DETAIL_KEY; // For optional nib textfields.
extern NSString * const LAR_OUTLINE_BEGAN_EDITING_KEY;

extern NSString * const LAR_OUTLINE_TYPE_BOOL;
extern NSString * const LAR_OUTLINE_TYPE_ENUM;
extern NSString * const LAR_OUTLINE_TYPE_INT;
extern NSString * const LAR_OUTLINE_TYPE_STRING;

@protocol PTZOutlineViewTarget
- (BOOL)canEditProperty:(NSString *)kvcName;
@end

@protocol PTZOutlineViewDelegate

- (BOOL)outlineView:(NSOutlineView *)ov doCommandBySelector:(SEL)selector;
;
@end

@interface PTZOutlineViewDictionary : NSObject <NSOutlineViewDelegate, NSOutlineViewDataSource>


- (id)initWithDictionary:(NSDictionary *)aDictionary
                  target:(NSObject<PTZOutlineViewTarget> *)aTarget
                delegate:(NSObject *)aDelegate;

- (void)outlineView:(NSOutlineView *)outlineView changeDictionary:(NSDictionary *)aDictionary;

@end

@interface PTZOutlineView : NSOutlineView

@end

NS_ASSUME_NONNULL_END
