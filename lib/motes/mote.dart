import "dart:collection";
import 'dart:convert';
import 'package:tuple/tuple.dart';
import '../mote_manager.dart';
import '../instance_manager.dart';
import '../auth_manager.dart';
import '../user_manager.dart';
import "mote_comment.dart";
import '../crypto/mote_crypto.dart';
import 'mote_relation.dart';

class Mote with MoteCrypto {
	int id = 0;
	Map<String, dynamic> payload = {};
	Queue<MoteComment> comments = Queue();
	List<MoteRelation> relationships = [];      // (stores all relationships involving this mote, including reverse relationships)
	int typeId = 0;                 // Schema type ID
	int seqId = 0;                  // Version sequence ID, incremented by one each update.
	String dockey = "";             // Dockey for ourselves as B64 (we don't store generated dockeys for others)
	String payloadEncrypted = "";   // Encrypted payload as String JSON.
	int timestamp = 0;              // UNIX timestamp of the mote creation date.

	// Targeting for motes
	int sourceId = 0;               // Source user this mote is from
	int targetId = 0;               // Destination user/group
	bool groupType = false;         // If destination is a group
	int domainId = 0;               // Conversation ID or page ID if groupType.
	int folderId = 0;               // Folder for drive motes, 0 indicates root folder.

	Mote();         // Empty constructor can use default id=0 to initialize new motes.

	// Construct a loaded yet still encrypted mote from JSON input.
	Mote.fromEncryptedJson(Map<String, dynamic> json) {
		id = json['id'];
		typeId = json['type_id'] ?? 0;
		seqId = json['seq_id'] ?? 0;
		payloadEncrypted = json['payload'];
		dockey = json['dockey'];
		sourceId = json['source_id'] ?? 0;
		targetId = json['target_id'] ?? 0;
		groupType = (json['group_type'] ?? 0) == 0 ? false : true;
		domainId = json['domain_id'] ?? 0;
		folderId = json['folder_id'] ?? 0;
		timestamp = json['timestamp'] ?? 0;
		relationships = json['relationships'] == null ? [] :
			(json['relationships'] as List).map((r) => MoteRelation.fromMoteJson(r, this)).toList();
		// Motes may also contain internal attribution info if from specific sources,
		// we can automatically cache these details if we get them.
		if (json['attrib'] != null && json['attrib'] is Map) {
			UserManager().autoloadAttributionMap(json['attrib'] as Map<String, dynamic>);
		}
	}

	// Decrypt a mote from the encrypted values loaded by our constructor, as the current user.
	Future<void> decryptMote() async {
		try {
			payload = await decryptMotePayload(AuthManager().loggedInUser, dockey, payloadEncrypted);
			normalizeRelationships();
			// TODO: Deal with comments, relationships
		} catch(ex) {
			rethrow;
		}
	}

	// Encrypt a mote from the decrypted values, replacing the encrypted ones with them.
	Future<void> encryptMote() async {
		try {
			// TODO: Deal with sub-group target lists and non-group targets.
			// TODO: Fetch group list of users.
			var encryptionReturn = encryptMotePayload(AuthManager().loggedInUser, [], jsonEncode(payload));
		} catch(ex) {
			rethrow;
		}
	}

	// Helper function to get string representations of a mote's headers + payload CSV for UI.
	static Tuple2<String, List<String>> interpretMotesCSV(List<Mote> motes) {
		final uniqueTypes = motes.map((m) => m.typeId).toSet().toList();
		if (uniqueTypes.length > 1) {
			throw UnimplementedError("Cannot automatically interpret list of motes with multiple types yet!");
		}
		try {
			final schema = InstanceManager().schemaById(uniqueTypes.first);
			return Tuple2(schema.schemaHeadersCSV, motes.map((m) => schema.interpretMoteCSV(m)).toList());
		} catch (ex) {
			// TODO: Rewarn on this and fallback to common fields only?
			rethrow;
		}
	}

	// Fill relations into payload, overriding existing payload entries with the actual MoteRelation object.
	// This makes it easier to lookup relationships, etc. using purely the payload. However, Mote.retrieveReferences()
	// must still be called in order to finalize the mote relationship IDs into actual Mote objects.
	void normalizeRelationships() {
		Set<String> warnedFieldKeys = {};
		String fieldKey;

		for (var r in relationships) {
			fieldKey = r.relationFieldKey(id);
			if (!warnedFieldKeys.contains(fieldKey)) {
				warnedFieldKeys.add(fieldKey);
				if (payload[fieldKey] != null) {
					print("Warning: overriding payload[$fieldKey] with MoteRelation data list!");
				}
				payload[fieldKey] = <MoteRelation>[];
			}
			(payload[fieldKey] as List<MoteRelation>).add(r);
		}
	}

	// Function to retrieve any mote and user relation references that might be needed and cache them.
	// This automatically fills in the MoteRelation references that can be followed for a series of motes.
	static Future<void> retrieveReferences(List<Mote> targetMotes, int gid) async {
		// Get a list of all MoteRelations in our targetMotes that are not already fetched.
		final List<MoteRelation> relations = [];
		for (var m in targetMotes) {
			for (var r in m.relationships) {
				if (r.referencedSource == null || r.referencedTarget == null) {
					relations.add(r);
				}
			}
		}

		// Request cached-fetch of all mentioned motes. Note that some (or all) references may be
		// user-references, which are fetched separately.
		final mentionedMotes = HashSet<int>();
		final mentionedUsers = HashSet<int>();
		for (var r in relations) {
			// Source is ALWAYS a mote!
			mentionedMotes.add(r.sourceId);
			// Target may be a user or mote.
			if (r.isUserTarget) {
				mentionedUsers.add(r.targetId);
			} else {
				mentionedMotes.add(r.targetId);
			}
		}
		print("Reference fetch: ${mentionedMotes.length} motes, ${mentionedUsers.length} users");
		try {
			// NB: Returns for below fetches discarded; we only want motes to cache!
			await Future.wait([
				MoteManager().fetchMotes(mentionedMotes.toList(), gid),
				UserManager().ensureCachedAttribution(mentionedUsers.toList()),
			]);
		} catch (ex) {
			rethrow;
		}

		// Fulfill relationship references for each relation object from mote cache.
		for (var r in relations) {
			r.fillReferences();
		}
	}

}