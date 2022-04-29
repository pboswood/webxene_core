import 'dart:collection';
import 'filter.dart';
import 'sort_method.dart';
import '../groups/page.dart';
import '../instance_manager.dart';
import 'mote.dart';
import 'schema.dart';

// A column represents a collection of motes within a page that are displayed together (usually same schema type).
// It can be displayed, manipulated, filtered, sorted, etc.
class MoteColumn {
	late Page page;                     // Page this column originated from.
	int id = 0;                         // Internal identifier for column. Should be 1+ only!
	String title = '';                  // Title / label for this column
	List<Schema> schemas = [];          // List of schemas visible in this column.
	List<Filter> filters = [];          // List of filters active for this column.
	List<SortMethod> sortMethods = [];  // List of sorting methods active for this column.

	Set<int> get validSchemaIds {
		_validSchemaIdsCache ??= schemas.map((s) => s.id).toSet();
		return _validSchemaIdsCache!;
	}
	Set<int>? _validSchemaIdsCache;

	// TODO: Integrate (unused) column info from webxene: multi-line, interactions, etc?
	// TODO: Default sort, default filters

	MoteColumn.fromCarddeckOptions(this.page, Map<String, dynamic> categoryData) {
		id = categoryData['id'] is String ? int.parse(categoryData['id']) : categoryData['id'];
		title = categoryData['title'];
		if (categoryData['sources'] != null && categoryData['sources'] is List) {
			for (var source in (categoryData['sources'] as List)) {
				var schema = InstanceManager().schemaByType(source as String);
				schemas.add(schema);
			}
		}
	}

	// Get a list of all 'filters' possible for this column. This can also be used to provide sort methods.
	List<String> allPossibleFilters() {
		// Get a list of list of headers from CSV.
		final listsOfHeaders = schemas.map((s) => s.schemaHeadersCSV.split(',')).toList();
		// Flatten all into a single list.
		final flattenHeaders = listsOfHeaders.expand((i) => i).toList();
		// Make this list unique and return it in correct order.
		final seenSet = <String>{};
		return flattenHeaders.where((val) => seenSet.add(val)).toList();        // (set add will return true if insertion succeeded)
	}

	// Return a filtered and sorted view of motes from within our parent page via this column.
	List<Mote> getMoteView() {
		final filteredMotes = page.cachedMotes.where(_filterWhere).toList();
		if (sortMethods.isEmpty) {
			filteredMotes.sort(SortMethod.defaultComparator);
		} else {
			filteredMotes.sort(_sortMultipleComparators);
		}
		return filteredMotes;
	}

	// Filtering function for a single mote to check if it passes all 'filters'.
	bool _filterWhere(Mote m) {
		// Always enforce a filter for schema types since we are dealing with the raw mote feed.
		if (!validSchemaIds.contains(m.typeId)) {
			return false;
		}
		if (filters.isEmpty) {
			return true;
		}
		for (var filter in filters) {
			if (!filter.passes(m)) {
				return false;
			}
		}
		return true;
	}

	// Generic sorting method that allows use of multiple comparators to sort.
	int _sortMultipleComparators(Mote a, Mote b) {
		int compareResult = 0;
		for (int i = 0; i < sortMethods.length; i++) {
			compareResult = sortMethods[i].comparator(a, b);
			if (compareResult != 0) {
				return compareResult;
			}

		}
		return SortMethod.defaultComparator(a, b);
	}
}