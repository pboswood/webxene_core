import '../mote_manager.dart';
import '../instance_manager.dart';
import '../user_manager.dart';
import 'field.dart';
import 'mote.dart';

// Represents a relationship between two motes, either saved or not.
class MoteRelation {
	late int sourceId;      // Mote source of relationship, this is where the relation is stored.
	late int targetId;      // Target mote/user this relationship points to.
	late int relationId;    // Relationship unique identifier. May be 0 if unsaved.
	late String fieldType;  // Field name used for this relationship.

	Mote? referencedSource;
	dynamic referencedTarget;       // Usually a Mote? type, but can also be a User? type if isTargetUser is true.
	bool isUserTarget = false;

	MoteRelation.new(this.sourceId, this.targetId, this.fieldType, { bool targetIsUser = false }) {
		relationId = 0;
		isUserTarget = targetIsUser;
	}

	// NB: Mote relationships must be constructed in the last stages of the Mote() constructor,
	// as we rely on ID and type data to setup our relationship items.
	MoteRelation.fromMoteJson(Map<String, dynamic> json, Mote constructingMote) {
		relationId = json['relid'];
		// A field type with a '*' prefix indicates a reversed relationship.
		fieldType = json['field'];
		if (fieldType.substring(0 ,1) == '*') {
			fieldType = fieldType.substring(1);
			sourceId = json['id'];
			targetId = constructingMote.id;
			// Reversed relations can never be a user reference.
			isUserTarget = false;
		} else {
			sourceId = constructingMote.id;
			targetId = json['id'];
			// Query schema-field typing to determine if this is a user reference.
			Field? referenceField = InstanceManager().schemaById(constructingMote.typeId).tryGetField(fieldType);
			if (referenceField == null) {
				print("Warning: skipping reference field initialization due to missing schema entry - mote #$sourceId, field $fieldType");
			} else {
				isUserTarget = referenceField.isUserReference;
			}
		}
	}

	// Returns true if this relationship is a reverse relationship from another mote,
	// relative to a known mote ID.
	bool isReverseRelationship(int moteId) {
		return sourceId != moteId;
	}

	// Return true if this relationship is a relationship to a user, rather than a mote.
	// Because actual target typing is NOT sent in relationship data, we cannot tell
	// the _real_ types of targets until fillReferences() is actually called once.
	bool isTargetUser() {
		return false;
	}

	// Fill relation references from mote cache. Should only be called if we are sure the relation
	// targets and source and already cached, usually from Mote::retrieveReferences().
	void fillReferences() {
		referencedSource ??= MoteManager().getCache(sourceId);
		referencedTarget ??= isUserTarget ? UserManager().getAttribName(targetId) : MoteManager().getCache(targetId);
	}

	// Get the field key (naming convention) expected to be used to represent this inside
	// our payload. Usually this is cf_{fieldname}.
	String relationFieldKey(int moteId) {
		return isReverseRelationship(moteId) ? "cf_*$fieldType" : "cf_$fieldType";
	}

	// Static method to interpret a list of mote relations into a list of either Motes, or Users.
	// The correct method must be called dependant on schema expectation, as incorrect types are silently dropped.
	// If any MoteRelations have not been filled by Mote.retrieveReferences() yet, this will throw an exception.
	// Note: relations is a generic List for easier use in JSON, but expected to be a List<MoteRelation>.
	static List<Mote> asMoteList(List relations, int fromMoteId) {
		final returnList = <Mote>[];
		relations.forEach((rel) {
			var relation = rel as MoteRelation;
			if (relation.isUserTarget) {
				return;
			}
			if (relation.referencedSource == null || relation.referencedTarget == null) {
				throw Exception("Invalid reference #${relation.relationId} from mote #$fromMoteId -- missing reference source/target; make sure retrieveReferences has been called correctly!");
			}
			returnList.add(relation.isReverseRelationship(fromMoteId) ? relation.referencedSource : relation.referencedTarget);
		});
		return returnList;
	}

	static List<String> asUserList(List relations, int fromMoteId) {
		throw UnimplementedError("asUserList not implemented yet - waiting for User return changes!");
	}

}