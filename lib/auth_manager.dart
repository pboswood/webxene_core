// Singleton class to store authentication details for current user.
import 'dart:convert';
import 'package:tuple/tuple.dart';
import 'users/user.dart';
import "instance_manager.dart";
import 'users/user_recognition.dart';

// TODO: Move these to separate classes
class NotFoundException implements Exception {
}
enum UserKeypairType {
	public,
	temp,
	invalid
}
class UserKeypair {                 // NB: These represent only the PUBLIC part of keypairs (encryption+signing) as stored in API backend.
	int id = 0;                     // Keypair ID, as reported by server - not the same as user ID!
	int timestamp = 0;              // UNIX timestamp of key creation.
	UserKeypairType type = UserKeypairType.invalid;     // Type of this keypair as reported by server. See backend Keypair model for more information.

	UserKeypair.fromJson(Map<String, dynamic> json, { bool enforceSentinel = false, bool enforceValid = false }) {
		id = json['id'];
		timestamp = json['timestamp'];
		type = UserKeypairType.values.byName(json['type']);     // (throws error if this enum type is not found!)

		if (enforceSentinel) {      // Enforce sentinel value - timestamp of request must be within one hour.
			final int sentinel = json['sentinel'] ?? 0;
			final int sentinelDiff = (sentinel - (DateTime.now().millisecondsSinceEpoch / 1000).round()).abs();
			if (sentinelDiff > (60*60)) {
				throw Exception("Invalid sentinel value for keypair: exceeds $sentinelDiff seconds!");
			}
		}

		if (enforceValid) {         // Enforce validity flag - require a 'valid' flag on this keypair meaning it is the most recent valid keypair.
			if (!(json['valid'] ?? false)) {
				throw Exception("Keypair validity flag is not set for keypair $id, aborting!");
			}
		}
	}
}


enum AuthState {
	init,               // Startup - request for login name or identifier.
	password,           // Login request for password only.
	passwordTOTP,       // Login request for password + 2FA.
	forgot,             // Forgot password request.
	keyPrompt,          // Prompt for key entry
	complete,           // Logged in and authenticated.
	error,              // Error message display.
}
class AuthManager {
	static AuthManager? _instance;
	factory AuthManager() => _instance ??= new AuthManager._singleton();
	AuthManager._singleton();       // Empty singleton constructor

	UserRecognition? _recognition;          // Recognition object used as part of login to describe partial user details.
	AuthState state = AuthState.init;       // State the Auth Manager is in, used to render UI or check logged-in status.
	User loggedInUser = User();             // Last user we logged in as successfully, or empty user.

	String _apiToken = '';                  // API token for this login session.
	Map<String, String> get authTokenHeaders => _apiToken == '' ? {} : { 'Authorization': 'Bearer ' + _apiToken };

	// Temporary login sequence that bypasses AuthState to do everything in one step.
	// TODO: Fix this to use separate pages, as required by 2FA/TOTP and other uses.
	Future<void> runSingleStageLogin(String username, String password) async {
		try {
			// Lookup recognition for this username to get uid, etc.
			await lookupLoginDetails(username);
			if (_recognition == null) {
				throw Exception("Failed to recognize user!");
			} else if (_recognition!.passwordEmpty) {
				throw UnimplementedError("Can't login to uninitialized user accounts yet!");
			} else if (_recognition!.totpEnabled) {
				throw UnimplementedError("Can't login to 2FA-enabled user accounts yet!");
			}

			// Exchange password for API token and user details.
			final loginResults = await attemptLoginTokenExchange(_recognition!.id, password);
			loggedInUser = loginResults.item1;
			_apiToken = loginResults.item2;
			print("Login token exchange complete: " + loggedInUser.name);

			// Get keypair for logged in user to obtain instance details.
			final keypairRemoteFetch = await getLoggedInKeypair(getInstanceInitializer: true);
			final keypairRemote = keypairRemoteFetch.item1;
			final instanceConfig = keypairRemoteFetch.item2;
			InstanceManager().setupInstance(null, instanceConfig);
			print("Remote keypair identified: id ${keypairRemote.id} is valid.");
			final keypairRecovered = await attemptKeyRecovery(keypairRemote, loggedInUser);

			// Attempt to unlock keypair with securecode to unlock UserCrypto operations.
			// TODO: Implement proper securecode lookup for non-defaults!
			await loggedInUser.DecryptSecurekey(InstanceManager().defaultSecurecode, keypairRecovered['pbkdf2_iter'], keypairRecovered['pbkdf2_salt'], keypairRecovered['aesEncrypted'], keypairRecovered['hmac']);
			print("Unlocked remote keypair successfully with securecode. Crypto operations now live for user ${loggedInUser.id}.");
			state = AuthState.complete;
		} on NotFoundException {
			rethrow;
		} catch (ex) {
			rethrow;
		}
	}

