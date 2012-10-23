//
//  jsval_helper.mm
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-22.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "jsval_helper.h"

#import "JSCore.h"

NSString *jsval_to_string(jsval val) {
    JSContext *cx = [JSCore sharedInstance].cx;
    JSType type = JS_TypeOfValue(cx, val);
    switch (type) {
        case JSTYPE_NULL:
            return @"null";
        case JSTYPE_VOID:
            return @"undefined";
        case JSTYPE_BOOLEAN:
            return JSVAL_TO_BOOLEAN(val) ? @"true" : @"false";
        case JSTYPE_NUMBER:
            if (JSVAL_IS_INT(val)) {
                return [NSString stringWithFormat:@"%d", JSVAL_IS_INT(val)];
            }
            return [NSString stringWithFormat:@"%lf", JSVAL_TO_DOUBLE(val)];
        case JSTYPE_FUNCTION:
        case JSTYPE_OBJECT:
        {
            jsval ret;
            if (JS_CallFunctionName(cx, JSVAL_TO_OBJECT(val), "toString", 0, NULL, &ret)) {
                JSString *jsstr = JSVAL_TO_STRING(ret);
                return @(JS_EncodeString(cx, jsstr));
            } else {
                return @"object";
            }
        }
        case JSTYPE_STRING:
            return @(JS_EncodeString(cx, JSVAL_TO_STRING(val)));
        default:
            return @(JS_GetTypeName(cx, type));
    }
}