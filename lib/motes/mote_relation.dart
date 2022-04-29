
// Represents a relationship between two motes, either saved or not.
class MoteRelation {
	late int sourceId;      // Mote source of relationship, this is where the relation is stored.
	late int targetId;      // Target mote this relationship points to.
	late int relationId;    // Relationship unique identifier. May be 0 if unsaved.
	late String fieldType;  // Field name used for this relationship.

	MoteRelation.new(this.sourceId, this.targetId, this.fieldType) {
		relationId = 0;
	}

	MoteRelation.fromJson(Map<String, dynamic> json, int moteSourceId) {
		relationId = json['relid'];
		// A field type with a '*' prefix indicates a reversed relationship.
		fieldType = json['field'];
		if (fieldType.substring(0 ,1) == '*') {
			fieldType = fieldType.substring(1);
			sourceId = json['id'];
			targetId = moteSourceId;

		} else {
			sourceId = moteSourceId;
			targetId = json['id'];
		}
	}

	// Returns true if this relationship is a reverse relationship from another mote.
	bool isReverseRelationship(int moteId) {
		return sourceId != moteId;
	}


}