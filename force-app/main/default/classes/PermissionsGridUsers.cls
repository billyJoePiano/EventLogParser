/**
 * Utility for analyzing actually-existing Permissions in the Salesforce Org.
 * 
 * This creates a CSV spreadsheet where Profiles, Permission Sets, and Permission Set Groups are listed across the columns headers,
 * while users are listed down the rows, showing which users are assigned to which Permission Sets and Permission Set Groups.
 * 
 * The resulting CSV is saved as a static resource, with a default name of 'PermissionsGridUsers'
 */
public class PermissionsGridUsers extends BatchableLogger implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    public static final String DEFAULT_STATIC_RESOURCE_NAME = 'PermissionsGridUsers';
    public static final Integer LAST_STEP = 3;

    public static void makePermissionsGrid() {
        makePermissionsGrid(DEFAULT_STATIC_RESOURCE_NAME);
    }

    public static void makePermissionsGrid(String staticResourceName) {
        Id jobId = Database.executeBatch(new PermissionsGridUsers(staticResourceName), 2000);
        Logger.debug('PermissionsGridUsers.makePermissionsGrid, enqueued batch for step 1, Job Id: ' + jobId);
        Logger.saveLog();
    }

    public final String staticResourceName;
    public final List<PermissionSet> permissionSets = new List<PermissionSet>();
    public final Map<Id, Set<Id>> psMap = new Map<Id, Set<Id>>(); //maps PermissionSet Id to User Ids

    public final List<User> users = new List<User>();
    public final Map<Id, Set<Id>> usersMap = new Map<Id, Set<Id>>(); //maps User Id to PermissionSet Ids

    public final Set<Id> unexpectedPsIds = new Set<Id>();
    public final Set<Id> unexpectedUserIds = new Set<Id>();
    public final List<PermissionSetAssignment> duplicateAssignments = new List<PermissionSetAssignment>();

    @TestVisible
    private Integer step = 1;

    @TestVisible
    private PermissionsGridUsers(String staticResourceName) {
        super(true);
        this.staticResourceName = staticResourceName;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.setLoggerTransactionId();
        try {
            String query;
            switch on this.step {
                when 1 { query = query1(); }
                when 2 { query = query2(); }
                when 3 { query = query3(); }
                when else { throw new IllegalArgumentException('Unexpected step: ' + this.step); }
            }
            if (Test.isRunningTest()) {
                query += ' LIMIT 2000';
            }
            return Database.getQueryLocator(query.normalizeSpace(), AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            Logger.error('PermissionSetGridMaker.start, step ' + this.step, e);
            Logger.saveLog();
            throw e;
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> result) {
        this.setLoggerTransactionId();
        try {
            switch on this.step {
                when 1 { execute1((List<PermissionSet>)result); }
                when 2 { execute2((List<User>)result); }
                when 3 { execute3((List<PermissionSetAssignment>)result); }
                when else { throw new IllegalArgumentException('Unexpected step: ' + this.step); }
            }
        } catch (Exception e) {
            Logger.error('PermissionSetGridMaker.execute, step ' + this.step, e);
            Logger.saveLog();
            throw e;
        }
    }

    public void finish(Database.BatchableContext bc) {
        this.setLoggerTransactionId();
        this.step++;
        try {
            if (this.step <= LAST_STEP) {
                Id jobId = Database.executeBatch(this, 2000);
                Logger.debug('PermissionSetGridMaker.finish, enqueued batch for next step (' + this.step + '), Job Id: ' + jobId);
                Logger.saveLog();
            } else {
                this.enqueueWriter();
            }
        } catch (Exception e) {
            Logger.error('PermissionSetGridMaker.finish, step ' + (this.step - 1), e);
            Logger.saveLog();
            throw e;
        }
    }

    public String query1() {
        return '''
            SELECT Id, Description, HasActivationRequired, IsCustom, IsOwnedByProfile, Label, LicenseId, Name, NamespacePrefix, Type,
                PermissionSetGroupId, PermissionSetGroup.Description, PermissionSetGroup.MasterLabel
            FROM PermissionSet
            WHERE IsOwnedByProfile = FALSE
            ORDER BY Type ASC, Name ASC
        ''';
    }

    public void execute1(List<PermissionSet> pss) {
        this.permissionSets.addAll(pss);
        for (PermissionSet ps : pss) {
            this.psMap.put(ps.Id, new Set<Id>());
        }
    }

    public String query2() {
        return '''
            SELECT Id, Name, Username, ProfileId, Profile.Name, UserRole.Name
            FROM User
            ORDER BY Profile.Name ASC, UserRole.Name ASC, LastName ASC, FirstName ASC, MiddleName ASC, Username ASC
        ''';
    }

    public void execute2(List<User> users) {
        this.users.addAll(users);
        for (User u : users) {
            this.usersMap.put(u.Id, new Set<Id>());
        }
    }

    public String query3() {
        return '''
            SELECT Id, AssigneeId, PermissionSetId
            FROM PermissionSetAssignment
            ORDER BY Assignee.Profile.Name ASC, Assignee.LastName ASC, Assignee.FirstName ASC, Assignee.Username ASC,
                PermissionSet.Type ASC, PermissionSet.Name ASC
        ''';
    }

    public void execute3(List<PermissionSetAssignment> assignments) {
        for (PermissionSetAssignment a : assignments) {
            Id psId = a.PermissionSetId;
            Id userId = a.AssigneeId;
            Set<Id> userPsAssignments = this.usersMap.get(userId);
            Set<Id> psUserAssignments = this.psMap.get(psId);

            if (userPsAssignments == null) {
                this.unexpectedUserIds.add(userId);
                if (psUserAssignments == null) {
                    this.unexpectedPsIds.add(psId);
                }
                continue;
            } else if (psUserAssignments == null) {
                this.unexpectedPsIds.add(psId);
                continue;
            }

            if (!(userPsAssignments.add(psId) & psUserAssignments.add(userId))) { // use bitwise & to ensure eager evaluation (as opposed to && lazy evaluation)
                this.duplicateAssignments.add(a);
            }
        }
    }

    public void enqueueWriter() {
        if (this.unexpectedPsIds.size() > 0) {
            Logger.debug('PermissionsGridUsers: unexpected PermissionSet Ids').setRecord(this.unexpectedPsIds);
            this.unexpectedPsIds.clear();
        }
        if (this.unexpectedUserIds.size() > 0) {
            Logger.debug('PermissionsGridUsers: unexpected User Ids').setRecord(this.unexpectedUserIds);
            this.unexpectedUserIds.clear();
        }
        if (this.duplicateAssignments.size() > 0) {
            Logger.debug('PermissionsGridUsers: unexpected duplicate permission set assignments').setRecord(this.duplicateAssignments);
            this.duplicateAssignments.clear();
        }

        this.permissionSets.sort(new MultiComparator(new List<Comparator<SObject>> {
            new SetSizeNonzeroComparator(this.psMap),
            new StringFieldComparator('Type'),
            new SetSizeComparator(this.psMap)
        }));
        this.users.sort(new MultiComparator(new List<Comparator<SObject>> {
            new SetSizeGroupAvgComparator(this.usersMap, this.users,
                                          new MultiFieldGetter(new List<String> {'Profile.Name'})),
            new StringFieldComparator('Profile.Name'),
            new SetSizeGroupAvgComparator(this.usersMap, this.users,
                                          new MultiFieldGetter(new List<String> {'Profile.Name', 'UserRole.Name'})),
            new StringFieldComparator('UserRole.Name'),
            new SetSizeComparator(this.usersMap)
        }));

        List<List<String>> output = getPermissionSetHeaders();
        for (User u : this.users) {
            List<String> row = new List<String> {
                u.Name,
                u.Username,
                u.Profile?.Name,
                u.UserRole?.Name,
                String.valueOf(this.usersMap.get(u.Id)?.size())
            };
            
            for (Id psId : this.usersMap.get(u.Id)) {
                Integer col = this.getColumnForPS(psId);
                while (row.size() <= col) {
                    row.add(null);
                }
                row.set(col, 'TRUE');
            }
            output.add(row);
        }

        Id jobId = new CSVWriter().writeToStaticResourceAsync(output, this, 'PermissionsGridUsers', this.staticResourceName, 'PermissionsGridUsers result', false);
        Logger.debug('PermissionsGridUsers.enqueueWriter, JobId ' + jobId);
        Logger.saveLog();
    }

    public List<List<String>> getPermissionSetHeaders() {
        List<String> names = new List<String> {null, null, null, null, 'PermissionSet:'};
        List<String> psTypes = new List<String> {null, null, null, null, 'Type:'};
        List<String> extraRow = new List<String> {null, null, null, null, null};
        List<String> counts = new List<String> {'Name', 'Username', 'Profile', 'Role', 'Count:'};
        for (PermissionSet ps : this.permissionSets) {
            PermissionsGridObjectsFields.addToHeaders(ps, names, psTypes, extraRow);
            counts.add(String.valueOf(this.psMap.get(ps.Id)?.size()));
        }
        return new List<List<String>> { names, psTypes, extraRow , counts};
    }

    public Integer getColumnForPS(Id psId) {
        Integer col = 5; //0-indexed with first 5 columns being for name, username, profile name, role name, and count
        for (PermissionSet ps : this.permissionSets) {
            if (ps.Id == psId) return col;
            col++;
        }
        return null;
    }

    public class MultiComparator implements Comparator<SObject> {
        public final List<Comparator<SObject>> comparators;

        public MultiComparator(List<Comparator<SObject>> comparators) {
            this.comparators = comparators;
        }

        public Integer compare(SObject obj1, SObject obj2) {
            for (Comparator<SObject> comparator : this.comparators) {
                Integer result = comparator.compare(obj1, obj2);
                if (result != 0 && result != null) {
                    return result;
                }
            }
            return 0;
        }
    }

    virtual public class SetSizeComparator implements Comparator<SObject> {
        public final Map<Id, Set<Id>> idsMap;

        public SetSizeComparator(Map<Id, Set<Id>> idsMap) {
            this.idsMap = idsMap;
        }

        virtual public Integer compare(SObject obj1, SObject obj2) {
            Integer size1 = this.size(obj1);
            Integer size2 = this.size(obj2);
            if (size1 < size2) return 1;
            if (size2 < size1) return -1;
            return 0;
        }

        virtual public Integer size(SObject obj) {
            if (obj == null) return 0;
            Set<Id> ids = idsMap.get(obj.Id);
            if (ids == null) return 0;
            return ids.size();
        }
    }

    virtual public class SetSizeNonzeroComparator extends SetSizeComparator {
        public SetSizeNonzeroComparator(Map<Id, Set<Id>> idsMap) {
            super(idsMap);
        }

        override virtual public Integer size(SObject obj) {
            return super.size(obj) > 0 ? 1 : 0;
        }
    }

    public class FieldGetter {
        public final List<String> relationships;
        public final String field;

        public FieldGetter(String fieldStr) {
            this.relationships = fieldStr.split('\\.');
            this.field = this.relationships.remove(this.relationships.size() - 1);
        }

        public String get(SObject obj) {
            for (String relationship : this.relationships) {
                obj = obj?.getSobject(relationship);
            }
            return (String)obj?.get(this.field);
        }
    }

    public class MultiFieldGetter {
        public final List<FieldGetter> fields;

        public MultiFieldGetter(List<String> fieldsStr) {
            this.fields = new List<FieldGetter>();
            for (String fieldStr : fieldsStr) {
                this.fields.add(new FieldGetter(fieldStr));
            }
        }

        public List<String> get(SObject obj) {
            List<String> result = new List<String>();
            for (FieldGetter field : this.fields) {
                result.add(field.get(obj));
            }
            return result;
        }
    }

    virtual public class SetSizeGroupAvgComparator extends SetSizeComparator {
        public final MultiFieldGetter groupByFields;
        public final Map<List<String>, Double> avgs = new Map<List<String>, Double>();
        
        public SetSizeGroupAvgComparator(Map<Id, Set<Id>> idsMap, List<SObject> objects, MultiFieldGetter groupByFields) {
            super(idsMap);
            this.groupByFields = groupByFields;

            Map<List<String>, List<Integer>> avgsCounter = new Map<List<String>, List<Integer>>();
            for (SObject obj : objects) {
                Integer size = this.size(obj);
                List<String> groupByValues = groupByFields.get(obj);
                List<Integer> groupCounter = avgsCounter.get(groupByValues);
                if (groupCounter == null) {
                    groupCounter = new List<Integer>();
                    avgsCounter.put(groupByValues, groupCounter);
                }
                groupCounter.add(size);
            }

            for (List<String> groupByValues : avgsCounter.keySet()) {
                List<Integer> groupCounter = avgsCounter.get(groupByValues);
                Integer sum = 0;
                for (Integer size : groupCounter) {
                    sum += size;
                }
                Double groupAvg = ((Double)sum) / groupCounter.size();
                this.avgs.put(groupByValues, groupAvg);
            }
        }

        override virtual public Integer compare(SObject obj1, SObject obj2) {
            Double avg1 = this.avgs.get(this.groupByFields.get(obj1));
            Double avg2 = this.avgs.get(this.groupByFields.get(obj2));
            if (avg1 == null) avg1 = 0.0;
            if (avg2 == null) avg2 = 0.0;
            if (avg1 < avg2) return 1;
            if (avg2 < avg1) return -1;
            return 0;
        }
    }

    public class StringFieldComparator implements Comparator<SObject> {
        public final FieldGetter field;
        public final Comparator<String> stringComparator;

        public StringFieldComparator(String fieldStr) {
            this(fieldStr, new PermissionsGridObjectsFields.CaseInsensitiveStringComparator());
        }

        public StringFieldComparator(String fieldStr, Comparator<String> stringComparator) {
            this.field = new FieldGetter(fieldStr);
            this.stringComparator = stringComparator;
        }

        public Integer compare(SObject obj1, SObject obj2) {
            return this.stringComparator.compare(this.field.get(obj1), this.field.get(obj2));
        }
    }
}