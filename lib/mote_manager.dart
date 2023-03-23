import 'dart:convert';
import 'auth_manager.dart';
import 'instance_manager.dart';
import 'motes/field.dart';
import 'motes/filter.dart';
import "motes/mote.dart";
import 'motes/schema.dart';

class MoteManager {
	static MoteManager? _instance;
	factory MoteManager() => _instance ??= new MoteManager._singleton();
	MoteManager._singleton();       // Empty singleton constructor

	final Map<int, Mote> _moteCache = {};

	// Invalidate the given mote ID or list of IDs.
	invalidateMote(int id) {
		_moteCache.remove(id);
	}
	invalidateMotes(List<int> ids, { bool allMotes = false }) {
		if (allMotes) {
			_moteCache.clear();
		} else {
			for (var id in ids) {
				_moteCache.remove(id);
			}
		}
	}
	// Manually cache a mote (used for updates and store returns which auto-cache)
	forceCacheMote(Mote m) {
		if (m.id != 0) {
			_moteCache[m.id] = m;
		}
	}

	// Fetch a cached mote if it exists, or return null.
	Mote? getCache(int id) {
		return _moteCache[id];
	}

	// Fetch a single mote as given by the mote ID and a group ID. Usually used only for looking up relations,
	// as we normally fetch a sequence given by a page or something else.
	Future<Mote> fetchMote(int id, int gid) async {
		final moteList = await fetchMotes(List<int>.filled(1, id), gid);
		final moteObj = moteList.firstWhere((mote) => mote.id == id,
			orElse: () => throw NotFoundException());
		return moteObj;
	}
	Future<List<Mote>> fetchMotes(List<int> ids, int gid) async {
		final List<Mote> returnMotes = [];

		// Take what we can from the mote cache, removing those we satisfy.
		List<int> toFetch = [];
		for (int id in ids) {
			if (_moteCache.containsKey(id)) {
				returnMotes.add(_moteCache[id]!);
			} else {
				toFetch.add(id);
			}
		}

		// If we have a full cache hit, just return this.
		if (toFetch.isEmpty) {
			return returnMotes;
		}

		// Otherwise fetch a list of motes using our API.
		print("fetchMote: remote fetching ${toFetch.length} motes...");
		try {
			final List<String> toFetchStr = toFetch.map((e) => e.toString()).toList();
			final fetchRequest = await InstanceManager().apiRequest('motes/relationMotes', {
				'ids[]': toFetchStr,
				'gid': gid.toString(),
				'full': '1',
			});
			if (!fetchRequest.success(APIResponseJSON.list)) {
				throw Exception("Failed to fetch mote sequence (error " + fetchRequest.response.statusCode.toString() + ")");
			}

			final List<Mote> returnMotes = [];
			final fetchMotes = fetchRequest.result as List;
			// Multi-threaded implementation, broken!
			/*
			await Future.forEach(fetchMotes, (m) {
				Mote initializedMote = Mote.fromEncryptedJson(m as Map<String, dynamic>);
				initializedMote.decryptMote().then((_) {        // (decryptMote has Future<void> return)
					returnMotes.add(initializedMote);
					_moteCache[initializedMote.id] = initializedMote;
				});
			});
			*/

			// Single-threaded implementation.
			var timerInterpret = Stopwatch()..start();
			int timerCounter = 0;
			for (var m in fetchMotes) {
				try {
					Mote initializedMote = Mote.fromEncryptedJson(m);
					await initializedMote.decryptMote();
					returnMotes.add(initializedMote);
					_moteCache[initializedMote.id] = initializedMote;
					if (timerCounter++ > 100) {
						timerCounter = 0;
						print("fetchMote: Processed chunk of 100 motes [elapsed ${timerInterpret.elapsedMilliseconds}ms]");
					}
				} catch (ex) {
					// On failure of initializing a mote (JSON decode / encryption), we 'fetch' nothing.
					print(ex);
				}
			}
			timerInterpret.stop();
			print("fetchMote: Elapsed decrypt/interpret (single-thread): ${timerInterpret.elapsedMilliseconds} ms.");

			return returnMotes;
		} catch (ex) {
			//throw Exception("Failed to fetch mote sequence");
			rethrow;
		}
	}

	// Automatically load and cache motes from a page request, usually called by GroupManager.
	// This is the normal route of loading motes - from a page request. Returns a list of
	// the loaded motes, which may be empty.
	Future<List<Mote>> autoloadFromPageRequest(APIResponse apiPage) async {
		if (apiPage.result is! Map) {
			return [];
		}
		final List<dynamic> jsonMotes = (apiPage.result as Map<String, dynamic>)['motes'] ?? [];
		final List<Mote> returnMotes = [];
		// TODO: Multithread this?
		print("Autoload: Processing ${jsonMotes.length} motes from page data.");
		var timerInterpret = Stopwatch()..start();
		for (var jsonMote in jsonMotes) {
			try {
				Mote initializedMote = Mote.fromEncryptedJson(jsonMote);
				await initializedMote.decryptMote();
				returnMotes.add(initializedMote);
				_moteCache[initializedMote.id] = initializedMote;
			} catch (ex) {
				// On failure of initializing a mote (JSON decode / encryption), warn but continue.
				print(ex);
			}
		}
		timerInterpret.stop();
		print("Autoload: Elapsed decrypt/interpret (single-thread): ${timerInterpret.elapsedMilliseconds} ms.");

		return returnMotes;
	}

