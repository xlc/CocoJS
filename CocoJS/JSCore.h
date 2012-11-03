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

- (id)executeFunction:(NSString *)name arguments:(id)arg, ... NS_REQUIRES_NIL_TERMINATION;

@end

static inline id JSGetValue(NSString *name, id defaultValue) {
    return [[JSCore sharedInstance] valueForName:name defaultValue:defaultValue];
}

static inline float JSGetFloat(NSString *name, float defaultValue) {
    return [[[JSCore sharedInstance] valueForName:name defaultValue:[NSNumber numberWithFloat:defaultValue]] floatValue];
}

static inline int JSGetInt(NSString *name, int defaultValue) {
    return [[[JSCore sharedInstance] valueForName:name defaultValue:[NSNumber numberWithInt:defaultValue]] intValue];
}