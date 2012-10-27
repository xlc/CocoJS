NSObject = objc.NSObject

Parent = NSObject.extend('Parent', null, {
    init: function() {
        this._super();
        log('parent');
    }, 
    test: function() {
        log('parent test');
    },
    t: 1
});


Child = Parent.extend('Child', null, {
    init: function() {
        this._super();
        log('Child');
    },
    test: function() {
        log('child test');
        this._super();
    },
});