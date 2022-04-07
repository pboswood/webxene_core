import 'dart:typed_data';
import 'dart:convert';
import 'dart:collection';
import 'package:tuple/tuple.dart';
import 'package:webcrypto/webcrypto.dart';
import "constants.dart";
import "../users/user.dart";

mixin MoteCrypto {
	// Decrypt an encrypted payload in JSON format, given our own User and a known dockey obtained via TODO: ....
	// Returns a decoded JSON map representing our payload, or throws an exception.
	Future<Map<String, dynamic>> decryptMotePayload(User cryptoUser, String dockeyB64, String payloadJSON) async {
		if (cryptoUser.cryptoKeys.encryptPrivate == null) {
			throw Exception("Decrypt operation is missing private encryption key");
		}

		// Use JWK keys from cryptoUser to decrypt the mote dockey, and load as AES key.
		final dockeyCiphertext = base64Decode(dockeyB64);
		final dockeyPlaintext = await cryptoUser.cryptoKeys.encryptPrivate!.decryptBytes(dockeyCiphertext);
		// Actual plaintext above consists of AES key followed by HMAC key.
		final moteDockey = await AesCbcSecretKey.importRawKey(dockeyPlaintext.sublist(0, CRYPTO_AES_LENGTH ~/ 8));
		final moteDockeyHMAC = dockeyPlaintext.sublist(CRYPTO_AES_LENGTH ~/ 8);

		// Use mote dockey to AES decrypt payload, and check HMAC. The 'aesEncrypted' entry below stores an IV first before the actual AES payload.
		final motePayloadObj = jsonDecode(payloadJSON);
		final motePayloadAES = base64Decode(motePayloadObj['aesEncrypted']);
		final motePayloadHMAC = await HmacSecretKey.importRawKey(moteDockeyHMAC, Hash.sha1);
		final motePayloadHMACGood = await motePayloadHMAC.verifyBytes(base64Decode(motePayloadObj['hmac']), motePayloadAES);
		if (!motePayloadHMACGood) {
			throw Exception("Mote payload HMAC not valid");
		}

		final motePayloadPlaintext = await moteDockey.decryptBytes(motePayloadAES.sublist(CRYPTO_IV_LENGTH), motePayloadAES.sublist(0, CRYPTO_IV_LENGTH));
		return jsonDecode(Utf8Decoder().convert(motePayloadPlaintext));
	}

	// Encrypts a payload JSON string, given ourself and a list of users to target which should include ourselves.
	// All public keys required should be fetched already via TODO: ...
	// Returns a Tuple of the encrypted string payload, and dockeys Map.
	Future<Tuple2<String, HashMap<int, String>>> encryptMotePayload(User cryptoUser, List<User> cryptoTargets, String payloadJSON) async {
		// Take the JSON payload and encrypt it using AES, and generating the dockey.
		final payloadCleartext = Utf8Encoder().convert(payloadJSON);
		final moteDockey = await AesCbcSecretKey.generateKey(CRYPTO_AES_LENGTH);
		final payloadIV = Uint8List(CRYPTO_IV_LENGTH);
		fillRandomBytes(payloadIV);
		final payloadCiphertext = await moteDockey.encryptBytes(payloadCleartext, payloadIV);

		// Generate HMAC key + signature, encode into stored payload object.
		final moteDockeyHMAC = await HmacSecretKey.generateKey(Hash.sha1, length: 160);
		final payloadAES = payloadIV + payloadCiphertext;       // Combined into single IV+Ciphertext to be stored.
		final payloadStored = {
			'aesEncrypted': base64Encode(payloadAES),
			'hmac': base64Encode(await moteDockeyHMAC.signBytes(payloadAES)),
		};
		final payloadStoredJSON = jsonEncode(payloadStored);

		// Encode the mote dockey into a form consisting of AES key + HMAC key.
		final moteDockeyStored = (await moteDockey.exportRawKey()) + (await moteDockeyHMAC.exportRawKey());
		// Take this dockey and RSA encrypt it for each crypto-target user.
		final allDockeys = HashMap<int, String>();
		for (var targetUser in cryptoTargets) {
			if (targetUser.cryptoKeys.encryptPublic == null) {
				allDockeys[targetUser.id] = "";
				continue;
			}
			allDockeys[targetUser.id] = base64Encode(await targetUser.cryptoKeys.encryptPublic!.encryptBytes(moteDockeyStored));
		}
		return Tuple2(payloadStoredJSON, allDockeys);
		/* (multi-threaded implementation?)
		var allDockeys = await Future.wait(cryptoTargets.map((targetUser) async {
			if (targetUser.cryptoKeys.encryptPublic == null) {
				return null;
			}
			return base64Encode(await targetUser.cryptoKeys.encryptPublic!.encryptBytes(moteDockeyStored));
		}).toList());
		*/
	}

}