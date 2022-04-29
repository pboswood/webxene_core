import 'dart:convert';
import 'groups/group.dart';
import 'groups/page.dart';
import 'instance_manager.dart';
import 'mote_manager.dart';
import 'motes/mote.dart';
import 'user_manager.dart';

// Manager for handling all group and page fetches and caching.
class GroupManager {
	static GroupManager? _instance;
	factory GroupManager() => _instance ??= new GroupManager._singleton();
	GroupManager._singleton();       // Empty singleton constructor

	final Map<int, Group> _groupCache = {};
	final Map<int, Page> _pageCache = {};

	// Invalidate a given group or all of them. Invalidating a group will clear
	// the pages of this group as well.
	invalidateGroup(int id) {
		_groupCache.remove(id);
		_pageCache.removeWhere((key, value) => value.groupId == id);
	}
	invalidateAllGroups() {
		_groupCache.clear();
		_pageCache.clear();
	}

	// Invalidate a page or list of pages.
	invalidatePage(int id) {
		_pageCache.remove(id);
	}
	invalidatePages(List<int> ids, { bool allPages = false }) {
		if (allPages) {
			_pageCache.clear();
		} else {
			for (int id in ids) {
				_pageCache.remove(id);
			}
		}
	}

	// Fetch a single group and all pages related to it.
	Future<Group> fetchGroup(int id) async {
		// If we have a cache hit, just return that.
		if (_groupCache.containsKey(id)) {
			return _groupCache[id]!;
		}

		// Otherwise fetch from our API.
		final apiGroup = await InstanceManager().apiRequest('groups/' + id.toString());
		if (!apiGroup.success(APIResponseJSON.map)) {
			throw Exception("Failed to fetch group (error " + apiGroup.response.statusCode.toString() + ")");
		}

		final groupObj = Group.fromJson(apiGroup.result);
		// Parse out all pages into our page cache as well.
		if (groupObj.orderedMenu.isNotEmpty) {
			for (Page p in groupObj.orderedMenu) {
				_pageCache[p.id] = p;
				// TODO: What about existing pages? How do we know the last fetch wasn't a 'full' fetch with motes, etc. and thus more recent?
			}
		}
		return groupObj;
	}

	// Fetch complete details on a single page, which also automatically gives us a preliminary mote list.
	// If we are viewing a subpage that needs to be filtered by a mote, it must be provided as the 'subviewMote' parameter!
	Future<Page> fetchPageAndMotes(int pageId, { bool forceRefresh = false, subviewMote = 0 }) async {
		// Use page cache if we have a non-partial result.
		if (!forceRefresh && _pageCache.containsKey(pageId) && !_pageCache[pageId]!.isPartialData) {
			// TODO: Caching for subviewMote pages?
			if (subviewMote == 0) {
				return _pageCache[pageId]!;
			}
		}

		final apiPage = await InstanceManager().apiRequest('pages/' + pageId.toString(), {
			'subview': subviewMote.toString(),
		});
		if (!apiPage.success(APIResponseJSON.map)) {
			throw Exception("Failed to fetch page (error " + apiPage.response.statusCode.toString() + ")");
		}
		final pageObj = Page.fromJson(apiPage.result);
		_pageCache[pageId] = pageObj;

		// Deal with optional attribution section which details usernames.
		UserManager().autoloadAttribution(apiPage);
		// Deal with optional motes section which lists all motes used in page.
		pageObj.cachedMotes  = await MoteManager().autoloadFromPageRequest(apiPage);

		return pageObj;
	}
}
