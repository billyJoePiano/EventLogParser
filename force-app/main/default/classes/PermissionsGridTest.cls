@IsTest
public class PermissionsGridTest {
    public class QueryLocatorIterable implements Iterable<SObject> {
        private final Database.QueryLocator ql;

        public QueryLocatorIterable(Database.QueryLocator ql) {
            this.ql = ql;
        }

        public Iterator<SObject> iterator() {
            return new QueryLocatorIterator(ql.iterator());
        }
    }

    public class QueryLocatorIterator implements Iterator<SObject> {
        private final Database.QueryLocatorIterator qli;
        private Integer count = 0;

        public QueryLocatorIterator(Database.QueryLocatorIterator qli) {
            this.qli = qli;
        }

        public Boolean hasNext() {
            return this.count < 2000 && this.qli.hasNext();
        }

        public SObject next() {
            this.count++;
            return this.qli.next();
        }
    }

    @IsTest
    public static void testObjectsFieldsSteps() {
        Test.startTest();
        PermissionsGridObjectsFields maker = new PermissionsGridObjectsFields(PermissionsGridObjectsFields.DEFAULT_STATIC_RESOURCE_NAME);
        
        List<PermissionSet> pss = new List<PermissionSet>();
        for (SObject obj : new QueryLocatorIterable(maker.start(null))) {
            pss.add((PermissionSet)obj);
        }
        maker.execute(null, pss);

        maker.step++;
        List<ObjectPermissions> ops = new List<ObjectPermissions>();
        for (SObject obj : new QueryLocatorIterable(maker.start(null))) {
            ops.add((ObjectPermissions)obj);
        }
        maker.execute(null, ops);

        //test duplicate ObjectPermissions edge-case logic
        for (ObjectPermissions op : ops) {
            op = op.clone();
            Integer column = maker.getColumnForPS(op.ParentId);
            if (column == null) continue;
            PermissionsGridObjectsFields.Output objOutput = maker.result.get(op.SobjectType);
            objOutput.objRow.set(column, 'Create, Modify all records, Edit, Delete, Read, View all records, View all fields, Invalid text');
            op.PermissionsCreate = false;
            op.PermissionsModifyAllRecords = false;
            op.PermissionsEdit = false;
            op.PermissionsDelete = false;
            op.PermissionsRead = false;
            op.PermissionsViewAllRecords = false;
            op.PermissionsViewAllFields = false;
            maker.execute2(new List<ObjectPermissions> { op });
            System.assertEquals('Create, Modify all records, View all fields', objOutput.objRow.get(column));
            break;
        }

        maker.step++;
        List<FieldPermissions> fps = new List<FieldPermissions>();
        for (SObject obj : new QueryLocatorIterable(maker.start(null))) {
            fps.add((FieldPermissions)obj);
        }
        maker.execute(null, fps);
        
        //test duplicate FieldPermissions edge-case logic
        for (FieldPermissions fp : fps) {
            fp = fp.clone();
            Integer column = maker.getColumnForPS(fp.ParentId);
            if (column == null) continue;
            PermissionsGridObjectsFields.Output objOutput = maker.result.get(fp.SobjectType);
            List<String> fieldSplit = fp.Field.split('\\.', 2);
            String fieldName = fieldSplit.get(fieldSplit.size() - 1);
            List<String> fieldRow = objOutput.fieldRows.get(fieldName);
            fieldRow.set(column, 'Read');
            fp.PermissionsEdit = true;
            fp.PermissionsRead = true;
            maker.execute3(new List<FieldPermissions> { fp });
            System.assertEquals('Edit', fieldRow.get(column));
            break;
        }

        //test missing PermissionSet Ids
        for (FieldPermissions fp : fps) {
            fp = fp.clone();
            Integer sizeBefore = maker.unexpectedPsIds.size();
            Id randPsId;
            do {
                randPsId = new Random().id(PermissionSet.SobjectType);
            } while (maker.personasMap.containsKey(randPsId));
            fp.ParentId = randPsId;
            maker.execute3(new List<FieldPermissions> { fp });
            System.assertEquals(sizeBefore + 1, maker.unexpectedPsIds.size());
            break;
        }

        maker.finish(null);

        Test.stopTest();
    }

    @IsTest
    public static void testObjectsFieldsExceptionLogging() {
        PermissionsGridObjectsFields maker = new PermissionsGridObjectsFields(PermissionsGridObjectsFields.DEFAULT_STATIC_RESOURCE_NAME);
        maker.step = PermissionsGridObjectsFields.LAST_STEP + 1;
        try {
            maker.start(null);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) { }
        try {
            maker.execute(null, null);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) { }
        
        Test.startTest();
        PermissionsGridObjectsFields.makePermissionsGrid();
        Test.stopTest();
    }

