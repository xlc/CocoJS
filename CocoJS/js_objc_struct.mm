//
//  js_objc_struct.mm
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-28.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#include "js_objc_struct.h"

#include "js_objc_helper.h"

#define FROM_STRUCT(type) \
if (strcmp(encode, @encode(type)) == 0) {\
type *s = (type *)value;

#define FROM_STRUCT_END return JS_TRUE;}

#define SET_PROPERTY(func, name) val = func(s->name); JS_SetProperty(cx, obj, #name, &val);
#define SET_PROPERTY2(func, exp, name) val = func(s->exp); JS_SetProperty(cx, obj, #name, &val);

JSBool jsval_from_struct(JSContext *cx, const char *encode, void *value, jsval *outval) {
    JSObject *obj = JS_NewObject(cx, NULL, NULL, NULL);
    *outval = OBJECT_TO_JSVAL(obj);
    
    jsval val;
    
    FROM_STRUCT(CGPoint)
    SET_PROPERTY(DOUBLE_TO_JSVAL, x)
    SET_PROPERTY(DOUBLE_TO_JSVAL, y)
    FROM_STRUCT_END
    
    FROM_STRUCT(CGSize)
    SET_PROPERTY(DOUBLE_TO_JSVAL, width)
    SET_PROPERTY(DOUBLE_TO_JSVAL, height)
    FROM_STRUCT_END
    
    FROM_STRUCT(CGRect)
    SET_PROPERTY2(DOUBLE_TO_JSVAL, size.width, width)
    SET_PROPERTY2(DOUBLE_TO_JSVAL, size.height, height)
    SET_PROPERTY2(DOUBLE_TO_JSVAL, origin.x, x)
    SET_PROPERTY2(DOUBLE_TO_JSVAL, origin.y, y)
    FROM_STRUCT_END
    
    FROM_STRUCT(CGAffineTransform)
    SET_PROPERTY(DOUBLE_TO_JSVAL, a)
    SET_PROPERTY(DOUBLE_TO_JSVAL, b)
    SET_PROPERTY(DOUBLE_TO_JSVAL, c)
    SET_PROPERTY(DOUBLE_TO_JSVAL, d)
    SET_PROPERTY(DOUBLE_TO_JSVAL, tx)
    SET_PROPERTY(DOUBLE_TO_JSVAL, ty)
    FROM_STRUCT_END
    
    FROM_STRUCT(NSRange)
    SET_PROPERTY(INT_TO_JSVAL, location)
    SET_PROPERTY(INT_TO_JSVAL, length)
    FROM_STRUCT_END
    
    FROM_STRUCT(UIEdgeInsets)
    SET_PROPERTY(DOUBLE_TO_JSVAL, top)
    SET_PROPERTY(DOUBLE_TO_JSVAL, left)
    SET_PROPERTY(DOUBLE_TO_JSVAL, bottom)
    SET_PROPERTY(DOUBLE_TO_JSVAL, right)
    FROM_STRUCT_END
    
    MWLOG(@"unsupported struct %s", encode);
    *outval = JSVAL_VOID;
    
    return JS_FALSE;
}

#define TO_STRUCT(type) \
if (strcmp(encode, @encode(type)) == 0) { \
static type s; \
*outval = &s; \
*outsize = sizeof(type); \

#define GET_PROPERTY(func, name) \
if (!JS_GetProperty(cx, obj, #name, &v)) return JS_FALSE; \
s.name = func(v);

#define GET_PROPERTY2(func, exp, name) \
if (!JS_GetProperty(cx, obj, #name, &v)) return JS_FALSE; \
s.exp = func(v);

#define TO_STRUCT_END return JS_TRUE;}

JSBool jsval_to_struct(JSContext *cx, jsval val, const char *encode, void **outval, uint32_t *outsize) {
    if (JSVAL_IS_PRIMITIVE(val)) {
        return JS_FALSE;
    }
    
    uint32_t size;
    if (!outsize) {
        outsize = &size;
    }
    
    JSObject *obj = JSVAL_TO_OBJECT(val);
    jsval v;
    
    TO_STRUCT(CGPoint)
    GET_PROPERTY(jsval_to_number, x);
    GET_PROPERTY(jsval_to_number, y);
    TO_STRUCT_END
    
    TO_STRUCT(CGSize)
    GET_PROPERTY(jsval_to_number, width);
    GET_PROPERTY(jsval_to_number, height);
    TO_STRUCT_END
    
    TO_STRUCT(CGRect)
    GET_PROPERTY2(jsval_to_number, size.width, width);
    GET_PROPERTY2(jsval_to_number, size.height, height);
    GET_PROPERTY2(jsval_to_number, origin.x, x);
    GET_PROPERTY2(jsval_to_number, origin.y, y);
    TO_STRUCT_END
    
    TO_STRUCT(CGAffineTransform)
    GET_PROPERTY(jsval_to_number, a);
    GET_PROPERTY(jsval_to_number, b);
    GET_PROPERTY(jsval_to_number, c);
    GET_PROPERTY(jsval_to_number, d);
    GET_PROPERTY(jsval_to_number, tx);
    GET_PROPERTY(jsval_to_number, ty);
    TO_STRUCT_END
    
    TO_STRUCT(NSRange)
    GET_PROPERTY(JSVAL_TO_INT, location)
    GET_PROPERTY(JSVAL_TO_INT, length)
    TO_STRUCT_END
    
    TO_STRUCT(UIEdgeInsets)
    GET_PROPERTY(jsval_to_number, top)
    GET_PROPERTY(jsval_to_number, left)
    GET_PROPERTY(jsval_to_number, bottom)
    GET_PROPERTY(jsval_to_number, right)
    TO_STRUCT_END
    
    return JS_FALSE;
}
