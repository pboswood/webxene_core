import "dart:collection";
import 'dart:convert';
import '../motes/mote.dart';

class Page {
	int id = 0;                             // ID of the page object
	String name = '';                       // Full title name of this page
	String type = '';                       // String type of the page, e.g. 'carddeck'. TODO: Enum?
	int groupId = 0;                        // Group ID this page belongs to
	int menuOrder = 0;                      // Menu order for sorting
	int timestamp = 0;                      // Timestamp of last page update
	int highestMote = 0;                    // Highest mote ID stored in this page
	Map<String, dynamic> options = {};      // JSON for advanced page options
	bool internal = false;                  // If this page should be hidden from display normally
	String icon = '';                       // Icon to render, usually material/f7 prefix.
	String menuName = '';                   // Label to display in menu instead of 'name' parameter.

	bool _partial = true;                   // If this is partial data (from a group menu fetcher), or full data from page fetch.
	get isPartialData => _partial;
	List<Mote> cachedMotes = [];            // List of cached motes from a full fetch of this page.

	// Parse a page from JSON, which may come from a menu item (from group fetch),
	// or direct page fetch. The menu item will have less data.
	Page.fromJson(Map<String, dynamic> json, { bool partialData = false }) {
		id = json['id'];
		name = json['name'];
		type = json['type'];
		groupId = json['group_id'] ?? 0;
		menuOrder = json['menu_order'] ?? 0;
		timestamp = json['timestamp'] ?? 0;
		highestMote = json['highest_mote'] ?? 0;
		options = json['options'] == null ? {} : jsonDecode(json['options']);
		internal = (json['internal'] ?? 0) == 0 ? false : true;
		icon = json['icon'] ?? '';
		menuName = json['menu_name'] ?? '';
		_partial = partialData;
	}
}