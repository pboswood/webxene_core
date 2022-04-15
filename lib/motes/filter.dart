import 'mote.dart';

class Filter {
	// NB: Filtering is done by string because filters can apply to multiple schemas!
	late String fieldName;      // Field name we are filtering on.
	dynamic term;               // What term to filter on. May be null, which will be ignored.

	Filter.andFilter(this.fieldName, this.term);

	// Check if this filter passes a specific mote or not.
	bool passes(Mote m) {
		if (term == null) {     // No term implies always successful filter.
			return true;
		}
		// TODO: Replace with typing system from Field!
		final dynamic moteValue = m.payload[fieldName];     // (may be null)
		// String comparison can just be matching
		if (term is String && moteValue is String) {
			return moteValue.contains(term);
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