	// Search globally for a series of motes, constrained by type. This is a global search that
	// is not constrained by fields (like filters) but looks in every indexed field/title entry instead.
	Future<List<Mote>> searchMoteGlobalIndex({ required int groupId, required List<String> searchTerms, List<Schema>? moteTypes }) async {
		final params = {
			'terms': searchTerms,
			'group_id': groupId.toString(),
		};
		if (moteTypes != null) {
			params['type_ids'] = moteTypes.map((s) => s.id.toString()).toList();
		}
		final searchRequest = await InstanceManager().apiRequest('moteindex/search', params, 'POST');
		if (!searchRequest.success(APIResponseJSON.list)) {
			throw Exception("Failed to fetch mote global index search (error " + searchRequest.response.statusCode.toString() + ")");
		}

		Filter globalFilter = Filter.globalFilter(searchTerms);
		
		List<Mote> returnMotes = [];
		for (var searchMote in (searchRequest.result as List)) {
			try {
				Mote initializedMote = Mote.fromEncryptedJson(searchMote);
				await initializedMote.decryptMote();
				_moteCache[initializedMote.id] = initializedMote;
				// Discard this mote if it doesn't pass our search request fully.
				if (!globalFilter.passes(initializedMote)) {
					continue;
				}
				returnMotes.add(initializedMote);
			} catch (ex) {
				// On failure of initializing a mote (JSON decode / encryption), warn but continue.
				print(ex);
			}
		}

		return returnMotes;
	}

	// Create/Update a mote from a mote object. This can be an existing mote, or a new blank mote from the
	// Mote.fromBlank constructor.
	Future<Mote> saveMote(Mote mote) async {
		if (!mote.groupType) {          // TODO: Implement non-group mote updates!
			throw "Unimplemented: non-group mote updates";
		} else if (mote.typeId <= 0) {  // TODO: Implement handling for schema-less motes!
			throw "Unimplemented: non-schema mote updates";
		}

		// Validate mote is allowed to be saved in this form. Require it has a title, etc.
		if (!mote.payload.containsKey('title') || mote.payload['title'].toString().trim() == '') {
			throw "Mote is missing title in payload, unable to save #${mote.id}";
		}
		// TODO: Validation at field levels, etc.

		// TODO: What about relationships? Parent-relationships?
		// TODO: Handling or warning for: prefixes, email-integrations, uniqueness checks, series-updates
		// TODO: Indexing generation?

		// Re-integrate our attachments into the mote payload.
		mote.generateAttachments();

		await mote.encryptMote();
		if (mote.encryptedCommit == null) {
			throw "Failed to generate mote commit for update";
		}

		final ownKeyId = AuthManager().loggedInUser.cryptoKeys.internalKeyId;
		final ownDockey = ownKeyId == 0 ? null : mote.encryptedCommit!.item2[ownKeyId];
		if (ownDockey == null) {
			throw Exception("Failed to isolate own dockey for logged in key after update of mote.");
		}
		final ownDockeyB64 = jsonDecode(ownDockey)[2];       // Parse directly from [uid,kid,base64] representation.

		final commitUrl = mote.isUnsaved ? "motes" : "motes/${mote.id}";
		final commitRequest = await InstanceManager().apiRequest(commitUrl, {
			'group_id': mote.targetId.toString(),
			'page_id': mote.domainId.toString(),
			'payload': mote.encryptedCommit!.item1,
			'dockeys': mote.encryptedCommit!.item2.values.toList(),
			'schema': mote.typeId.toString(),
			'indexing': [],             // TODO: Implement!
			'series-updates': [],       // TODO: Implement!
			'parent': mote.parentRelationAsPostArray,
			'_method': mote.isUnsaved ? 'POST' : 'PATCH',
		}, 'POST');
		if (!commitRequest.success(APIResponseJSON.map)) {
			throw Exception("Failed to save mote (error ${commitRequest.response.statusCode}: ${commitRequest.response.reasonPhrase}");
		}

		// Invalidate mote cache and replace with returned data.
		if (mote.id != 0) {
			MoteManager().invalidateMote(mote.id);
		}
		// If parent-relationship was created, invalidate the parent mote as well.
		if (mote.parentRelationAsMoteId > 0) {
			MoteManager().invalidateMote(mote.parentRelationAsMoteId);
		}
		final savedMote = Mote.fromEncryptedJson(commitRequest.result, overrideDockey: ownDockeyB64);
		await savedMote.decryptMote();
		forceCacheMote(savedMote);
		return savedMote;
	}


}