	// Lookup a username or contact to obtain details required for login, including 2FA status, recognition, etc.
	Future<void> lookupLoginDetails(String username) async {
		final apiResolveUser = await InstanceManager().apiRequest('users', { 'lookup': username });
		if (!apiResolveUser.success(APIResponseJSON.map)) {
			throw apiResolveUser.response.statusCode == 404 ?
				NotFoundException() :
				Exception("${apiResolveUser.response.statusCode}: ${apiResolveUser.response.reasonPhrase ?? 'Unknown error'}");
		}
		_recognition = UserRecognition.fromJson(apiResolveUser.result);
	}

	// Attempt login user and token exchange for password.
	Future<Tuple2<User, String>> attemptLoginTokenExchange(int uid, String password) async {
		final apiLogin = await InstanceManager().apiRequest("users/$uid/login", {
			'password': password,
			'totp_auth': null,
		}, 'POST');
		if (!apiLogin.success(APIResponseJSON.map)) {
			throw apiLogin.response.statusCode == 404 ?
				NotFoundException() :
				Exception("${apiLogin.response.statusCode}: ${apiLogin.response.reasonPhrase ?? 'Unknown error'}");
		}
		// Make sure api_token does not remain in the user JSON.
		final userApiToken = apiLogin.result['api_token'];
		apiLogin.result['api_token'] = '';
		return Tuple2(User.fromJson(apiLogin.result), userApiToken);
	}

	// Get our current keypair for the logged in user, along with login instance configuration, etc. if required.
	Future<Tuple2<UserKeypair, Map<String, dynamic>?>> getLoggedInKeypair({ bool getInstanceInitializer = false }) async {
		final apiKeypair = await InstanceManager().apiRequest('keypairs', {
			'fetch_only': getInstanceInitializer ? '0' : '1',
		});
		if (!apiKeypair.success(APIResponseJSON.map)) {
			throw Exception("${apiKeypair.response.statusCode}: ${apiKeypair.response.reasonPhrase ?? 'Unknown error'}");
		}
		final keypair = UserKeypair.fromJson(apiKeypair.result, enforceSentinel: true, enforceValid: true);
		if (!getInstanceInitializer) {
			return Tuple2(keypair, null);
		}
		// Separate instance configuration from keypair details and return them separately.
		final instanceConfig = {
			'actions': apiKeypair.result['actions'],
			'schemas': apiKeypair.result['schemas'],
			'instance': apiKeypair.result['instance'],
		};
		return Tuple2(keypair, instanceConfig);
	}

	// Attempt to recover keypair from server via recovery, returning JSON map of encrypted key (unlocked by passphrase).
	Future<Map<String, dynamic>> attemptKeyRecovery(UserKeypair keypair, User user) async {
		final apiRecoveryCode = await InstanceManager().apiRequest("keypairs/${keypair.id}/recover", null, 'POST');
		if (!apiRecoveryCode.success(APIResponseJSON.map)) {
			throw Exception("Failed to generate recovery code for user keypair ${keypair.id} -- "
				"${apiRecoveryCode.response.statusCode}: ${apiRecoveryCode.response.reasonPhrase ?? 'Unknown error'}");
		}
		// TODO: Work with non-default securecode!
		final backupHash = await user.GenerateSecureBackupHash(user.id, keypair.id, apiRecoveryCode.result['recover']['salt'], InstanceManager().defaultSecurecode);
		final backupFetch = await InstanceManager().enclaveRequestRaw('load.php', {
			'signature': apiRecoveryCode.result['recover']['signature'],
			'api_message': apiRecoveryCode.result['recover']['message'],
			'filename': backupHash,
		});

		if (backupFetch.statusCode == 200) {
			return jsonDecode(backupFetch.body);
		} else {
			throw Exception("Failed to fetch recovery key from secure enclave: ${backupFetch.statusCode}: ${backupFetch.reasonPhrase ?? 'Unknown error'}");
		}
	}

	// Attempt to do a full login with lookup, keypair and api token retrieval.
	/* TODO: Restore this once we have AuthState working!
		Future<bool> attemptUsernameLogin(LoginScreenController parent, String username, String password) async {
			if (state != AuthState.init) {
				throw Exception("Invalid authmanager state for login lookup!");
			}
			parent.busy();

			try {
				final usernameRequest = await InstanceManager().apiRequest('users', { 'lookup': username });
				if (!usernameRequest.success(APIResponseJSON.map)) {
					if (usernameRequest.response.statusCode == 404) {
						parent.showError("Login username was not found.");
					} else {
						parent.showError(usernameRequest.response.statusCode.toString() + ": " + (usernameRequest.response.reasonPhrase ?? "Unknown error"));
					}
					parent.finished();
					return false;
				}
				_loginTOTP = usernameRequest.result['totp_enabled'] == 1;
				_loginRecognition = usernameRequest.result['recognition'];
				state = AuthState.keyPrompt;
				final apiKeypair = await InstanceManager().apiRequest('keypairs');
				print(apiKeypair.result);
				parent.mirrorState(state);
				parent.finished();
				return true;
			} catch (ex) {
				parent.showError("Error looking up this login username!");
				parent.finished();
				rethrow;
			}
		}
		 */

}