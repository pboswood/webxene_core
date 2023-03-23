import 'dart:convert';
import 'dart:typed_data';
import 'package:tuple/tuple.dart';
import '../crypto/attach_crypto.dart';
import "../instance_manager.dart";

// Represents an attachment object stored in a mote, saved or not.
class Attachment with AttachCrypto {
	int id = 0;                             // Attachment id, or 0 if unsaved.
	late String filename;                   // Filename of this attachment, e.g. document.txt
	late int filesize;                      // Filesize of bytes of this attachment (server-reported pack-size)
	late String mime;                       // Mimetype of this attachment, e.g. text/plain
	late String url;                        // Partial URL of remote location of this file (e.g. /storage/attachment/...) - MUST start with /
	late String filekey;                    // Random generated keystring for this file (included in url already)
	late Tuple2<String, String> enckey;     // Encryption key for file - consisting of base64 AES-key and HMAC
	late String? metadata;                  // Encrypted metadata (unused - for further expansion)
	Uint8List? byteArray;                   // Byte-array of loaded and decrypted attachment, or null if not fetched.

	List<int>? _encryptedBytes;             // Encrypted bytes used for saving in API requests.
	List<int>? get encryptedBytes => _encryptedBytes;

	bool get isUnsaved => id == 0;
	bool get isLoaded => byteArray != null;

	static List<String> requiredFields = [ 'id', 'filename', 'filesize', 'mime', 'url', 'filekey', 'enckey' ];

	Attachment.fromMotePayload(Map<String, dynamic> attached) {
		for (var key in requiredFields) {
			if (!attached.containsKey(key)) {
				throw "Invalid attachment JSON structure - missing $key";
			}
		}

		id = attached['id'];
		filename = attached['filename'];
		filesize = attached['filesize'] is String ? int.parse(attached['filesize']) : attached['filesize'];
		mime = attached['mime'];
		url = attached['url'];
		filekey = attached['filekey'];
		enckey = Tuple2(attached['enckey'][0], attached['enckey'][1]);

		// Additional validation for URL: no query, no protocols, fixed root.
		if (url.contains('?') || url.contains(':') || url.substring(0, 9) != '/storage/') {
			throw "Invalid attachment JSON structure - invalid URL";
		}
	}

	Attachment.newFromByteArray(this.filename, this.mime, this.byteArray) {
		if (mime == "") {
			mime = "application/octet-stream";
		}
		filesize = byteArray!.length;
		url = "";
		filekey = "";
		enckey = Tuple2("", "");
	}

	Future<void> loadAttachment() async {
		var assetResponse = await InstanceManager().assetRequestRaw(url);
		if (assetResponse.statusCode != 200) {
			throw "Failed to load attachment #${id} from remote server - error ${assetResponse.statusCode} (${assetResponse.reasonPhrase})";
		}
		byteArray = await decryptAttachment(assetResponse.bodyBytes, enckey.item1, enckey.item2);
	}
	
	Future<void> saveAttachmentRemotely() async {
		if (!isLoaded) {
			throw Exception("Attempted to save an attachment with no data.");
		}
		// Generate random cryptographically secure key of 10 hex characters; this is used to ensure people can't easily 'guess' the URL,
		// even if all the data is still encrypted, etc.
		filekey = generateRandomFilekey();

		// Encrypt the attachment bytes, storing to our attachment object.
		var encryptedReturn = await encryptAttachment(byteArray!);
		enckey = Tuple2(encryptedReturn.item1, encryptedReturn.item2);
		_encryptedBytes = encryptedReturn.item3;

		var uploadRequest = await InstanceManager().apiRequest("attachments", {
			'filekey': filekey,
		}, 'POST', { 'file': this });
		if (!uploadRequest.success(APIResponseJSON.map)) {
			throw Exception("${uploadRequest.response.statusCode}: ${uploadRequest.response.reasonPhrase ?? 'Unknown error'}");
		}
		id = uploadRequest.result['id'];
		filename = uploadRequest.result['filename'];
		filesize = uploadRequest.result['filesize'];
		url = uploadRequest.result['url'];
	}

	void clearAttachment() {
		byteArray = null;
	}

	// Convert this attachment object to appropriate payload JSON for the 'attached' array.
	Map<String, dynamic> toPayloadJSON() {
		if (isUnsaved) {
			// If this is unsaved, something has gone wrong and this cannot be written properly to our payload.
			throw Exception("Attempted to commit an unsaved attachment to mote payload for mote #{$id}");
		}
		return {
			'id': id,
			'filename': filename,
			'filesize': filesize,
			'mime': mime,
			'url': url,
			'filekey': filekey,
			'enckey': [ enckey.item1, enckey.item2 ],
		};
	}

}