public class PermissionsGridObjectsFields extends BatchableLogger implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    public static final String DEFAULT_STATIC_RESOURCE_NAME = 'PermissionsGridObjectsFields';
    public static final Integer LAST_STEP = 3;

    public static void makePermissionsGrid() {
        makePermissionsGrid(DEFAULT_STATIC_RESOURCE_NAME);
    }

    public static void makePermissionsGrid(String staticResourceName) {
        Id jobId = Database.executeBatch(new PermissionsGridObjectsFields(staticResourceName), 2000);
        Logger.debug('PermissionsGridObjectsFields.makePermissionsGrid, enqueued batch for step 1, Job Id: ' + jobId);
        Logger.saveLog();
    }

    public final String staticResourceName;
    public final List<PermissionSet> personas = new List<PermissionSet>();
    public final Map<String, Output> result = new Map<String, Output>(); //maps SobjectType to output result
    public final Set<Id> unexpectedPsIds = new Set<Id>();
    public final List<SObject> duplicatePerms = new List<SObject>();

    public transient Map<Id, PermissionSet> personasMap = null;

    @TestVisible
    private Integer step = 1;

    @TestVisible
    private PermissionsGridObjectsFields(String staticResourceName) {
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
            Logger.error('PermissionsGridObjectsFields.start, step ' + this.step, e);
            Logger.saveLog();
            throw e;
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> result) {
        this.setLoggerTransactionId();
        try {
            switch on this.step {
                when 1 { execute1((List<PermissionSet>)result); }
                when 2 { execute2((List<ObjectPermissions>)result); }
                when 3 { execute3((List<FieldPermissions>)result); }
                when else { throw new IllegalArgumentException('Unexpected step: ' + this.step); }
            }
            if (Logger.getBufferSize() > 0) {
                Logger.saveLog();
            }
        } catch (Exception e) {
            Logger.error('PermissionsGridObjectsFields.execute, step ' + this.step, e);
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
                Logger.debug('PermissionsGridObjectsFields.finish, enqueued batch for next step (' + this.step + '), Job Id: ' + jobId);
                Logger.saveLog();
            } else {
                this.enqueueWriter();
            }
        } catch (Exception e) {
            Logger.error('PermissionsGridObjectsFields.finish, step ' + (this.step - 1), e);
            Logger.saveLog();
            throw e;
        }
    }

    public String query1() {
        return '''
            SELECT Id, Description, HasActivationRequired, IsCustom, IsOwnedByProfile, Label, LicenseId, Name, NamespacePrefix, ProfileId,
                Profile.Name, Type, PermissionSetGroupId, PermissionSetGroup.Description, PermissionSetGroup.MasterLabel
            FROM PermissionSet
            ORDER BY IsOwnedByProfile DESC, Type ASC, Profile.Name ASC, Name ASC
        ''';
    }

    public void execute1(List<PermissionSet> pss) {
        this.personas.addAll(pss);
    }

    public class Output {
        public final List<String> objRow = new List<String>();
        public Map<String, List<String>> fieldRows = new Map<String, List<String>>(); //maps field name to CSV row

        public Output(String objName) {
            this.objRow.add(objName);
            this.objRow.add(null);
        }

        public void addObjPerm(PermissionsGridObjectsFields maker, Integer column, ObjectPermissions op) {
            List<String> perms = new List<String>();
            if (objRow.size() <= column) {
                do {
                    objRow.add(null);
                } while (objRow.size() <= column);
            } else if (objRow.get(column) != null) {
                // deal with edge-case: duplicate permissions for same SobjectType and PermissionSetId
                maker.duplicatePerms.add(op);
                List<String> oldPerms = objRow.get(column).split(', ');
                op = op.clone();
                for (String perm : oldPerms) {
                    switch on perm {
                        when 'Create' {
                            op.PermissionsRead = true;
                            op.PermissionsCreate = true;
                        }
                        when 'Modify all records' {
                            op.PermissionsRead = true;
                            op.PermissionsEdit = true;
                            op.PermissionsDelete = true;
                            op.PermissionsViewAllRecords = true;
                            op.PermissionsModifyAllRecords = true;
                        }
                        when 'Edit' {
                            op.PermissionsRead = true;
                            op.PermissionsEdit = true;
                        }
                        when 'Delete' {
                            op.PermissionsRead = true;
                            op.PermissionsDelete = true;
                        }
                        when 'Read' {
                            op.PermissionsRead = true;
                        }
                        when 'View all records' {
                            op.PermissionsRead = true;
                            op.PermissionsViewAllRecords = true;
                        }
                        when 'View all fields' {
                            op.PermissionsViewAllFields = true;
                        }
                        when else {
                            Logger.warn('Unexpected object permission added to column ' + column + ' on ' + this.objRow.get(0) + ': ' + perm);
                        }
                    }
                }
            }

            if (op.PermissionsCreate) {
                perms.add('Create');
            }
            if (op.PermissionsModifyAllRecords) {
                //ModifyAllRecords implies Read, Edit, Delete, and ViewAllRecords (but not neccessarily Create or ViewAllFields)
                perms.add('Modify all records');
            } else if (op.PermissionsRead) {
                // Create, Edit, Delete, and ViewAllRecords imply Read
                if (op.PermissionsEdit) {
                    perms.add('Edit');
                }
                if (op.PermissionsDelete) {
                    perms.add('Delete');
                }
                if (perms.size() < 1) {
                    perms.add('Read');
                }
                if (op.PermissionsViewAllRecords) {
                    perms.add('View all records');
                }
            }
            if (op.PermissionsViewAllFields) {
                perms.add('View all fields');
            }

            objRow.set(column, String.join(perms, ', '));
        }

        public void addFieldPerm(PermissionsGridObjectsFields maker, Integer column, FieldPermissions fp) {
            List<String> fieldSplit = fp.Field.split('\\.', 2);
            String fieldName = fieldSplit.get(fieldSplit.size() - 1);

            List<String> fieldRow = this.fieldRows.get(fieldName);
            if (fieldRow == null) {
                fieldRow = new List<String> { this.objRow.get(0), fieldName };
                this.fieldRows.put(fieldName, fieldRow);
            }
            if (fieldRow.size() <= column) {
                do {
                    fieldRow.add(null);
                } while (fieldRow.size() <= column);
            } else if (fieldRow.get(column) != null) {
                maker.duplicatePerms.add(fp);
                if (fp.PermissionsEdit) { //overwrite only if PermissionsEdit = true
                    fieldRow.set(column, 'Edit');
                }
                return;
            }
            if (fp.PermissionsEdit) {
                // Edit implies Read
                fieldRow.set(column, 'Edit');
            } else if (fp.PermissionsRead) {
                fieldRow.set(column, 'Read');
            }
        }
    }

    public Integer getColumnForPS(Id parentId) {
        if (this.personasMap == null) {
            this.personasMap = new Map<Id, PermissionSet>(this.personas);
        }
        Integer column = this.personas.indexOf(this.personasMap.get(parentId));
        if (!(column > -1)) {
            this.unexpectedPsIds.add(parentId);
            return null;
        }
        return column + 2;
    }

    public String query2() {
        return '''
            SELECT Id, ParentId, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords,
                PermissionsViewAllFields, PermissionsModifyAllRecords
            FROM ObjectPermissions
            ORDER BY SobjectType ASC
        ''';
    }

    public void execute2(List<ObjectPermissions> objPerms) {
        for (ObjectPermissions op : objPerms) {
            Integer col = this.getColumnForPS(op.ParentId);
            if (col == null) continue;

            Output objOutput = this.result.get(op.SobjectType);
            if (objOutput == null) {
                objOutput = new Output(op.SobjectType);
                this.result.put(op.SobjectType, objOutput);
            }
            objOutput.addObjPerm(this, col, op);
        }
    }

    public String query3() {
        return '''
            SELECT ParentId, SobjectType, Field, PermissionsRead, PermissionsEdit
            FROM FieldPermissions
            ORDER BY SobjectType ASC, Field ASC, Parent.IsOwnedByProfile DESC, Parent.Profile.Name ASC, Parent.Name ASC
        ''';
    }

    public void execute3(List<FieldPermissions> fldPerms) {
        for (FieldPermissions fp : fldPerms) {
            Integer col = this.getColumnForPS(fp.ParentId);
            if (col == null) continue;

            Output objOutput = this.result.get(fp.SobjectType);
            if (objOutput == null) {
                objOutput = new Output(fp.SobjectType);
                this.result.put(fp.SobjectType, objOutput);
            }
            objOutput.addFieldPerm(this, col, fp);
        }
    }

    public void enqueueWriter() {
        if (this.unexpectedPsIds.size() > 0) {
            Logger.debug('PermissionsGridObjectsFields: unexpected PermissionSet Ids').setRecord(this.unexpectedPsIds);
            this.unexpectedPsIds.clear();
        }
        if (this.duplicatePerms.size() > 0) {
            Logger.debug('PermissionsGridObjectsFields: unexpected duplicate object/field permissions').setRecord(this.duplicatePerms);
            this.duplicatePerms.clear();
        }

        List<List<String>> output = getPermissionSetHeaders();
        for (String objName : getNamesSorted(this.result.keySet())) {
            Output out = this.result.remove(objName);
            output.add(new List<String>()); //empty row
            output.add(out.objRow);
            for (String fieldName : getNamesSorted(out.fieldRows.keySet())) {
                output.add(out.fieldRows.get(fieldName));
            }
        }

        Id jobId = new CSVWriter().writeToStaticResourceAsync(output, this, 'PermissionsGridObjectsFields', this.staticResourceName, 'PermissionsGridObjectsFields result', false);
        Logger.debug('PermissionsGridObjectsFields.enqueueWriter, JobId ' + jobId);
        Logger.saveLog();
    }

    public List<List<String>> getPermissionSetHeaders() {
        List<String> names = new List<String> {null, 'PermissionSet/Profile:'};
        List<String> psTypes = new List<String> {null, 'Type:'};
        List<String> extraRow = new List<String> {'Object', 'Field'};
        for (PermissionSet ps : this.personas) {
            addToHeaders(ps, names, psTypes, extraRow);
        }
        return new List<List<String>> { names, psTypes, extraRow };
    }

    // This method is also used by PermissionsGridUsers and PermissionGridProfileVsPs (which is why it isn't just inlined within the for loop of getPermissionSetHeaders)
    public static void addToHeaders(PermissionSet ps, List<Object> names, List<Object> psTypes, List<Object> extraRow) {
        List<String> extraStr = new List<String>();
        if (ps.IsOwnedByProfile) {
            names.add(ps.Profile.Name);
            extraStr.add('Profile');
        } else {
            names.add(ps.Name);
        }
        psTypes.add(ps.Type);
        if (ps.PermissionSetGroupId != null) {
            extraStr.add('Group');
        }
        if (ps.HasActivationRequired) {
            extraStr.add('Activation Required');
        }
        if (ps.LicenseId != null) {
            extraStr.add('License');
        }
        if (extraStr.size() > 0) {
            extraRow.add(String.join(extraStr, ', '));
        } else{
            extraRow.add(null);
        }
    }
    
    public static List<String> getNamesSorted(Iterable<String> names) {
        List<String> stdNames = new List<String>();
        List<String> cstNames = new List<String>();
        Map<String, List<String>> nsNames = new Map<String, List<String>>(); //namespaced objs/fields

        for (String objName : names) {
            List<String> split = objName.split('__');
            if (split.size() < 2) {
                stdNames.add(objName);
            } else if (split.size() == 2 && split.get(1) == 'c') {
                cstNames.add(objName);
            } else {
                String ns = split.get(0); //namespace
                List<String> nsList = nsNames.get(ns);
                if (nsList == null) {
                    nsList = new List<String>();
                    nsNames.put(ns, nsList);
                }
                nsList.add(objName);
            }
        }

        stdNames.sort(new CaseInsensitiveStringComparator());
        cstNames.sort(new CaseInsensitiveStringComparator());

        List<String> namesSorted = new List<String>();
        namesSorted.addAll(stdNames);
        namesSorted.addAll(cstNames);

        List<String> namespaces = new List<String>(nsNames.keySet());
        namespaces.sort(new CaseInsensitiveStringComparator());
        for (String ns : namespaces) {
            List<String> nsList = nsNames.get(ns);
            nsList.sort(new CaseInsensitiveStringComparator());
            namesSorted.addAll(nsList);
        }

        return namesSorted;
    }

    public class CaseInsensitiveStringComparator implements Comparator<String> {
        public Integer compare(String str1, String str2) {
            if (str1 != null) {
                if (str2 != null) {
                    return str1.toLowerCase().compareTo(str2.toLowerCase());
                } else {
                    return 1;
                }
            } else if (str2 != null) {
                return -1;
            } else {
                return 0;
            }
        }
    }
}