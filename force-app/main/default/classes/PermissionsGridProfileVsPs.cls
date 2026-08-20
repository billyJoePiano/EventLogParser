public class PermissionsGridProfileVsPs extends BatchableLogger implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    public static final String DEFAULT_STATIC_RESOURCE_NAME = 'PermissionsGridProfileVsPs';

    public static void makePermissionsGrid() {
        makePermissionsGrid(DEFAULT_STATIC_RESOURCE_NAME);
    }

    public static void makePermissionsGrid(String staticResourceName) {
        Id jobId = Database.executeBatch(new PermissionsGridProfileVsPs(staticResourceName), 2000);
        Logger.debug('PermissionsGridProfileVsPs.makePermissionsGrid, enqueued batch for step 1, Job Id: ' + jobId);
        Logger.saveLog();
    }

    public final String staticResourceName;
    public final List<PermissionSet> profiles = new List<PermissionSet>();
    public final List<PermissionSet> pss = new List<PermissionSet>(); //non-profile PermissionSets
    
    //dummy Object/FieldPermissions, reused to save on heap-space
    public final Map<Integer, ObjectPermissions> dummyOps = new Map<Integer, ObjectPermissions>();
    public final Map<Integer, FieldPermissions> dummyFps = new Map<Integer, FieldPermissions>();
    
    // Maps psId => SObject name => ObjectPermissions
    public final Map<Id, Map<String, ObjectPermissions>> profileOps = new Map<Id, Map<String, ObjectPermissions>>();
    public final Map<Id, Map<String, ObjectPermissions>> psOps = new Map<Id, Map<String, ObjectPermissions>>();
    
    // Maps psId => SObject name => fieldName (normalized, w/o SObject name) => FieldPermissions
    public final Map<Id, Map<String, Map<String, FieldPermissions>>> profileFps = new Map<Id, Map<String, Map<String, FieldPermissions>>>();
    public final Map<Id, Map<String, Map<String, FieldPermissions>>> psFps = new Map<Id, Map<String, Map<String, FieldPermissions>>>();
    
    // Maps psId (non-profile) => psId (profile) => DiffCounts
    public final Map<Id, Map<Id, DiffCounter>> result = new Map<Id, Map<Id, DiffCounter>>();
    public final Map<Id, List<Double>> resultSorting = new Map<Id, List<Double>>(); // value is a List of 3 doubles returned by DiffCounter.calcOutput/getOutput
    public final List<List<Object>> output = new List<List<Object>>();

    public final List<Id> readyToCompare = new List<Id>();
    private ObjectPermissionsComparisonProcessor objectProcessor = null;
    private FieldPermissionsComparisonProcessor fieldProcessor = null;
    
    public final Set<Id> unexpectedPsIds = new Set<Id>();
    public final List<SObject> duplicatePerms = new List<SObject>();

    @TestVisible
    private Integer step = 1;

    @TestVisible
    private PermissionsGridProfileVsPs(String staticResourceName) {
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
                when 4 { query = query4(); }
                when 5 { query = query5(); }
                when else { throw new IllegalArgumentException('Unexpected step: ' + this.step); }
            }
            Set<Id> parentIds = null;
            switch on this.step {
                when 1 { }
                when 2, 4 { parentIds = new Map<Id, PermissionSet>(this.profiles).keySet(); }
                when 3, 5 { parentIds = new Map<Id, PermissionSet>(this.pss).keySet(); }
                when else { throw new IllegalArgumentException('Unexpected step: ' + this.step); }
            }
            if (Test.isRunningTest()) {
                query += ' LIMIT 2000';
            }
            if (parentIds == null) {
                return Database.getQueryLocator(query.normalizeSpace(), AccessLevel.SYSTEM_MODE);
            } else {
                return Database.getQueryLocatorWithBinds(query.normalizeSpace(),
                                                         new Map<String, Object> { 'parentIds' => parentIds },
                                                         AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            Logger.error('PermissionsGridProfileVsPs.start, step ' + this.step, e);
            Logger.saveLog();
            return null;
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> result) {
        this.setLoggerTransactionId();
        try {
            switch on this.step {
                when 1 { execute1((List<PermissionSet>)result); }
                when 2 { execute2((List<ObjectPermissions>)result); }
                when 3 { execute3((List<ObjectPermissions>)result); }
                when 4 { execute4((List<FieldPermissions>)result); }
                when 5 { execute5((List<FieldPermissions>)result); }
                when else { throw new IllegalArgumentException('Unexpected step: ' + this.step); }
            }
            if (Logger.getBufferSize() > 0) {
                Logger.saveLog();
            }
        } catch (Exception e) {
            Logger.error('PermissionsGridProfileVsPs.execute, step ' + this.step, e);
            Logger.saveLog();
        }
    }

    public void finish(Database.BatchableContext bc) {
        this.setLoggerTransactionId();
        Integer finishStep = this.step;
        try {
            switch on this.step {
                when 1, 2, 4 { this.nextStep(); }
                when 3 { this.finish3(); }
                when 5 { this.finish5(); }
                when else { throw new IllegalArgumentException('Unexpected step: ' + this.step); }
            }
        } catch (Exception e) {
            Logger.error('PermissionsGridProfileVsPs.finish, step ' + finishStep, e);
            Logger.saveLog();
        }
    }
    
    public void nextStep() {
        this.step++;
        try {
            switch on this.step {
                when 2, 3, 4, 5 {
                    Id jobId = Database.executeBatch(this, 2000);
                    Logger.debug('PermissionsGridProfileVsPs.nextStep, enqueued batch for next step (' + this.step + '), Job Id: ' + jobId);
                    Logger.saveLog();
                }
                when 6 { this.sortComparisonResults(); }
                when 7 { this.processOutput(); }
                when 8 { this.enqueueWriter(); }
                when else { throw new IllegalArgumentException('Unexpected step: ' + this.step); }
            }
        } catch (Exception e) {
            Logger.error('PermissionsGridProfileVsPs.nextStep for next step ' + this.step, e);
            Logger.saveLog();
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
        for (PermissionSet ps : pss) {
            if (ps.IsOwnedByProfile) {
                this.profiles.add(ps);
            } else {
                this.pss.add(ps);
            }
        }
    }

    public String query2() {
        for (PermissionSet ps : this.profiles) {
            this.profileOps.put(ps.Id, new Map<String, ObjectPermissions>());
        }
        return '''
            SELECT Id, ParentId, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords,
                PermissionsViewAllFields, PermissionsModifyAllRecords
            FROM ObjectPermissions
            WHERE ParentId IN :parentIds
            ORDER BY ParentId ASC, SobjectType ASC
        ''';
    }
    
    public String query3() {
        for (PermissionSet ps : this.pss) {
            this.psOps.put(ps.Id, new Map<String, ObjectPermissions>());
        }
        return '''
            SELECT Id, ParentId, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords,
                PermissionsViewAllFields, PermissionsModifyAllRecords
            FROM ObjectPermissions
            WHERE ParentId IN :parentIds
            ORDER BY ParentId ASC, SobjectType ASC
        ''';
    }

    public void execute2(List<ObjectPermissions> objPerms) {
        this.processObjectPermissions(true, objPerms);
    }

    public void execute3(List<ObjectPermissions> objPerms) {
        this.processObjectPermissions(false, objPerms);
    }

    public void processObjectPermissions(Boolean isProfile, List<ObjectPermissions> objPerms) {
        Map<Id, Map<String, ObjectPermissions>> currentMap = isProfile ? this.profileOps : this.psOps;

        // relying on the sorting of ObjectPermissions by ParentId, so we don't need to re-fetch the same map with each iteration
        Map<String, ObjectPermissions> currentOps;
        Id currentPsId = null;
        for (ObjectPermissions op : objPerms) {
            if (op.ParentId != currentPsId) {
                if (currentOps != null && !isProfile) {
                    this.readyToCompare.add(currentPsId);
                }

                //get map for the new PS
                currentPsId = op.ParentId;
                currentOps = currentMap.get(currentPsId);
                if (currentOps == null) {
                    this.unexpectedPsIds.add(currentPsId);
                    continue;
                }
            } else if (currentOps == null) {
                continue;
            }
            ObjectPermissions existingOp = currentOps.put(op.SobjectType, this.getDummyObjectPermissions(op));
            if (existingOp != null) {
                this.duplicatePerms.add(op);
                currentOps.put(op.SobjectType, this.getDummyObjectPermissions(mergeObjectPermissions(op, existingOp)));
            }
        }

        if (!isProfile) {
            // It's neccessary to do comparison processing for as many records as we can, given CPU limits,
            // in order to free heap-space and reduce size of the object being serialized between executions
            if (this.objectProcessor == null) {
                this.objectProcessor = new ObjectPermissionsComparisonProcessor(this, new AsyncProcessor.CannibalizingListIterator(this.readyToCompare));
            }
            this.objectProcessor.executeSync();
        }
    }

    public void compareObjectPermissions(Id psId) {
        Map<String, ObjectPermissions> psMap = this.psOps.get(psId);
        Map<Id, DiffCounter> diffMap = this.result.get(psId);
        if (diffMap == null) {
            diffMap = new Map<Id, DiffCounter>();
            this.result.put(psId, diffMap);
        }

        for (Id prfId : this.profileOps.keySet()) {
            DiffCounter diff = diffMap.get(prfId);
            if (diff == null) {
                diff = new DiffCounter();
                diffMap.put(prfId, diff);
            }

            Map<String, ObjectPermissions> prfMap = this.profileOps.get(prfId);
            Set<String> objNames = new Set<String>(prfMap.keySet());
            objNames.addAll(psMap.keySet());
            for (String objName : objNames) {
                diff.compareObjectPermissions(prfMap.get(objName), psMap.get(objName));
            }
        }
        this.psOps.remove(psId); // to prevent re-processing of these ObjectPermissions at finish3(), and to free heap-space
    }

    public void finish3() {
        // process any remaining object permissions (e.g. that ended on the boundary of a batch execution, or that didn't have any object permissions)
        for (Id psId : this.psOps.keySet()) {
            if (!this.readyToCompare.contains(psId)) {
                this.readyToCompare.add(psId);
            }
        }
        if (this.objectProcessor == null) {
            this.objectProcessor = new ObjectPermissionsComparisonProcessor(this, new AsyncProcessor.CannibalizingListIterator(this.readyToCompare));
        }
        this.objectProcessor.executeSync();
        this.objectProcessor.resetTimingCounters();
        this.objectProcessor.enqueue();
    }

    public String query4() {
        for (PermissionSet ps : this.profiles) {
            this.profileFps.put(ps.Id, new Map<String, Map<String, FieldPermissions>>());
        }
        return '''
            SELECT ParentId, SobjectType, Field, PermissionsRead, PermissionsEdit
            FROM FieldPermissions
            WHERE ParentId IN :parentIds
            ORDER BY ParentId ASC, SobjectType ASC, Field ASC
        ''';
    }

    public String query5() {
        for (PermissionSet ps : this.pss) {
            this.psFps.put(ps.Id, new Map<String, Map<String, FieldPermissions>>());
        }
        return '''
            SELECT ParentId, SobjectType, Field, PermissionsRead, PermissionsEdit
            FROM FieldPermissions
            WHERE ParentId IN :parentIds
            ORDER BY ParentId ASC, SobjectType ASC, Field ASC
        ''';
    }

    public void execute4(List<FieldPermissions> fldPerms) {
        this.processFieldPermissions(true, fldPerms);
    }

    public void execute5(List<FieldPermissions> fldPerms) {
        this.processFieldPermissions(false, fldPerms);
    }

    public void processFieldPermissions(Boolean isProfile, List<FieldPermissions> fldPerms) {
        Map<Id, Map<String, Map<String, FieldPermissions>>> currentMap = isProfile ? this.profileFps : this.psFps;

        // relying on the sorting of FieldPermissions by ParentId and SsbjectType, so we don't need to re-fetch the same map with each iteration
        Map<String, Map<String, FieldPermissions>> currentFps;
        Map<String, FieldPermissions> currentSObjFps;
        Id currentPsId = null;
        String currentSObj = null;
        for (FieldPermissions fp : fldPerms) {
            if (fp.ParentId != currentPsId) {
                if (currentFps != null && !isProfile) {
                    this.readyToCompare.add(currentPsId);
                }

                // get map for the new PS
                currentPsId = fp.ParentId;
                currentSObjFps = null;
                currentSObj = null;
                currentFps = currentMap.get(currentPsId);
                if (currentFps == null) {
                    this.unexpectedPsIds.add(currentPsId);
                    continue;
                }
            } else if (currentFps == null) {
                continue;
            }
            if (fp.SobjectType != currentSObj) {
                currentSObj = fp.SobjectType;
                currentSObjFps = currentFps.get(currentSObj);
                if (currentSObjFps == null) {
                    currentSObjFps = new Map<String, FieldPermissions>();
                    currentFps.put(currentSObj, currentSObjFps);
                }
            }
            
            List<String> fieldSplit = fp.Field.split('\\.', 2);
            String fieldName = fieldSplit.get(fieldSplit.size() - 1);

            FieldPermissions existingFp = currentSObjFps.put(fieldName, this.getDummyFieldPermissions(fp));
            if (existingFp != null) {
                this.duplicatePerms.add(fp);
                currentSObjFps.put(fieldName, this.getDummyFieldPermissions(mergeFieldPermissions(fp, existingFp)));
            }
        }

        if (!isProfile) {
            // It's neccessary to do comparison processing for as many records as we can, given CPU limits,
            // in order to free heap-space and reduce size of the object being serialized between executions
            if (this.fieldProcessor == null) {
                this.fieldProcessor = new FieldPermissionsComparisonProcessor(this, new AsyncProcessor.CannibalizingListIterator(this.readyToCompare));
            }
            this.fieldProcessor.executeSync();
        }
    }

    public void compareFieldPermissions(Id psId) {
        Map<String, Map<String, FieldPermissions>> psMap = this.psFps.get(psId);
        Map<Id, DiffCounter> diffMap = this.result.get(psId);
        for (Id prfId : this.profileFps.keySet()) {
            DiffCounter diff = diffMap.get(prfId);
            Map<String, Map<String, FieldPermissions>> prfMap = this.profileFps.get(prfId);
            Set<String> objNames = new Set<String>(prfMap.keySet());
            objNames.addAll(psMap.keySet());
            for (String objName : objNames) {
                Map<String, FieldPermissions> prfFieldMap = prfMap.get(objName);
                Map<String, FieldPermissions> psFieldMap = psMap.get(objName);
                Set<String> fieldNames = new Set<String>();
                if (prfFieldMap != null) fieldNames.addAll(prfFieldMap.keySet());
                if (psFieldMap != null) fieldNames.addAll(psFieldMap.keySet());
                for (String fieldName : fieldNames) {
                    System.debug(objName + '.' + fieldName);
                    diff.compareFieldPermissions(prfFieldMap?.get(fieldName), psFieldMap?.get(fieldName));
                }
            }
        }
        this.psFps.remove(psId); // to prevent re-processing of these FieldPermissions at finish5(), and to free heap-space
    }

    public void finish5() {
        if (this.unexpectedPsIds.size() > 0) {
            Logger.debug('PermissionsGridProfileVsPs: unexpected PermissionSet Ids').setRecord(this.unexpectedPsIds);
            this.unexpectedPsIds.clear();
        }
        if (this.duplicatePerms.size() > 0) {
            Logger.debug('PermissionsGridProfileVsPs: unexpected duplicate object/field permissions').setRecord(this.duplicatePerms);
            this.duplicatePerms.clear();
        }

        // process any remaining field permissions (e.g. that ended on the boundary of a batch execution, or that didn't have any field permissions)
        for (Id psId : this.psFps.keySet()) {
            if (!this.readyToCompare.contains(psId)) {
                this.readyToCompare.add(psId);
            }
        }

        if (this.fieldProcessor == null) {
            this.fieldProcessor = new FieldPermissionsComparisonProcessor(this, new AsyncProcessor.CannibalizingListIterator(this.readyToCompare));
        }
        this.fieldProcessor.executeSync();
        this.fieldProcessor.enqueue();
    }

    // called by fieldProcessor after it finishes
    public void sortComparisonResults() {
        List<Object> psIds = new List<Object>();

        for (Id psId : this.result.keySet()) {
            psIds.add(psId);
        }

        for (PermissionSet profilePs : this.profiles) {
            this.resultSorting.put(profilePs.Id, new List<Double> { 0.0, 0.0, 0.0 });
        }

        SortingProcessor sortingProc = new SortingProcessor(this, psIds.iterator());
        sortingProc.executeSync();
        Id jobId = sortingProc.enqueue();
        Logger.debug('PermissionsGridProfileVsPs.sortComparisonResults (step 6), JobId ' + jobId);
        Logger.saveLog();
    }

    // called by resultSortingProc for each psId during execute
    public void calcSorting(Id psId) {
        Double sum1 = 0.0, sum2 = 0.0, sum3 = 0.0;
        Map<Id, DiffCounter> psDiffs = this.result.get(psId);
        for (Id profileId : psDiffs.keySet()) {
            DiffCounter diff = psDiffs.get(profileId);
            List<Double> sorting = diff.calcSorting();
            sum1 += sorting.get(0);
            sum2 += sorting.get(1);
            sum3 += sorting.get(2);

            List<Double> profileSums = this.resultSorting.get(profileId);
            profileSums.set(0, profileSums.get(0) + sorting.get(0));
            profileSums.set(1, profileSums.get(1) + sorting.get(1));
            profileSums.set(2, profileSums.get(2) + sorting.get(2));
        }
        this.resultSorting.put(psId, new List<Double> {sum1, sum2, sum3});
    }

    // called by resultSortingProc after it finishes
    public void processOutput() {
        Comparator<SObject> compare = new DoubleListComparator(this.resultSorting);
        this.pss.sort(compare);
        this.profiles.sort(compare);

        this.addPermissionSetHeaders();
        OutputProcessor outputProc = new OutputProcessor(this, ((List<Object>)this.pss).iterator());
        outputProc.executeSync();
        Id jobId = outputProc.enqueue();
        Logger.debug('PermissionsGridProfileVsPs.processOutput (step 7), JobId ' + jobId);
        Logger.saveLog();
    }

    // called by outputProc for each PermissionSet during execute
    public void processOutputPermissionSet(PermissionSet ps) {
        Map<Id, DiffCounter> diffMap = this.result.remove(ps.Id); // remove to free heap-space
        List<Object> sumRow = new List<Object>();
        List<Object> psRow = new List<Object>();
        List<Object> profileRow = new List<Object>();
        PermissionsGridObjectsFields.addToHeaders(ps, sumRow, psRow, profileRow);
        sumRow.add(null);
        psRow.add('PS');
        profileRow.add('Profile');

        for (PermissionSet profile : this.profiles) {
            DiffCounter diff = diffMap.get(profile.Id);
            List<List<Object>> out = diff.getOutput();
            sumRow.addAll(out.get(0));
            psRow.addAll(out.get(1));
            profileRow.addAll(out.get(2));
        }
        this.output.add(sumRow);
        this.output.add(psRow);
        this.output.add(profileRow);
    }

    public void enqueueWriter() {
        Id jobId = new CSVWriter().writeToStaticResourceAsync(this.output, this, 'PermissionsGridProfileVsPs', this.staticResourceName, 'PermissionsGridProfileVsPs result', false);
        Logger.debug('PermissionsGridProfileVsPs.enqueueWriter (step 8), JobId ' + jobId);
        Logger.saveLog();
    }

    private abstract class StepProcessor extends AsyncProcessor.WithFinish {
        private final PermissionsGridProfileVsPs parent;
        private String className; //set by subclass

        private StepProcessor(PermissionsGridProfileVsPs parent, Iterator<Object> it) {
            super(parent, it);
            this.parent = parent;
        }

        protected abstract void iterate(Object obj);
        
        override public void execute(QueueableContext qc, AsyncIterator it) {
            try {
                for (Object obj : it) {
                    this.iterate(obj);
                }
            } catch (Exception e) {
                Logger.error('PermissionsGridProfileVsPs.' + this.className + '.execute', e);
                Logger.saveLog();
            }
        }

        override public void finish(QueueableContext qc) {
            try {
                this.parent.nextStep();
            } catch (Exception e) {
                Logger.error('PermissionsGridProfileVsPs.' + this.className + '.finish', e);
                Logger.saveLog();
            }
        }
    }

    private class ObjectPermissionsComparisonProcessor extends StepProcessor {
        private ObjectPermissionsComparisonProcessor(PermissionsGridProfileVsPs parent, Iterator<Object> it) {
            super(parent, it);
            this.className = 'ObjectPermissionsComparisonProcessor';
        }

        override public void iterate(Object psId) {
            this.parent.compareObjectPermissions((Id)psId);
        }
    }

    private class FieldPermissionsComparisonProcessor extends StepProcessor {
        private FieldPermissionsComparisonProcessor(PermissionsGridProfileVsPs parent, Iterator<Object> it) {
            super(parent, it);
            this.className = 'FieldPermissionsComparisonProcessor';
        }

        override public void iterate(Object psId) {
            this.parent.compareFieldPermissions((Id)psId);
        }
    }

    private class SortingProcessor extends StepProcessor {
        private SortingProcessor(PermissionsGridProfileVsPs parent, Iterator<Object> psIds) {
            super(parent, psIds);
            this.className = 'SortingProcessor';
        }

        override public void iterate(Object psId) {
            this.parent.calcSorting((Id)psId);
        }
    }

    private class OutputProcessor extends StepProcessor {
        private OutputProcessor(PermissionsGridProfileVsPs parent, Iterator<Object> pss) {
            super(parent, pss);
            this.className = 'OutputProcessor';
        }

        override public void iterate(Object ps) {
            this.parent.processOutputPermissionSet((PermissionSet)ps);
        }
    }

    public void addPermissionSetHeaders() {
        List<Object> names = new List<Object> {null, 'Profile:'};
        List<Object> extraRow = new List<Object> {'Permission Set', null};
        for (PermissionSet ps : this.profiles) {
            names.add(ps.Profile.Name);
            for (Integer i = 0; i < 11; i++) {
                names.add(null);
            }
            extraRow.add('Sum');
            extraRow.add('Object Sum');
            extraRow.add('Read');
            extraRow.add('Create');
            extraRow.add('Edit');
            extraRow.add('Delete');
            extraRow.add('ViewAllRecords');
            extraRow.add('ModifyAllRecords');
            extraRow.add('ViewAllFields');
            extraRow.add('Field Sum');
            extraRow.add('Read');
            extraRow.add('Edit');
        }
        this.output.add(names);
        this.output.add(extraRow);
    }

    private static final ObjectPermissions allFalseOp = new ObjectPermissions (
        PermissionsCreate = false,
        PermissionsRead = false,
        PermissionsEdit = false,
        PermissionsDelete = false,
        PermissionsViewAllRecords = false,
        PermissionsModifyAllRecords = false,
        PermissionsViewAllFields = false
    );

    private static final FieldPermissions allFalseFp = new FieldPermissions(
        PermissionsRead = false,
        PermissionsEdit = false
    );

    public static ObjectPermissions mergeObjectPermissions(ObjectPermissions op1, ObjectPermissions op2) {
        return new ObjectPermissions(
            Id = null,
            PermissionsCreate = op1.PermissionsCreate || op2.PermissionsCreate,
            PermissionsRead = op1.PermissionsRead || op2.PermissionsRead,
            PermissionsEdit = op1.PermissionsEdit || op2.PermissionsEdit,
            PermissionsDelete = op1.PermissionsDelete || op2.PermissionsDelete,
            PermissionsViewAllRecords = op1.PermissionsViewAllRecords || op2.PermissionsViewAllRecords,
            PermissionsModifyAllRecords = op1.PermissionsModifyAllRecords || op2.PermissionsModifyAllRecords,
            PermissionsViewAllFields = op1.PermissionsViewAllFields || op2.PermissionsViewAllFields
        );
    }

    public static FieldPermissions mergeFieldPermissions(FieldPermissions fp1, FieldPermissions fp2) {
        return new FieldPermissions(
            Id = null,
            PermissionsRead = fp1.PermissionsRead || fp2.PermissionsRead,
            PermissionsEdit = fp1.PermissionsEdit || fp2.PermissionsEdit
        );
    }

    public class DiffCounter {
        public Integer psObjectRead = 0;
        public Integer psObjectCreate = 0;
        public Integer psObjectEdit = 0;
        public Integer psObjectDelete = 0;
        public Integer psObjectViewAllRecords = 0;
        public Integer psObjectModifyAllRecords = 0;
        public Integer psObjectViewAllFields = 0;

        public Integer psFieldRead = 0;
        public Integer psFieldEdit = 0;

        public Integer profileObjectRead = 0;
        public Integer profileObjectCreate = 0;
        public Integer profileObjectEdit = 0;
        public Integer profileObjectDelete = 0;
        public Integer profileObjectViewAllRecords = 0;
        public Integer profileObjectModifyAllRecords = 0;
        public Integer profileObjectViewAllFields = 0;

        public Integer profileFieldRead = 0;
        public Integer profileFieldEdit = 0;

        public List<List<Integer>> output;
        public List<Double> sorting;

        public List<List<Integer>> getOutput() {
            if (this.output != null) {
                return this.output;
            }
            return calcOutput();
        }
        
        public List<Double> getSorting() {
            if (this.sorting != null) {
                return this.sorting;
            }
            return calcSorting();
        }

        public List<List<Integer>> calcOutput() {
            Integer psObjectSum = psObjectRead + psObjectCreate + psObjectEdit + psObjectDelete + psObjectViewAllRecords + psObjectModifyAllRecords + psObjectViewAllFields;
            Integer psFieldSum = psFieldRead + psFieldEdit;
            Integer psSum = psObjectSum + psFieldSum;

            Integer profileObjectSum = profileObjectRead + profileObjectCreate + profileObjectEdit + profileObjectDelete + profileObjectViewAllRecords + profileObjectModifyAllRecords + profileObjectViewAllFields;
            Integer profileFieldSum = profileFieldRead + profileFieldEdit;
            Integer profileSum = profileObjectSum + profileFieldSum;

            return this.output = new List<List<Integer>> {
                new List<Integer> { psSum + profileSum, psObjectSum + profileObjectSum, psObjectRead + profileObjectRead, psObjectCreate + profileObjectCreate, psObjectEdit + profileObjectEdit, psObjectDelete + profileObjectDelete, psObjectViewAllRecords + profileObjectViewAllRecords,
                                    psObjectModifyAllRecords + profileObjectModifyAllRecords, psObjectViewAllFields + profileObjectViewAllFields, psFieldSum + profileFieldSum, psFieldRead + profileFieldRead, psFieldEdit + profileFieldEdit },
                new List<Integer> { psSum, psObjectSum, psObjectRead, psObjectCreate, psObjectEdit, psObjectDelete, psObjectViewAllRecords, psObjectModifyAllRecords, psObjectViewAllFields, psFieldSum, psFieldRead, psFieldEdit },
                new List<Integer> { profileSum, profileObjectSum, profileObjectRead, profileObjectCreate, profileObjectEdit, profileObjectDelete, profileObjectViewAllRecords, profileObjectModifyAllRecords, profileObjectViewAllFields, profileFieldSum, profileFieldRead, profileFieldEdit }
            };
        }

        public List<Double> calcSorting() {
            List<Integer> sums = getOutput().get(0);
            return this.sorting = new List<Double> {
                // We add one to the sums because log(0) is undefined
                Math.log(sums.get(0) + 1), //overall sum
                Math.log(sums.get(1) + 1), // object sum
                Math.log(sums.get(9) + 1) //field sum
            };
        }

        public void compareObjectPermissions(ObjectPermissions prf, ObjectPermissions ps) {
            if (prf == null) {
                prf = allFalseOp;
            }
            if (ps == null) {
                ps = allFalseOp;
            }

            if (prf.PermissionsRead) {
                if (!ps.PermissionsRead) {
                    this.profileObjectRead++;
                }
            } else if (ps.PermissionsRead) {
                this.psObjectRead++;
            }

            if (prf.PermissionsCreate) {
                if (!ps.PermissionsCreate) {
                    this.profileObjectCreate++;
                }
            } else if (ps.PermissionsCreate) {
                this.psObjectCreate++;
            }

            if (prf.PermissionsEdit) {
                if (!ps.PermissionsEdit) {
                    this.profileObjectEdit++;
                }
            } else if (ps.PermissionsEdit) {
                this.psObjectEdit++;
            }

            if (prf.PermissionsDelete) {
                if (!ps.PermissionsDelete) {
                    this.profileObjectDelete++;
                }
            } else if (ps.PermissionsDelete) {
                this.psObjectDelete++;
            }

            if (prf.PermissionsViewAllRecords) {
                if (!ps.PermissionsViewAllRecords) {
                    this.profileObjectViewAllRecords++;
                }
            } else if (ps.PermissionsViewAllRecords) {
                this.psObjectViewAllRecords++;
            }

            if (prf.PermissionsModifyAllRecords) {
                if (!ps.PermissionsModifyAllRecords) {
                    this.profileObjectModifyAllRecords++;
                }
            } else if (ps.PermissionsModifyAllRecords) {
                this.psObjectModifyAllRecords++;
            }

            if (prf.PermissionsViewAllFields) {
                if (!ps.PermissionsViewAllFields) {
                    this.profileObjectViewAllFields++;
                }
            } else if (ps.PermissionsViewAllFields) {
                this.psObjectViewAllFields++;
            }
        }

        public void compareFieldPermissions(FieldPermissions prf, FieldPermissions ps) {
            if (prf == null) {
                prf = allFalseFp;
            }
            if (ps == null) {
                ps = allFalseFp;
            }

            if (prf.PermissionsRead) {
                if (!ps.PermissionsRead) {
                    this.profileFieldRead++;
                }
            } else if (ps.PermissionsRead) {
                this.psFieldRead++;
            }

            if (prf.PermissionsEdit) {
                if (!ps.PermissionsEdit) {
                    this.profileFieldEdit++;
                }
            } else if (ps.PermissionsEdit) {
                this.psFieldEdit++;
            }
        }
    }

    public ObjectPermissions getDummyObjectPermissions(ObjectPermissions op) {
        Integer hash = 0;
        if (op.PermissionsRead) hash |= 1;
        if (op.PermissionsCreate) hash |= 2;
        if (op.PermissionsEdit) hash |= 4;
        if (op.PermissionsDelete) hash |= 8;
        if (op.PermissionsViewAllRecords) hash |= 16;
        if (op.PermissionsModifyAllRecords) hash |= 32;
        if (op.PermissionsViewAllFields) hash |= 64;
        ObjectPermissions dummy = this.dummyOps.get(hash);
        if (dummy == null) {
            dummy = new ObjectPermissions (
                PermissionsRead = op.PermissionsRead,
                PermissionsCreate = op.PermissionsCreate,
                PermissionsEdit = op.PermissionsEdit,
                PermissionsDelete = op.PermissionsDelete,
                PermissionsViewAllRecords = op.PermissionsViewAllRecords,
                PermissionsModifyAllRecords = op.PermissionsModifyAllRecords,
                PermissionsViewAllFields = op.PermissionsViewAllFields
            );
            this.dummyOps.put(hash, dummy);
        }
        return dummy;
    }

    public FieldPermissions getDummyFieldPermissions(FieldPermissions fp) {
        Integer hash = 0;
        if (fp.PermissionsRead) hash |= 1;
        if (fp.PermissionsEdit) hash |= 2;
        FieldPermissions dummy = this.dummyFps.get(hash);
        if (dummy == null) {
            dummy = new FieldPermissions(
                PermissionsRead = fp.PermissionsRead,
                PermissionsEdit = fp.PermissionsEdit
            );
            this.dummyFps.put(hash, dummy);
        }
        return dummy;
    }

    public class DoubleListComparator implements Comparator<SObject> {
        public final Map<Id, List<Double>> resultSorting;

        public DoubleListComparator(Map<Id, List<Double>> resultSorting) {
            this.resultSorting = resultSorting;
        }

        public Integer compare(SObject obj1, SObject obj2) {
            List<Double> list1 = this.resultSorting.get(obj1.Id);
            List<Double> list2 = this.resultSorting.get(obj2.Id);
            for (Integer i = 0; i < 3; i++) {
                Double val1 = list1.get(i);
                Double val2 = list2.get(i);

                //NaN check
                if (val1 != val1 || val2 != val2) throw new IllegalArgumentException('NaN value provided');

                if (val1 < val2) return -1;
                if (val2 < val1) return 1;
            }
            return 0;
        }
    }
}