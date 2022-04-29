import 'mote.dart';

class SortMethod {
	// Sort methods always are sorted by 'ascending' or 'descending' modes.
	// TODO: Implement unique sort modes found in web version!
	late String fieldName;      // Field name we are sorting on.
	bool isAscending = true;

	SortMethod.normalSort(this.fieldName, this.isAscending);

	// Provide a comparison function for this sorting mode.
	int comparator(Mote a, Mote b) {
		// TODO: Replace with typing system from Field!
		dynamic valueA = a.payload[fieldName];      // (may be null)
		dynamic valueB = b.payload[fieldName];

		// For now, we always sort by simple string comparison unless we know this is a number.
		valueA ??= ''; valueB ??= '';
		if (valueA is num && valueB is num) {
			return valueA == valueB ? 0 : (valueA > valueB ? 1 : -1);
		}
		valueA = valueA.toString();
		valueB = valueB.toString();
		return valueA.compareTo(valueB);
	}

	// Provides the default 'sort' mode fallback for all motes, executed if no sort method is provided.
	static int defaultComparator(Mote a, Mote b) {
		return a.id - b.id;
	}
}