    @IsTest
    public static void testUsersSteps() {
        Test.startTest();
        PermissionsGridUsers maker = new PermissionsGridUsers(PermissionsGridUsers.DEFAULT_STATIC_RESOURCE_NAME);
        
        List<PermissionSet> pss = new List<PermissionSet>();
        for (SObject obj : new QueryLocatorIterable(maker.start(null))) {
            pss.add((PermissionSet)obj);
        }
        maker.execute(null, pss);

        maker.step++;
        List<User> users = new List<User>();
        for (SObject obj : new QueryLocatorIterable(maker.start(null))) {
            users.add((User)obj);
        }
        maker.execute(null, users);

        maker.step++;
        List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
        for (SObject obj : new QueryLocatorIterable(maker.start(null))) {
            psas.add((PermissionSetAssignment)obj);
        }
        maker.execute(null, psas);

        //test duplicate and unexpected edge-case logic
        psas = new List<PermissionSetAssignment> {
            psas.get(0).clone(),
            psas.get(0).clone(),
            psas.get(0).clone(),
            psas.get(0).clone()
        };

        Id randUserId, randPsId;
        do {
            randUserId = new Random().id(User.SObjectType);
        } while (maker.usersMap.containsKey(randUserId));

        do {
            randPsId = new Random().id(PermissionSetAssignment.SObjectType);
        } while (maker.psMap.containsKey(randPsId));

        psas.get(0).AssigneeId = randUserId;
        psas.get(1).PermissionSetId = randPsId;
        psas.get(2).AssigneeId = randUserId;
        psas.get(2).PermissionSetId = randPsId;

        maker.execute(null, psas);

        maker.finish(null);

        Test.stopTest();
    }

    @IsTest
    public static void testUsersExceptionLogging() {
        PermissionsGridUsers maker = new PermissionsGridUsers(PermissionsGridUsers.DEFAULT_STATIC_RESOURCE_NAME);
        maker.step = PermissionsGridUsers.LAST_STEP + 1;
        try {
            maker.start(null);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) { }
        try {
            maker.execute(null, null);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) { }
        
        Test.startTest();
        PermissionsGridUsers.makePermissionsGrid();
        Test.stopTest();
    }

    @IsTest
    public static void testProfileVsPsSteps() {
        Test.startTest();
        PermissionsGridProfileVsPs maker = new PermissionsGridProfileVsPs(PermissionsGridProfileVsPs.DEFAULT_STATIC_RESOURCE_NAME);

        List<PermissionSet> pss = new List<PermissionSet>();
        Integer profileCount = 0;
        Integer psCount = 0;
        Integer psgCount = 0;
        for (SObject obj : new QueryLocatorIterable(maker.start(null))) {
            PermissionSet ps = (PermissionSet)obj;
            //limit the number of profiles, permission sets, and permission set groups to 5 each
            if (ps.IsOwnedByProfile) {
                if (profileCount < 5) {
                    pss.add(ps);
                    profileCount++;
                }
            } else if (ps.PermissionSetGroupId != null) {
                if (psgCount < 5) {
                    pss.add(ps);
                    psgCount++;
                }
            } else {
                if (psCount < 5) {
                    pss.add(ps);
                    psCount++;
                }
            }
            if (pss.size() >= 15) break;
        }
        maker.execute(null, pss);
        maker.finish(null); // calls maker.nextStep() after step 1, which automatically increments maker.step

        while (maker.step <= 3) {
            List<ObjectPermissions> ops = new List<ObjectPermissions>();
            for (SObject obj : new QueryLocatorIterable(maker.start(null))) {
                ops.add((ObjectPermissions)obj);
            }
            maker.execute(null, ops);
            maker.objectProcessor = null;

            if (maker.step == 2) {
                maker.finish(null); // calls maker.nextStep() after step 2, which automatically increments maker.step
            } else {
                maker.finish(null);
                maker.objectProcessor.finish(null); // needed after step 3 to call maker.nextStep() which increments maker.step
            }
        }

        while (maker.step <= 5) {
            List<FieldPermissions> fps = new List<FieldPermissions>();
            for (SObject obj : new QueryLocatorIterable(maker.start(null))) {
                fps.add((FieldPermissions)obj);
            }
            maker.execute(null, fps);
            maker.fieldProcessor = null;

            if (maker.step == 4) {
                maker.finish(null); // calls maker.nextStep() after step 4, which automatically increments maker.step
            } else {
                maker.finish(null);
                maker.objectProcessor.finish(null); // needed after step 5 to call maker.nextStep() which increments maker.step
            }
        }

        while (maker.step < 8) {
            maker.nextStep(); //automatically increments maker.step and runs the code logic for that step
        }

        Test.stopTest();
    }
}