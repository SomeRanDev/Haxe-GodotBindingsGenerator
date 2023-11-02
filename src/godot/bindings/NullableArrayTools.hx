package godot.bindings;

function maybeMap<T, U>(self: Null<Array<T>>, callback: (T) -> U): Array<U> {
	if(self == null) {
		return [];
	}

	final result = [];
	for(obj in self) {
		result.push(callback(obj));
	}
	return result;
}
