import 'dart:convert';
import 'auth_manager.dart';
import 'instance_manager.dart';
import "motes/mote.dart";

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
				"ids[]": toFetchStr,
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
}
