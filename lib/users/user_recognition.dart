
// A user recognition object is a 'partial' user returned from login lookup API.
// This may or may not be a real user, but specifies the login criteria needed,
// such as 2FA, recognition code to show user, user 'id', etc.

class UserRecognition {
	int id = 0;                 // ID of user that will be fetched on login.
	String recognition = '';    // Recognition code to 'describe' this user. Usually email if user has access to see it.
	bool passwordEmpty = false; // If the password is empty for this user, and must be setup before login.
	bool totpEnabled = false;   // If 2FA is required to process a login.

	UserRecognition.fromJson(Map<String, dynamic> json) {
		json['password_empty'] ??= 0;
		json['totp_enabled'] ??= 0;

		id = json['id'];
		recognition = json['recognition'];
		passwordEmpty = json['password_empty'] == 0 ? false : true;
		totpEnabled = json['totp_enabled'] == 0 ? false : true;
	}

}
