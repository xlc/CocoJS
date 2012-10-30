function Point(x, y) {
    if (typeof x != 'number' || typeof y != 'number')
        throw TypeError('invalid input type. x: ' + x + ', y: ' + y);
    return {x:x, y:y};
}

function Size(width, height) {
    if (typeof width != 'number' || typeof height != 'number')
        throw TypeError('invalid input type. width: ' + width + ', height: ' + height);
    return {width:width, height:height};
}

function Rect(x, y, width, height) {
    if (typeof x != 'number' || typeof y != 'number' || typeof width != 'number' || typeof height != 'number')
        throw TypeError('invalid input type. x: ' + x + ', y: ' + y + ', width: ' + width + ', height: ' + height);
    return {x:x, y:y, width:width, height:height};
}

function Range(location, length) {
    if (typeof location != 'number' || typeof length != 'number')
        throw TypeError('invalid input type. location: ' + location + ', length: ' + length);
    return {location:location, length:length};
}