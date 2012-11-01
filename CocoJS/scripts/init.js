function require(file) {
    if (require._files.indexOf(file) != -1) return;
    require._files.push(file);
    evalFile(file);
}

require._files = [];

require.reload = function() {
    var files = require._files;
    require._files = [];
    files.forEach(function(file) {
        require(file);
    });
}

require('struct');