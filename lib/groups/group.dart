import "dart:collection";
import 'dart:convert';
import 'package:webxene_core/crypto/user_crypto.dart';
import 'package:webxene_core/instance_manager.dart';

import '../users/user.dart';
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

	// Groups may have a list of user_id => keys that are obtained for crypto purposes.
	Map<int, UserCryptoKeys>? memberKeys;

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

	// Fetch and fill member crypto keys for this group.
	Future<void> FetchMemberKeys() async {
		final apiKeys = await InstanceManager().apiRequest('keypairs/target', {
			'type': 'group',
			'id': id.toString(),
		});
		if (!apiKeys.success(APIResponseJSON.list)) {
			throw Exception("Failed to fetch member crypto keys for group (Error ${apiKeys.response.statusCode}: ${apiKeys.response.reasonPhrase ?? 'Unknown error'}");
		}

		memberKeys?.clear();
		memberKeys ??= {};
		for (Map<String, dynamic> cryptoKey in apiKeys.result) {
			final importedKeys = UserCryptoKeys();
			await importedKeys.ImportPublicJSON(cryptoKey['encrypt_public'], cryptoKey['sign_public'], cryptoKey['id'], cryptoKey['user_id']);
			memberKeys![cryptoKey['user_id']] = importedKeys;
		}
	}
}