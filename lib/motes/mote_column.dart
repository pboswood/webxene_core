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

	List<Mote> _moteView = [];          // List of cachedMotes from page that have been pre-filtered and sorted.
	bool _moteViewCalculated = false;   // If we have calculated the mote view (sanity check)

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

	// Compute a view upon this column with a new set of filters/sort methods.
	void calculateMoteView() {
		_moteView = page.cachedMotes.where(_filterWhere).toList();
		_moteView.sort(sortMethods.isEmpty ? SortMethod.defaultComparator : _sortMultipleComparators);
		_moteViewCalculated = true;
	}

	// Return a filtered and sorted paginated view of motes from within our parent page via this column.
	// There are three ways to use this, depending on parameter passed:
	// pageNum: fetch page 0-n of results, each containing {capacity} items (or 0).
	// afterMoteId: fetch {capacity} motes after the entry with id {afterMoteId} (exclusive) - requires default mote ID sorting
	// afterIndex: fetch {capacity} motes after entry with index {afterIndex} (exclusive)
	List<Mote> getMoteViewPage({ int? pageNum, int? afterMoteId, int? afterIndex, int capacity = 20, bool unpaginated = false }) {
		if (!_moteViewCalculated) {
			throw Exception("Mote view uninitialized - calculateMoteView() must be called before use!");
		}
		if (capacity <= 0) {
			throw Exception("Invalid page capacity in getMoteViewPage");
		}
		if (_moteView.length == 0) {
			return [];
		}
		if (unpaginated) {
			return _moteView;
		}

		int? start, end;
		if (pageNum != null) {      // (page number 0 starts at 0, ends at 19)
			start = (pageNum * capacity);
			end = start + capacity - 1;
		}
		if (afterMoteId != null) {
			for (int idx = 0; idx < _moteView.length; idx++) {
				if (_moteView[idx].id > afterMoteId) {
					start = idx;
					end = start + capacity - 1;
					break;
				}
			}
		}
		if (afterIndex != null) {
			start = afterIndex + 1;
			end = start + capacity - 1;
		}

		if (start == null || end == null) {
			throw Exception("Invalid use of getMoteViewPage - must specify pagination parameter!");
		}
		if (end > _moteView.length)
			end = _moteView.length;
		return _moteView.sublist(start, end);
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