//
//  js_objc_binding.mm
//  CocoJS
//
//  Created by Xiliang Chen on 12-10-23.
//  Copyright (c) 2012年 Xiliang Chen. All rights reserved.
//

#import "js_objc_binding.h"

#import "js_objc_helper.h"

static int internalOperation = 0;

static JSBool objc_property_op(JSContext *cx, JSHandleObject obj, JSHandleId jid, jsval *vp) {
    if (internalOperation) return JS_TRUE;
    
    *vp = JSVAL_VOID;
    return JS_FALSE;
}

static JSBool objc_property_setter(JSContext *cx, JSHandleObject obj, JSHandleId jid, JSBool strict, jsval *vp) {
    return objc_property_op(cx, obj, jid, vp);
}

static JSBool resolve_objc_selector(JSContext *cx, JSHandleObject obj, JSHandleId jid) {
    if (internalOperation) return JS_TRUE;
    
    internalOperation++;
    
    JSString *jsname = JSID_TO_STRING(jid);
    const char *selname = JS_EncodeString(cx, jsname);
    
    
    
    internalOperation--;
    return JS_TRUE;
}

JSClass js_objc_prototype_class = { "ObjCInstancePrototype", 0, objc_property_op, objc_property_op, JS_PropertyStub, objc_property_setter, JS_EnumerateStub, resolve_objc_selector, JS_ConvertStub, NULL, JSCLASS_NO_OPTIONAL_MEMBERS };

static jsval create_objc_instance_class(JSContext *cx, NSString *clsname) {
    jsval val;
    const char *script = [[NSString stringWithFormat:@"(function(){function %@ () {objc._alloc(this)}; return %@;})()", clsname, clsname] UTF8String];
    MASSERT_SOFT(JS_EvaluateScript(cx, JS_GetGlobalObject(cx), script, strlen(script), NULL, 0, &val));
    
    JSObject *proto = JS_NewObject(cx, &js_objc_prototype_class, NULL, NULL);
    jsval protoval = OBJECT_TO_JSVAL(proto);
    JS_SetProperty(cx, JSVAL_TO_OBJECT(val), "prototype", &protoval);   // class.prototype = proto
    JS_SetProperty(cx, proto, "constructor", &val);     // class.prototype.constructor = class
    
    return val;
}

static JSBool resolve_objc_class(JSContext *cx, JSHandleObject obj, JSHandleId jid) {
    internalOperation++;
    
    JSString *jsname = JSID_TO_STRING(jid);
    NSString *clsname = @(JS_EncodeString(cx, jsname));
    Class cls = NSClassFromString(clsname);
    if (cls) {
        jsval val = create_objc_instance_class(cx, clsname);
        JS_SetProperty(cx, obj, [clsname UTF8String], &val);
    }
    
    internalOperation--;
    return JS_TRUE;
}

static JSClass js_objc_class = { "ObjC", 0, objc_property_op, objc_property_op, JS_PropertyStub, objc_property_setter, JS_EnumerateStub, resolve_objc_class, JS_ConvertStub, NULL, JSCLASS_NO_OPTIONAL_MEMBERS };

static JSBool perform_selector(JSContext *cx, uint32_t argc, jsval *vp) {
    if (argc < 2) return JS_FALSE;
    
    jsval *argvp = JS_ARGV(cx, vp);
    if (JSVAL_IS_PRIMITIVE(argvp[0])) return JS_FALSE;
    
    id nsobj = jsobject_to_objc(cx, JSVAL_TO_OBJECT(argvp[0]));
    if (!nsobj) return JS_FALSE;
    
    if (!JSVAL_IS_STRING(argvp[1])) return JS_FALSE;
    const char *selname = jsval_to_string(cx, argvp[1]);
    
    argc -= 2;
    argvp += 2;
    
    SEL sel = find_selector(nsobj, selname, argc);
    if (!sel) {
        MILOG(@"cannot find selector '%s' for object %@", selname, nsobj);
        return JS_FALSE;
    }
    
    JSBool ok = JS_TRUE;
    NSMethodSignature *signature = [nsobj methodSignatureForSelector:sel];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:nsobj];
    [invocation setSelector:sel];
    for (int i = 0; i < argc; i++) {
        ok &= set_argument(cx, invocation, i, argvp[i]);
    }
    if (!ok) return JS_FALSE;
    [invocation invoke];
    
    jsval rval;
    void *retval = malloc([signature methodReturnLength]);
    [invocation getReturnValue:retval];
    
    ok &= jsval_from_type(cx, [signature methodReturnType], retval, &rval);
    free(retval);
    
    JS_SET_RVAL(cx, vp, rval);
    
    return ok;
}

static JSBool js_objc_alloc(JSContext *cx, uint32_t argc, jsval *vp) {
    if (argc < 1) return JS_FALSE;
    jsval *argvp = JS_ARGV(cx, vp);
    JSObject *obj = JSVAL_TO_OBJECT(argvp[0]);
    jsval cstrval, nameval;
    MASSERT_SOFT(JS_GetProperty(cx, obj, "constructor", &cstrval));
    MASSERT_SOFT(JS_GetProperty(cx, JSVAL_TO_OBJECT(cstrval), "name", &nameval));
    Class cls = NSClassFromString(@(jsval_to_string(cx, nameval)));
    id nsobj = [[cls alloc] autorelease];
    
    associate_object(cx, obj, nsobj);   // this will retain the object
    
    JS_SET_RVAL(cx, vp, JSVAL_VOID);
    return JS_TRUE;
}

static JSBool js_objc_gc(JSContext *cx, uint32_t argc, jsval *vp) {
    JS_GC(JS_GetRuntime(cx));
    JS_SET_RVAL(cx, vp, JSVAL_VOID);
    return JS_TRUE;
}

void js_objc_init(JSContext *cx, JSObject *global) {
    JSObject *obj = JS_NewObject(cx, &js_objc_class, NULL, NULL);
    jsval objval = OBJECT_TO_JSVAL(obj);
    JS_SetProperty(cx, global, "objc", &objval);
    
    internalOperation++;
    
    JS_DefineFunction(cx, obj, "_perform", perform_selector, 2, JSPROP_READONLY | JSPROP_PERMANENT );
    JS_DefineFunction(cx, obj, "_alloc", js_objc_alloc, 1, JSPROP_READONLY | JSPROP_PERMANENT );
    JS_DefineFunction(cx, obj, "gc", js_objc_gc, 0, JSPROP_READONLY | JSPROP_PERMANENT | JSPROP_ENUMERATE );
    
    internalOperation--;
}