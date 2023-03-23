import 'package:collection/collection.dart';
import 'dart:convert';
import 'field.dart';
import 'mote.dart';
import 'mote_relation.dart';

// Representation of a schema type. Schemas can be referred to as either an integer ID,
// or as a unique string type name. They are stored in the instance manager.
class Schema {
	// TODO: Fix a lot of these initial values, deal with nulls in existing data, etc.
	int id = 0;                     // Numerical ID of this schema
	String type = "";               // Unique typename, a-z0-9_ only
	String singular = "";           // Singular label, e.g. Customer
	String plural = "";             // Plural label, e.g. Customers
	List<Field> spec = [];          // Specification - ordered list of fields.
	int pageView = 0;               // Page ID used as default to render this data, or 0.
	String folderName = "";         // Folder name, used for administrative sorting only.
	String titleName = "";          // Label to override primary name/title for this data.
	String titlePrefix = "";        // Generator for auto-prefix
	String titleUnique = "";        // If title field should be unique - type of uniqueness
	String titleDefault = "";       // Default title value, or empty string for none.
	String casting = "";            // CSV of schema types this can be cast to.
	String htmlBody = "";           // Settings for HTML body field, or empty string.

	Schema.fromJson(Map<String, dynamic> json) {
		id = json['id'];
		type = json['type'];
		singular = json['singular'] ?? '';
		plural = json['plural'] ?? '';
		pageView = json['pageview'] ?? 0;
		folderName = json['foldername'] ?? '';
		titleName = json['titlename'] ?? '';
		titlePrefix = json['titleprefix'] ?? '';
		titleUnique = json['titleunique'] ?? '';
		titleDefault = json['titledefault'] ?? '';
		casting = json['casting'] ?? '';
		htmlBody = json['htmlbody'] ?? '';

		// JSON spec is delivered as a string here and must be decoded.
		if (json['spec'] != null && json['spec'] is String) {
			final jsonSpec = jsonDecode(json['spec']);
			if (jsonSpec != null && jsonSpec is List) {
				for (var specItem in jsonSpec) {
					spec.add(Field.fromJson(specItem));
				}
			}
		}
	}

	// Fetch field by name in spec if possible.
	Field? tryGetField(String fieldTypeName) {
		fieldTypeName = fieldTypeName.toLowerCase().trim();
		return spec.firstWhereOrNull((f) => f.field.toLowerCase().trim() == fieldTypeName);
	}

	// Common fields that exist in all mote schema types.
	static const List<String> commonFields = [ 'title', 'id', 'timestamp' ];

	// Generate (cached) CSV representation of this mote's payload headers, for our UI layer.
	String get schemaHeadersCSV => _cachedHeadersCSV == null ? _schemaHeadersCSV() : _cachedHeadersCSV!;
	String? _cachedHeadersCSV = null;
	String _schemaHeadersCSV() {
		if (spec.isEmpty) {
			throw UnimplementedError("Handling non-schema motes is not implemented yet!");
		}
		final orderedHeaders = spec.map((field) => 'cf_' + field.field).toList();
		orderedHeaders.addAll(commonFields);
		_cachedHeadersCSV = orderedHeaders.join(',');
		return _cachedHeadersCSV!;
	}

	// Interpret a mote according to it's schema for UI layer, returning CSV representation
	// in same order as the schemaHeadersCSV() return.
	String interpretMoteCSV(Mote mote) {
		if (spec.isEmpty) {
			throw UnimplementedError("Handling non-schema motes is not implemented yet!");
		}
		final orderedPayload = spec.map((field) {
			var fieldKey = 'cf_' + field.field;
			if (!mote.payload.containsKey(fieldKey)) {
				return '';
			}
			// TODO: Deal with internal JSON, all other field constructs, etc.
			if (field.isReference) {
				final relations = mote.payload[fieldKey] as List<MoteRelation>;
				return relations.map((relation) {
					if (relation.isUserTarget) {
						return relation.referencedTarget;
					} else {
						if (relation.referencedTarget == null)
							return "#UNKNOWN#";
						return (relation.referencedTarget as Mote).payload['title'];
					}
				}).toList().join(';');
			}
			return mote.payload[fieldKey]!.toString();
		}).toList();

		orderedPayload.addAll(commonFields.map((commonField) {
			if (commonField == 'id') {
				return mote.id.toString();
			} else if (commonField == 'timestamp') {
				return mote.timestamp.toString();
			}
			return mote.payload[commonField] ?? '';
		}));

		return orderedPayload.join(';');
	}

	// Initialize a blank mote with the defaults as set in this schema.
	void setMoteDefaults(Mote mote, { String? title }) {
		for (Field f in spec) {
			f.setDefaultValue(mote);
		}
		// If title does not exist, always set it to empty string or given title.
		if (!mote.payload.containsKey('title')) {
			mote.payload['title'] = title == null ? '' : title;
		} else if (title != null) {    // Otherwise override only if we have data.
			mote.payload['title'] = title;
		}
	}
}