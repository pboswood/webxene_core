import 'dart:collection';
import 'instance_manager.dart';
import 'users/user.dart';

// Manager for handling all attribution and user caching.
class UserManager {
	static UserManager? _instance;
	factory UserManager() => _instance ??= new UserManager._singleton();
	UserManager._singleton();       // Empty singleton constructor

	final Map<int, User> _userCache = {};           // Cache of user objects, used for advanced fetching.
	final Map<int, String> _attribCache = {};       // Cache of simple attribution of user ID to name, fall-through if user data not available.

	// Invalidate a specific user.
	invalidateUser(int id) {
		_userCache.remove(id);
		_attribCache.remove(id);
	}
	invalidateAllUsers() {
		_userCache.clear();
		_attribCache.clear();
	}

	// Get attribution information for a specific user ID. Returns username
	// of a specific user ID, or string equivalent if unknown (e.g. #123).
	String getAttribName(int uid) {
		if (_userCache.containsKey(uid)) {
			return _userCache[uid]!.name;
		}
		return _attribCache[uid] ?? "#$uid";
	}

	// Incorporate an 'attrib' structure from APIResponse returns, which are
	// automatically sent along with some responses to point UIDs to Usernames.
	autoloadAttribution(APIResponse apiResponse) {
		if (apiResponse.response.statusCode != 200 || apiResponse.result == null) {
			return;
		}
		// We only deal with Map-type responses for now.
		if (apiResponse.result is! Map) {
			return;
		}
		final resultMap = apiResponse.result as Map<String, dynamic>;
		if (!resultMap.containsKey('attrib') && !resultMap.containsKey('attribution')) {
			return;
		}
		// Attrib hashmap should be a JSON map of objects, e.g. { 1: { id: 1, name: Abc }, 2: ... }
		final attribHashmap = (resultMap.containsKey('attrib') ? resultMap['attrib'] : resultMap['attribution']) as Map<String, dynamic>;
		for (var attribVal in attribHashmap.values) {
			if (attribVal is! Map || !attribVal.containsKey('id') || !attribVal.containsKey('name')) {
				continue;
			}
			_attribCache[attribVal['id']] = attribVal['name'];
		}
	}
}
