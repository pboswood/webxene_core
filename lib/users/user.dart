import '../groups/group.dart';
import '../instance_manager.dart';
import '../auth_manager.dart';
import '../crypto/user_crypto.dart';

class User with UserCrypto {
	int id = 0;
	String name = '';
	String? email;
	String? phone;

	User();     // Empty user constructor for non-logged in users, id = 0.

	User.fromJson(Map<String, dynamic> json) {
		id = json['id'];
		name = json['name'];
		email = json['email'];
		phone = json['phone'];
	}

	// Fetch a list of groups we are a member of, along with all metadata for rendering main groups list.
	// Will only work for the currently logged in user - you cannot see what groups someone else is in.
	Future<List<Group>> getSelfGroupsList() async {
		if (id == 0 || id != AuthManager().loggedInUser.id) {
			throw Exception("Attempted to get joined groups of a user we are not logged in as!");
		}
		final apiGroups = await InstanceManager().apiRequest("users/" + id.toString() + "/groups");
		if (!apiGroups.success(APIResponseJSON.map)) {
			throw Exception("Failed to fetch main group list (Error ${apiGroups.response.statusCode}: ${apiGroups.response.reasonPhrase ?? 'Unknown error'}");
		}
		// apiGroups returns partial group data that should not be used in group_manager!
		final groups = apiGroups.result['groups'];
		if (groups is! List || groups.length == 0) {
			return [];
		}

		final Map<String, dynamic> lastVisits = apiGroups.result['last_visits'] is Map ? apiGroups.result['last_visits'] : {};
		final Map<String, dynamic> memberCount = apiGroups.result['membercount'] is Map ? apiGroups.result['membercount'] : {};
		return groups.map((group) {
			String groupId = group['id']?.toString()?.trim() ?? '';     // NB: Needs to be string to lookup in above Maps.
			if (groupId == '' || int.tryParse(groupId) == null) {
				throw Exception("Missing or invalid ID in self group list!");
			}
			group['last_visits'] = lastVisits.containsKey(groupId) ? lastVisits[groupId] : null;
			group['membercount'] = memberCount.containsKey(groupId) ? memberCount[groupId] : null;
			return Group.fromJson(group);
		}).toList();
	}

}

