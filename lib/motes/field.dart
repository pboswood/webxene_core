import 'mote.dart';

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

	// Default handling is only for non-complex/computed fields.
	bool get allowsDefaultValues => (type != 'complex' && type != 'computed');

	// Set a default value for this field on the mote payload if possible.
	void setDefaultValue(Mote mote) {
		if (defaultValue == null || !allowsDefaultValues) {
			return;
		}

		// By default, all default values are treated as text strings when set in payload.
		// The only exceptions are for numeric values, currency, datetime and references.
		dynamic castedDefault;
		if (type == 'number' || type == 'currency') {
			castedDefault = defaultValue;       // We allow object-maps to be stored as default values for number/currency values.
			// TODO: Validate precision objects?
		} else if (type == 'datetime') {
			castedDefault = defaultValue;       // Likewise for datetime, as we have object-types for from/to dates.
			// TODO: Validate dates?
		} else if (isReference) {
			// Default value may be one of logged in user in certain cases.
			// TODO: Implement replacement of current user reference.
			throw "Unimplemented: default value for references";
		} else {
			castedDefault = defaultValue.toString();
		}

		mote.payload['cf_' + field]  = castedDefault;
	}
}

