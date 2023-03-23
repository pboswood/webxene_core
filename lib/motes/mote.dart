import "dart:collection";
import 'dart:convert';
import 'package:tuple/tuple.dart';
import '../group_manager.dart';
import '../groups/group.dart';
import '../mote_manager.dart';
import '../instance_manager.dart';
import '../auth_manager.dart';
import '../user_manager.dart';
import "mote_comment.dart";
import '../crypto/mote_crypto.dart';
import 'mote_relation.dart';
import "schema.dart";
import "../users/user.dart";
import "../groups/page.dart";
import "attachment.dart";

class Mote with MoteCrypto {
	int id = 0;
	Map<String, dynamic> payload = {};
	Queue<MoteComment> comments = Queue();
	List<MoteRelation> relationships = [];      // (stores all relationships involving this mote, including reverse relationships)
	List<Attachment> attachments = [];          // (stores all attachments/metadata AFTER decrypting - although bytes are not retrieved without requesting)
	int typeId = 0;                 // Schema type ID
	int seqId = 0;                  // Version sequence ID, incremented by one each update.
	String dockey = "";             // Dockey for ourselves as B64 (we don't store generated dockeys for others)
	String payloadEncrypted = "";   // Encrypted payload as String JSON.
	int timestamp = 0;              // UNIX timestamp of the mote creation date.

	// Dockeys and new encrypted payload, to be used when creating updates or creations.
	Tuple2<String, HashMap<int, String>>? encryptedCommit;

	// Targeting for motes
	int sourceId = 0;               // Source user this mote is from
	int targetId = 0;               // Destination user/group
	bool groupType = false;         // If destination is a group
	int domainId = 0;               // Conversation ID or page ID if groupType.
	int folderId = 0;               // Folder for drive motes, 0 indicates root folder.

	// Internal parent relationships for new motes only - used only to store details, do not apply as relationships data.
	String? _parentRelationKey;     // Relationship field name on parent mote (or '_${ourMoteType}' for auto-detection)
	int? _parentRelationId;         // Mote ID of our parent mote.

	bool get isUnsaved => id == 0;
	dynamic get parentRelationAsPostArray => _parentRelationKey == null ? [] : [ _parentRelationKey, _parentRelationId.toString() ];
	int get parentRelationAsMoteId => _parentRelationKey != null && _parentRelationId != null ? _parentRelationId! : 0;

	Mote();         // Empty constructor can use default id=0 to initialize new motes, but we recommend using the .fromBlank constructor for 'new' motes.

	// Construct a loaded yet still encrypted mote from JSON input.
	Mote.fromEncryptedJson(Map<String, dynamic> json, { String? overrideDockey }) {
		id = json['id'];
		typeId = (json['type_id'] is String ? int.parse(json['type_id']) : json['type_id']) ?? 0;
		seqId = json['seq_id'] ?? 0;
		payloadEncrypted = json['payload'];
		dockey = overrideDockey == null ? json['dockey'] : overrideDockey;
		sourceId = json['source_id'] ?? 0;
		targetId = json['target_id'] ?? 0;
		groupType = (json['group_type'] ?? 0) == 0 ? false : true;
		domainId = json['domain_id'] ?? 0;
		folderId = json['folder_id'] ?? 0;
		timestamp = json['timestamp'] ?? 0;
		encryptedCommit = null;
		relationships = json['relationships'] == null ? [] :
			(json['relationships'] as List).map((r) => MoteRelation.fromMoteJson(r, this)).toList();
		// Motes may also contain internal attribution info if from specific sources,
		// we can automatically cache these details if we get them.
		if (json['attrib'] != null && json['attrib'] is Map) {
			UserManager().autoloadAttributionMap(json['attrib'] as Map<String, dynamic>);
		}
	}

