//
//  JSCore.h
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-22.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "jsapi.h"

@interface JSCore : NSObject

@property (nonatomic, readonly) JSRuntime *rt;
@property (nonatomic, readonly) JSContext *cx;
@property (nonatomic, readonly) JSObject *global;
@property (nonatomic, retain, readonly) NSString *errorString;
@property (nonatomic) BOOL searchDocumentDirectory;

+ (JSCore *)sharedInstance;

- (void)customInit;

- (BOOL)evaluateString:(NSString *)string outVal:(jsval *)outVal;
- (BOOL)evaluateFile:(NSString *)filepath;
- (BOOL)evaluateScriptFile:(NSString *)filename;
- (BOOL)isStringCompleted:(NSString *)string;

- (NSString *)stringFromValue:(jsval)val;

- (void)gc;
- (void)gcIfNeed;

- (void)startAutoGC;
- (void)stopAutoGC;

- (id)valueForName:(NSString *)name;
- (id)valueForName:(NSString *)name defaultValue:(id)defaultValue;
- (void)valueForName:(NSString *)name encode:(const char *)encode outValue:(void *)outValue;
- (void)valueForName:(NSString *)name encode:(const char *)encode defaultValue:(void *)defaultValue outValue:(void *)outValue;

- (id)executeFunction:(NSString *)name arguments:(id)arg, ... NS_REQUIRES_NIL_TERMINATION;
- (id)executeFunction:(NSString *)name argumentArray:(NSArray *)args;

@end


#define JSExecuteFunction(function, ...) [[JSCore sharedInstance] executeFunction:function arguments:__VA_ARGS__]

static inline id JSGetValue(NSString *name, id defaultValue) {
    return [[JSCore sharedInstance] valueForName:name defaultValue:defaultValue];
}

static inline float JSGetFloat(NSString *name, float defaultValue) {
    return [[[JSCore sharedInstance] valueForName:name defaultValue:[NSNumber numberWithFloat:defaultValue]] floatValue];
}

static inline int JSGetInt(NSString *name, int defaultValue) {
    return [[[JSCore sharedInstance] valueForName:name defaultValue:[NSNumber numberWithInt:defaultValue]] intValue];
}

#define JSGETSTRUCT(type) \
static inline type JSGet##type (NSString *name, type defaultValue) {\
    type ret; \
    [[JSCore sharedInstance] valueForName:name encode:@encode(type) defaultValue:&defaultValue outValue:&ret]; \
    return ret; \
}

JSGETSTRUCT(CGPoint)
JSGETSTRUCT(CGSize)
JSGETSTRUCT(CGRect)
JSGETSTRUCT(CGAffineTransform)
JSGETSTRUCT(NSRange)
JSGETSTRUCT(UIEdgeInsets)