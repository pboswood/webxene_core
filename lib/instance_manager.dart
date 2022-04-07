// Singleton class to store instance and configuration details.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'motes/schema.dart';

class InstanceManager {
	static InstanceManager? _instance;
	factory InstanceManager() => _instance ??= new InstanceManager._singleton();
	InstanceManager._singleton();       // Empty singleton constructor

	String _instanceHost = "";          // Hostname of our API server.
	final Map<String, dynamic> _instanceConfig = {};
	final Map<int, Schema> _schemasById = {};
	final Map<String, Schema> _schemasByType = {};

	// Setup instance manager with configuration details. Called after instance
	// data is retrieved by login/username exchange or keypair checks.
	void setupInstance(String? instanceHostname, Map<String, dynamic>? instanceConfig) {
		if (instanceHostname != null) {
			_instanceHost = instanceHostname;
		}
		if (instanceConfig != null) {
			if (instanceConfig.containsKey('instance')) {
				(instanceConfig['instance'] as Map<String, dynamic>).forEach((key, value) {
					_instanceConfig[key] = value;
				});
			}
			if (instanceConfig.containsKey('schemas')) {
				hydrateSchemas(instanceConfig['schemas']!);
				print("Loaded ${_schemasById.length} schemas from instance config.");
			}
			// TODO: Implement actions hydration
		}
	}

	// Get API path as URI for a client connection, for example:
	// "user/1/login" => "https://subdomain.server.com/api/user/1/login"
	// Note that common headers for auth/accept must be used - use apiRequest() instead to make a full API call!
	Uri apiPath(String route, [Map<String, dynamic>? parameters, String method = 'GET' ]) {
		if (_instanceHost == "") {          // setupInstance MUST be called first!
			throw Exception("Instance manager has no host setup!");
		}
		final bool useUnsecure = _instanceConfig['DEBUG_HTTP'] ?? false;
		print("API request: " + (useUnsecure ? "Using HTTP" : "Using HTTPS"));
		return Uri(
			scheme: useUnsecure ? 'http' : 'https',
			host: _instanceHost,
			path: 'api/' + (route.substring(0, 1) == '/' ? route.substring(1) : route),
			queryParameters:  parameters,
		);
	}

	// Make an async API request to an endpoint along with any authorization required.
	// Returns an APIResponse containing the original HTTP request as well as JSON result.
	// Note: the parameters, if a list, must be a String subclass, i.e. List<int> will NOT work!
	Future<APIResponse> apiRequest(String route, [Map<String, dynamic>? parameters, String method = 'GET']) {
		method = method.toUpperCase().trim();
		if (method != 'GET') {
			parameters ??= {};
			parameters.putIfAbsent('_method', () => method);        // Add laravel-specific _method handling for PUT/etc. to simulate HTTP forms.
		}
		final reqPath = InstanceManager().apiPath(route, parameters, method);
		final reqHeaders = {
			'Accept': 'application/json',
			'Authorization': 'Bearer ' + 'alice-----',
		};
		final reqHttp = method == 'GET' ?
			http.get(reqPath, headers: reqHeaders) :
			http.post(reqPath, headers: reqHeaders, body: (parameters is String ? parameters : jsonEncode(parameters)));
		return reqHttp.then((response) => APIResponse(response));
	}

	// Make an async request to an enclave endpoint via our API, used for key backup/recovery operations.
	// Returns the raw HTTP response, as this may or may not be JSON data.
	Future<http.Response> enclaveRequestRaw(String route, [Map<String, dynamic>? parameters]) {
		print(parameters);
		// TODO: How can we define our enclave URI? We don't pass this is any way normally via instance config!
		const String enclaveRoot = 'netxene-enclave.cirii.org';
		final bool useUnsecure = _instanceConfig['DEBUG_HTTP'] ?? false;
		print("Enclave request: " + (useUnsecure ? "Using HTTP" : "Using HTTPS"));
		final enclaveUri = Uri(
			scheme: useUnsecure ? 'http' : 'https',
			host: enclaveRoot,
			path: (route.substring(0, 1) == '/' ? route.substring(1) : route),
			queryParameters:  null,
		);
		// All enclave requests are POST requests.
		final enclaveRequest = http.post(enclaveUri,
			headers: {},
			body: jsonEncode(parameters),       // Our scripts require JSON input at the moment
		);
		return enclaveRequest;
	}

	// Fetch common environmental variables used in instance configuration.
	String get defaultSecurecode => _instanceConfig['defaultSecurecode'] ?? '';

	// Get a schema type by ID or type string, after instance initialization.
	schemaById(int id) => _schemasById.containsKey(id) ? _schemasById[id] : throw Exception("Failed to load schema #$id");
	schemaByType(String type) => _schemasByType.containsKey(type) ? _schemasByType[type] : throw Exception("Failed to load schema '$type'");

	// Create our schema objects from a JSON list and assign them to our lookup maps.
	hydrateSchemas(List<dynamic> schemas) {
		for (var schema in schemas.map((s) => Schema.fromJson(s))) {
			_schemasById[schema.id] = schema;
			_schemasByType[schema.type] = schema;
		}
	}
}

enum APIResponseJSON {
	failed,         // Failed to decode the JSON result
	list,           // JSON returned a List<dynamic>
	map,            // JSON returned a Map<String, dynamic>
	unknown,        // JSON returned something else (raw variable?)
}

class APIResponse {
	late http.Response response;
	late dynamic result;        // JSON could be List<dynamic>, Map<String, dynamic>, etc.
	APIResponseJSON resultType = APIResponseJSON.failed;

	APIResponse(http.Response httpResponse) {
		response = httpResponse;
		try {
			result = jsonDecode(response.body);
			if (result is List) {
				resultType = APIResponseJSON.list;
			} else if (result is Map) {
				resultType = APIResponseJSON.map;
			} else {
				resultType = APIResponseJSON.unknown;
			}
		} catch (ex) {
			resultType = APIResponseJSON.failed;
		}
	}

	// Return if this is a success or not. If we require a specific type or JSON (list/map),
	// we can pass this in to check here as well.
	bool success([APIResponseJSON? requiredType]) {
		return response.statusCode == 200 && resultType != APIResponseJSON.failed &&
				(requiredType == null || requiredType == resultType);
	}
}