import '../crypto/user_crypto.dart';

class User with UserCrypto {
	int id = 0;
	String name = '';
	String? email;
	String? phone;

	User();     // Empty user constructor for non-logged in users, id = 0.

	User.fromJson(Map<String, dynamic> json) {
		id = json['id'];
		name = json['name'];
		email = json['email'];
		phone = json['phone'];
	}

}