	// Construct a mote from scratch (as a 'blank' mote ready to be saved by MoteManager().saveMote).
	// The typeId can be determined by calling InstanceManager().schemaByType after login.
	// The 'parent' should be the mote we are creating this in, e.g. the subview, or null for root level motes.
	// Note: this constructor is ONLY for group motes, not conversational motes.
	Mote.fromBlank({
		required Schema schema, required Group group, required Page page, required User author,
		Mote? parent, String? title, Mote? driveFolder
	}) {
		typeId = schema.id;
		schema.setMoteDefaults(this, title: title);
		// Targeting setup for group-type motes: group_type = 1, source = author, target = group, domain = page, folder = 0/drive_folder
		sourceId = author.id;
		targetId = group.id;
		groupType = true;
		domainId = page.id;
		folderId = driveFolder == null ? 0 : driveFolder.id;
		// Parent relationship setup for blank motes only - the parent must be saved first, or relationship storage will fail.
		if (parent != null) {
			if (parent.isUnsaved) {
				throw "Parent mote specified in Mote.fromBlank constructor is unsaved and cannot be used";
			}
			_parentRelationKey = '_' + schema.type;
			_parentRelationId = parent.id;
		}
	}

	// Decrypt a mote from the encrypted values loaded by our constructor, as the current user.
	Future<void> decryptMote() async {
		try {
			payload = await decryptMotePayload(AuthManager().loggedInUser, dockey, payloadEncrypted);
			normalizeRelationships();
			parseAttachments();
			// TODO: Deal with comments, relationships
		} catch(ex) {
			rethrow;
		}
	}

	// Encrypt a mote from the decrypted values, replacing the encrypted ones with them.
	Future<void> encryptMote() async {
		// TODO: Implement non-group encryption.
		if (!groupType) {
			throw "Unimplemented: non-group encryption operations!";
		}
		try {
			// TODO: Deal with sub-group target lists and non-group targets.
			var groupObj = await GroupManager().fetchGroup(targetId);
			if (groupObj.memberKeys == null) {
				await groupObj.FetchMemberKeys();
			}
			var jsonPayload = jsonEncode(separateRelationships());
			encryptedCommit = await encryptMotePayload(AuthManager().loggedInUser, groupObj.memberKeys!, jsonPayload);
			print("Encrypted commit package generated OK for mote #${this.id}");
		} catch(ex) {
			rethrow;
		}
	}

	// Helper function to get string representations of a mote's headers + payload CSV for UI.
	static Tuple2<String, List<String>> interpretMotesCSV(List<Mote> motes) {
		if (motes.length == 0) {
			return Tuple2('', []);
		}
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

	// Separate and remove relations from payload, doing the opposite of normalizeRelationships() since relational
	// data cannot be upload as part of the encrypted payload JSON. This returns a clone of the payload to be saved
	// in JSON format, since we don't want to change the actual original payload here.
	Map<String, dynamic> separateRelationships() {
		// TODO: Deal with complex objects!
		Map<String, dynamic> clonePayload = {};
		for (var k in payload.keys) {
			if (payload[k] is! List<MoteRelation>) {
				clonePayload[k] = payload[k];
			}
		}
		return clonePayload;
	}

	// Parse JSON 'attached' array in payload for attachments and hydrate our attachments list.
	parseAttachments() {
		if (!payload.containsKey('attached')) {
			return;
		}
		var payloadAttached = (payload['attached'] as List);
		for (var attached in payloadAttached) {
			attachments.add(Attachment.fromMotePayload(attached));
		}
	}

	// Do the reverse of parseAttachments - convert attachment objects back into JSON for our payload.
	generateAttachments() {
		if (attachments.isEmpty) {
			// For 0 attachments, set it to an empty array only if it used to have some.
			if (payload.containsKey('attached')) {
				payload['attached'] = [];
			}
			return;
		}
		// Otherwise, for 1+ attachments just populate it with our JSON.
		payload['attached'] = attachments.map((a) => a.toPayloadJSON()).toList();
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