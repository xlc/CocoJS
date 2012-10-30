Parent = objc.NSObject.extend('Parent', null, {
    init: function() {
        this._super();
        log('init parent');
        log(this);
        return this;
    },
    name: 'object'
});

Child = Parent.extend('Child', null, {
    init: function() {
        this._super();
        log('init child');
        return this;
    },
})