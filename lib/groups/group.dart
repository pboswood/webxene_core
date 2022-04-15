import "dart:collection";
import 'dart:convert';
import 'page.dart';

class Group {
	int id = 0;
	String name = '';
	int timestamp = 0;                      // UNIX timestamp of last mote update
	int? highestReserved;                   // Highest mote in conversations
	Map<String, dynamic> options = {};      // JSON for advanced group options

	// Values passed in user's main group list fetch, that may not exist elsewhere.
	int? lastVisit;                         // Last visit time as UNIX timestamp for logged in user.
	int? memberCount;                       // Number of members in this group at time of fetch.
	int? outstanding;                       // Outstanding items count for logged in user.


	// Menu implementation - Page objects are also stored in our group manager for
	// direct fetching, but remain in a ordered list here as well for menu rendering.
	// Note that pages fetched in the menu are generally contain only a subset of the
	// full data fetched in the full page API request.
	List<Page> orderedMenu = [];

	bool _amAdmin = false;                  // If group handler returned that we had admin privileges during fetch. This is either group admin or instance admin.
	bool get hasAdmin => _amAdmin;          // If current user had admin privileges (either group or instance).

	// Construct a group from JSON, optionally parsing the menu.
	Group.fromJson(Map<String, dynamic> json) {
		id = json['id'];
		name = json['name'];
		timestamp = json['timestamp'];
		highestReserved = json['highest_reserved'];
		options = json['options'] == null ? {} : jsonDecode(json['options']);
		// TODO: Deal with 'outstanding' parameter for tracking unread pages.
		_amAdmin = json['am_admin'] ?? false;

		lastVisit = json['last_visits'];
		memberCount = json['membercount'];

		// Parse out menu as well if it exists.
		if (json['menu'] != null && json['menu'] is List) {
			final jsonMenu = json['menu'] as List;
			for (var menuItem in jsonMenu) {
				orderedMenu.add(Page.fromJson(menuItem, partialData: true));
			}
			orderedMenu.sort((a, b) => a.menuOrder - b.menuOrder);
		}
	}
}