//
//  js_objc_helper.h
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-22.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "jsapi.h"

NSString *jsval_to_NSString(JSContext *cx, jsval val);

const char *jsval_to_string(JSContext *cx, jsval val);

id jsobject_to_objc(JSContext *cx, JSObject *obj);
jsval jsval_from_objc( JSContext *cx, id object);

void associate_object(JSContext *cx, JSObject *jsobj, id nsobj);
void remove_associated_object(JSObject *jsobj);

SEL find_selector(id obj, const char *selname, int argc);
SEL find_selector_class(Class cls, const char *selname, int argc, char **typedesc, char **rettype);

JSBool set_argument(JSContext *cx, NSInvocation *invocation, int idx, jsval val);

JSBool jsval_to_type(JSContext *cx, jsval val, const char *encode, void **outval, unsigned *outsize);
JSBool jsval_from_type(JSContext *cx, const char *encode, void *value, jsval *outval);

IMP get_imp(char *rettype);