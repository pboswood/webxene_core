import 'mote.dart';

enum FilterType { and, global }

class Filter {
	// NB: Filtering is done by string because filters can apply to multiple schemas!
	late String fieldName;      // Field name we are filtering on.
	dynamic term;               // What term to filter on. May be null, which will be ignored.
	FilterType type = FilterType.and;

	// Cached regular expression that may or may not apply. We use a simple static cache pattern.
	static RegExp? cachedRegExp;
	static String? cachedRegExpTerm;

	// Create a filter for standard and-operations only.
	Filter.andFilter(this.fieldName, this.term);

	// Specialized global (any-field) filter, designed for use in global searches only.
	Filter.globalFilter(List<String> terms) {
		fieldName = '*';
		term = terms;
		type = FilterType.global;
	}

	// Check if this filter passes a specific mote or not.
	bool passes(Mote m) {
		if (term == null) {     // No term implies always successful filter.
			return true;
		}

		// Special handling for global matches that always does string comparison and compares all fields.
		if (type == FilterType.global) {
			final consolidatedValue = m.payload.values.map((v) => v.toString()).toList().join(' ');
			if (cachedRegExp == null || cachedRegExpTerm != term.hashCode.toString()) {
				cachedRegExpTerm = term.hashCode.toString();
				cachedRegExp = RegExp((term as List<String>).map((t) => RegExp.escape(t)).toList().join('|'), caseSensitive: false);
			}
			return consolidatedValue.contains(cachedRegExp!);
		}

		// TODO: Replace with typing system from Field!
		final dynamic moteValue = m.payload[fieldName];     // (may be null)

		// String comparison can just be matching, but we need to use a regexp for case-insensitivity.
		if (term is String && moteValue is String) {
			if (cachedRegExp == null || cachedRegExpTerm != term) {
				cachedRegExpTerm = term;
				cachedRegExp = RegExp(RegExp.escape(term), caseSensitive: false);
			}
			return moteValue.contains(cachedRegExp!);
		}
		// Otherwise fall back to int and double comparisons
		if ((term is int && moteValue is int) || (term is double && moteValue is double)) {
			return term == moteValue;
		}
		if (term is double && moteValue is int) {       // Less precision in value
			return (term as double).toInt() == moteValue;
		}
		if (term is int && moteValue is double) {       // Less precision in search term
			return term == moteValue.toInt();
		}
		// Otherwise always fail, for now.
		return false;
	}
}

