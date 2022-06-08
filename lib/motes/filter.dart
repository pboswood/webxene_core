import 'mote.dart';

class Filter {
	// NB: Filtering is done by string because filters can apply to multiple schemas!
	late String fieldName;      // Field name we are filtering on.
	dynamic term;               // What term to filter on. May be null, which will be ignored.

	// Cached regular expression that may or may not apply. We use a simple static cache pattern.
	static RegExp? cachedRegExp;
	static String? cachedRegExpTerm;

	Filter.andFilter(this.fieldName, this.term);

	// Check if this filter passes a specific mote or not.
	bool passes(Mote m) {
		if (term == null) {     // No term implies always successful filter.
			return true;
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

