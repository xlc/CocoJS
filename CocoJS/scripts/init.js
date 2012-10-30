function require(file) {
    require._files || (require._files = []);
    if (file in require._files) return;
    require._files.push(file);
    evalFile(file);
}

require('struct');