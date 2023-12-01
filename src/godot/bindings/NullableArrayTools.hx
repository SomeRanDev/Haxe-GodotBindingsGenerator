package godot.bindings;

function maybeMap<T, U>(self: Null<Array<T>>, callback: (T, Int) -> U): Array<U> {
	if(self == null) {
		return [];
	}

	final result = [];
	for(i in 0...self.length) {
		result.push(callback(self[i], i));
	}
	return result;
}

inline function denullify<T>(self: Null<Array<T>>): Array<T> {
	return self == null ? [] : self;
}
