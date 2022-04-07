import 'field.dart';
import 'mote.dart';

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
	}
}