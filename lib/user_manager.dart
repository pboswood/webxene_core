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

	// Force-load attribution for a list of user IDs. This will query for any
	// user IDs not in cache, and async-fetch their attribution. Usually only
	// used for specific places (e.g. user-references) where we want to check
	// we have all attribution info loaded.
	Future<void> ensureCachedAttribution(List<int> userIds) async {
		// If we have all ids cached, we can exit early.
		if (userIds.isEmpty || userIds.every((id) => _userCache.containsKey(id) || _attribCache.containsKey(id))) {
			return;
		}

		final uids = userIds.map((id) => id.toString()).toList();
		final apiAttrib = await InstanceManager().apiRequest('users/attrib', { 'uids[]': uids });
		if (!apiAttrib.success(APIResponseJSON.map)) {
			throw Exception("Attribution request failed for user lookup!");
		}
		final apiAttribMap = apiAttrib.result as Map<String, dynamic>;      // Returned data is keyed by user ID.
		for (var attribEntry in apiAttribMap.values) {
			var attribObj = attribEntry as Map<String, dynamic>;
			_attribCache[attribObj['id']] = attribObj['name'];
		}
		return;
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
		autoloadAttributionMap(attribHashmap);
	}

	// Autoload JSON data of cattribution from a map manually - usually from JSON.
	autoloadAttributionMap(Map<String, dynamic> attribMap) {
		for (var attribVal in attribMap.values) {
			if (attribVal is! Map || !attribVal.containsKey('id') || !attribVal.containsKey('name')) {
				continue;
			}
			_attribCache[attribVal['id']] = attribVal['name'];
		}
	}

}
