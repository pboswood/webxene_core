
class Field {
	String field = "";          // Field name, unique within a schema, a-z0-9_ only.
	String title = "";          // Label for this field
	String type = "";           // Typing string for this field.
	String position = "";       // Positioning string for this field (deprecated).
	dynamic defaultValue;       // Default value (or null) for this field. May not apply to all types.

	Field.fromJson(Map<String, dynamic> json) {
		field = json['field'];
		title = json['title'];
		type = json['type'];
		position = json['position'] ?? '';
		defaultValue = json['defaultValue'];        // (May be null!)
	}

	// Check if field type matches any reference, a reverse reference, or a user reference.
	bool get isReference => (type == 'reverseref' || type.endsWith('[]'));
	bool get isReverseReference => type == 'reverseref';
	bool get isUserReference => type == '_user[]';

}

