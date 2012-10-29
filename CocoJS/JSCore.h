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

+ (JSCore *)sharedInstance;

- (BOOL)evaluateString:(NSString *)string outVal:(jsval *)outVal;
- (BOOL)evaluateFile:(NSString *)filepath;
- (BOOL)evaluateScriptFile:(NSString *)filename;
- (BOOL)isStringCompleted:(NSString *)string;

- (NSString *)stringFromValue:(jsval)val;

- (void)gc;
- (void)gcIfNeed;

- (void)startAutoGC;
- (void)stopAutoGC;

@end
