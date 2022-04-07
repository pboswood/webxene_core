import "dart:collection";
import 'dart:convert';
import '../auth_manager.dart';
import "mote_comment.dart";
import '../crypto/mote_crypto.dart';

class Mote with MoteCrypto {
	int id = 0;
	Map<String, dynamic> payload = {};
	Queue<MoteComment> comments = Queue();
	int typeId = 0;                 // Schema type ID
	int seqId = 0;                  // Version sequence ID, incremented by one each update.
	String dockey = "";             // Dockey for ourselves as B64 (we don't store generated dockeys for others)
	String payloadEncrypted = "";   // Encrypted payload as String JSON.

	// Targeting for motes
	int sourceId = 0;           // Source user this mote is from
	int targetId = 0;           // Destination user/group
	bool groupType = false;     // If destination is a group
	int domainId = 0;           // Conversation ID or page ID if groupType.
	int folderId = 0;           // Folder for drive motes, 0 indicates root folder.

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
	}

	// Decrypt a mote from the encrypted values loaded by our constructor, as the current user.
	Future<void> decryptMote() async {
		try {
			payload = await decryptMotePayload(AuthManager().loggedInUser, dockey, payloadEncrypted);
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

	// Generate string CSV representation of mote payload (headers)?
	// TODO: Where should this be? Ideally we want a schema abstraction, but not all motes MATCH schema!
	String motePayloadHeadersCSV() {
		SplayTreeMap<String, dynamic> orderedPayload = SplayTreeMap.from(payload, (a,b) => a.compareTo(b));
		orderedPayload.removeWhere((key, value) => !(key == 'title' || key.startsWith('cf_')));
		return orderedPayload.keys.join(";");
	}

	// Generate string CSV representation of mote payload.
	String motePayloadCSV() {
		SplayTreeMap<String, dynamic> orderedPayload = SplayTreeMap.from(payload, (a,b) => a.compareTo(b));
		orderedPayload.removeWhere((key, value) => !(key == 'title' || key.startsWith('cf_')));
		return orderedPayload.values.join(";");
	}

}