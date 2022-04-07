
class Field {
	String field = "";          // Field name, unique within a schema, a-z0-9_ only.
	String title = "";          // Label for this field
	String type = "";           // Typing string for this field.
	String position = "";       // Positioning string for this field (deprecated).
	dynamic defaultValue;       // Default value (or NULL) for this field. May not apply to all types.
}

