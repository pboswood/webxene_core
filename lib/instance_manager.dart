// Singleton class to store instance and configuration details.
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:webxene_core/auth_manager.dart';
import 'motes/attachment.dart';
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
		print("API Request [" + (useUnsecure ? 'HTTP' : 'HTTPS') + "] " + route);
		return Uri(
			scheme: useUnsecure ? 'http' : 'https',
			host: _instanceHost,
			path: 'api/' + (route.substring(0, 1) == '/' ? route.substring(1) : route),
			queryParameters:  method != 'GET' ? {} : parameters,
		);
	}

	// Make an async API request to an endpoint along with any authorization required.
	// Returns an APIResponse containing the original HTTP request as well as JSON result.
	// Note: the parameters, if a list, must be a String subclass, i.e. List<int> will NOT work!
	// Note: as a general rule, in GET requests arrays must be 'field[]', while in POST bodies just 'field' will work since these are JSON transmitted.
	Future<APIResponse> apiRequest(String route, [Map<String, dynamic>? parameters, String method = 'GET', Map<String, Attachment>? multipartFiles ]) {
		method = method.toUpperCase().trim();
		if (method != 'POST' && multipartFiles != null) {
			throw Exception("Invalid file-upload request with non-POST apiRequest");
		}
		if (method != 'GET') {
			parameters ??= {};
			parameters.putIfAbsent('_method', () => method);        // Add laravel-specific _method handling for PUT/etc. to simulate HTTP forms.
		}
		final reqPath = InstanceManager().apiPath(route, parameters, method);
		final reqHeaders = {
			...AuthManager().authTokenHeaders,
			'Accept': 'application/json',
			'Content-Type': 'application/json'
		};
		if (multipartFiles != null && method == 'POST') {
			reqHeaders.remove('Content-Type');      // Won't work with a multipart, obviously.
			final reqHttpMultipart = http.MultipartRequest(method, reqPath);
			reqHttpMultipart.headers.addAll(reqHeaders);
			for (MapEntry filePairs in multipartFiles!.entries) {
				var attachment = filePairs.value as Attachment;
				if (attachment.encryptedBytes == null) {
					continue;
				}
				reqHttpMultipart.files.add(http.MultipartFile.fromBytes(filePairs.key, attachment.encryptedBytes!,
					filename: attachment.filename, contentType: http_parser.MediaType.parse(attachment.mime)
				));
			}
			for (MapEntry paramPairs in parameters!.entries) {
				reqHttpMultipart.fields[paramPairs.key] = paramPairs.value as String;       // TODO: What about not being able to cast?
			}
			var multipartRequest = reqHttpMultipart.send();
			return apiMultipartExecute(multipartRequest);
		}
		final reqHttp = method == 'GET' ?
			http.get(reqPath, headers: reqHeaders) :
			http.post(reqPath, headers: reqHeaders, body: (parameters is String ? parameters : jsonEncode(parameters)));
		return reqHttp.then((response) => APIResponse(response));
	}

	Future<APIResponse> apiMultipartExecute(Future<http.StreamedResponse> streamedResponse) async {
		var responseStream = await streamedResponse;
		var responseObj = await http.Response.fromStream(responseStream);
		return APIResponse(responseObj);
	}

	// Make an async request to an enclave endpoint via our API, used for key backup/recovery operations.
	// Returns the raw HTTP response, as this may or may not be JSON data.
	Future<http.Response> enclaveRequestRaw(String route, [Map<String, dynamic>? parameters]) {
		// TODO: How can we define our enclave URI? We don't pass this is any way normally via instance config!
		var enclaveRoot = "";
		var enclavePath = route.substring(0, 1) == '/' ? route.substring(1) : route;
		switch(_instanceHost) {
			case 'netxene.cirii.org':
				enclaveRoot = 'netxene-enclave.cirii.org';
				break;
			case 'crm.sevconcept.ch':
			case 'demo.xemino.ch':
				enclaveRoot = _instanceHost;
				enclavePath = 'enclave/' + enclavePath;
				break;
			default:
				throw Exception("Undefined enclave for hostname '${_instanceHost}; pre-defined settings are required for now!");
		}

		final bool useUnsecure = _instanceConfig['DEBUG_HTTP'] ?? false;
		print("Enclave Request [" + (useUnsecure ? 'HTTP' : 'HTTPS') + "] " + route);
		final enclaveUri = Uri(
			scheme: useUnsecure ? 'http' : 'https',
			host: enclaveRoot,
			path: enclavePath,
			queryParameters:  null,
		);
		// All enclave requests are POST requests.
		final enclaveRequest = http.post(enclaveUri,
			headers: {},
			body: jsonEncode(parameters),       // Our scripts require JSON input at the moment
		);
		return enclaveRequest;
	}

	// Make an async request to our storage to fetch an attachment 'asset' as encrypted bytes.
	// Returns the raw HTTP response. The remoteURL MUST start with '/storage/' or 'storage/' to be valid!
	Future<http.Response> assetRequestRaw(String remoteUrl) {
		if (_instanceHost == "") {          // setupInstance MUST be called first!
			throw Exception("Instance manager has no host setup!");
		}
		if (remoteUrl.startsWith('/')) {
			remoteUrl = remoteUrl.substring(1);
		}
		if (!remoteUrl.startsWith('storage/')) {
			throw Exception("Invalid asset URL passed to request - must start with storage root");
		}
		final bool useUnsecure = _instanceConfig['DEBUG_HTTP'] ?? false;
		final assetPath = Uri(
			scheme: useUnsecure ? 'http' : 'https',
			host: _instanceHost,
			path: remoteUrl,
		);
		final assetHeaders = {
			...AuthManager().authTokenHeaders,
		};
		final assetHttp = http.get(assetPath, headers: assetHeaders);
		return assetHttp;
	}

	// Fetch common environmental variables used in instance configuration.
	String get defaultSecurecode => _instanceConfig['defaultSecurecode'] ?? '';

	// Get a schema type by ID or type string, after instance initialization.
	Schema schemaById(int id) => _schemasById.containsKey(id) ? _schemasById[id] as Schema : throw Exception("Failed to load schema '$id'");
	Schema schemaByType(String type) => _schemasByType.containsKey(type) ? _schemasByType[type] as Schema : throw Exception("Failed to load schema '$type'");

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