import 'dart:ffi';
import 'dart:typed_data';
import 'dart:convert';
import 'package:tuple/tuple.dart';
import 'package:webcrypto/webcrypto.dart';
import "constants.dart";

mixin AttachCrypto {
	// Generate a random filekey used for attachments, consisting of 10 hex characters from a crypto-secure source.
	String generateRandomFilekey() {
		final keyBytes = Uint8List(5);
		fillRandomBytes(keyBytes);
		return keyBytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).toList().join("");
	}

	// Decrypt an encrypted byte array given our encryption key that was stored in a secured mote payload.
	Future<Uint8List> decryptAttachment(Uint8List ciphertext, String aes_b64, String hmac_b64) async {
		// Convert base64 AES keys and HMAC into byte arrays.
		final aesKey = base64Decode(aes_b64);
		final hmacKey = base64Decode(hmac_b64);

		final unpacked = decodePackedCrypto(ciphertext);
		if (!(unpacked.containsKey('hmac') && unpacked.containsKey('aesEncrypted'))) {
			throw Exception("Invalid packed attachment data");
		}

		final attachmentHMAC = await HmacSecretKey.importRawKey(hmacKey, Hash.sha1);
		final attachmentHMACGood = await attachmentHMAC.verifyBytes(unpacked['hmac'], unpacked['aesEncrypted']);
		if (!attachmentHMACGood) {
			throw Exception("Attachment HMAC not valid");
		}

		final aesKeyObj = await AesCbcSecretKey.importRawKey(aesKey);
		final attachmentPlain = await aesKeyObj.decryptBytes(unpacked['aesEncrypted'].sublist(CRYPTO_IV_LENGTH), unpacked['aesEncrypted'].sublist(0, CRYPTO_IV_LENGTH));
		return attachmentPlain;
	}

	// Encrypt an attachment file bytes, giving us AES/HMAC keys in base64, plus ciphertext bytes.
	Future<Tuple3<String, String, Uint8List>> encryptAttachment(Uint8List plainfile) async {
		// Generate an AES key and IV, using it to encrypt our plain file bytes.
		final aesKey = await AesCbcSecretKey.generateKey(CRYPTO_AES_LENGTH);
		final aesIV = Uint8List(CRYPTO_IV_LENGTH);
		fillRandomBytes(aesIV);
		final ciphertext = await aesKey.encryptBytes(plainfile, aesIV);
		// final aesPayload = Uint8List.fromList(aesIV)..addAll(ciphertext);       // Combine into single IV+Ciphertext to be stored.
		final aesPayload = aesIV + ciphertext;

		// Generate a HMAC key and signature.
		final hmacKey = await HmacSecretKey.generateKey(Hash.sha1, length: 160);
		final hmacSign = await hmacKey.signBytes(aesPayload);
		final Map<String, Uint8List> packedStruct = {
			'aesEncrypted': Uint8List.fromList(aesPayload),
			'hmac': hmacSign,
		};

		// Pack and return the structure with our keys separately base64 encoded.
		final packedBytes = encodePackedCrypto(packedStruct);
		return Tuple3(
			base64Encode(await aesKey.exportRawKey()),
			base64Encode(await hmacKey.exportRawKey()),
			packedBytes
		);
	}

	// This is a conversion of simpleCrypto's pack.decode and pack.encode method into Dart.
	static const Map<int, String> packedIndexToLabel = {
		0: "aesEncrypted", 1: "hmac",
		10: "rsaEncrypted",
		20: "signatureOfData", 21: "signatureOfEncrypted",
		30: "pbkdf2_iter", 31: "pbkdf2_salt",
		40: "mimeType"
	};
	static const Map<String, int> packedLabelToIndex = {
		'aesEncrypted': 0, 'hmac': 1,
		'rsaEncrypted': 10,
		'signatureOfData': 20, 'signatureOfEncrypted': 21,
		'pbkdf2_iter': 30, 'pbkdf2_salt': 31,
		'mimeType': 40
	};
	Map<String, dynamic> decodePackedCrypto(Uint8List buffer) {
		Map<String, dynamic> dict = {};
		int offset = 0;
		int version = buffer[offset];
		offset++;
		if (version != 0x1) {
			throw Exception("Unknown version number on packed crypto attachment, aborting decode.");
		}
		while (offset < buffer.length) {
			var index = buffer[offset];
			var label = packedIndexToLabel[index] ?? "unknown";
			var size = buffer.sublist(offset + 1, offset + 1 + 4).buffer.asByteData().getUint32(0, Endian.big);
			if (size > buffer.length - offset + 5) {
				throw Exception("Incorrect size in packed crypto attachment (${size} / ${buffer.length})");
			}
			var data = buffer.sublist(offset + 5, size + offset + 5);
			offset += 5 + data.length;
			dict[label] = data;
		}
		return dict;
	}
	Uint8List encodePackedCrypto(Map<String, Uint8List> dict) {
		int size = 1;
		int numItems = 0;
		for (var label in dict.keys) {
			if (!packedLabelToIndex.containsKey(label)) {
				throw Exception("Unsupported key in packed crypto attachment: ${label}");
			}
			size += 5;      // 1b key, 4b size
			size += dict[label]!.length;
			numItems++;
		}

		var bytes = ByteData(size);
		var offset = 0;
		bytes.setUint8(offset, 0x1);
		offset++;

		for (var label in dict.keys) {
			var index = packedLabelToIndex[label]!;
			bytes.setUint8(offset, index);
			var data = dict[label]!;
			bytes.setUint32(offset + 1, data.lengthInBytes, Endian.big);
			var bytesSub = bytes.buffer.asUint8List(offset + 5, data.lengthInBytes);
			bytesSub.setAll(0, data);
			offset += 5 + data.lengthInBytes;
		}
		return bytes.buffer.asUint8List(0);
	}
}