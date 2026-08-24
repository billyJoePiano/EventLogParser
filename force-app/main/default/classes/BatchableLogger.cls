/**
 * @description       : Generic class with utility methods for logging DB transactions in a Batchable or Queueable job.
 *                      For example of implementation, see: ApexUnexpectedExceptionParsingJob
 */
public virtual without sharing class BatchableLogger {
    public static final Integer CACHE_TTL = 3600; //3600 seconds = 1 hour
    
    @TestVisible
    private static final Set<String> savedTransactionIds = new Set<String>();
    private static final Set<BatchableLogger> loggers = new Set<BatchableLogger>();

    public static Cache.OrgPartition getPartition() {
        return Cache.Org.getPartition('local.BatchableLogger');
    }

    // See LoggerPlugin__mdt (custom metadata) record BatchableLogger_SaveListener, which installs the below inner-class as a custom plugin.
    public class SaveListener implements LoggerPlugin.Triggerable {
        public void execute(LoggerPlugin__mdt configuration, LoggerTriggerableContext input) {
            switch on input.triggerOperationType {
                when BEFORE_INSERT, BEFORE_UPDATE { }
                when else { return; }
            }
            if (input.sobjectType == Log__c.SObjectType || input.sobjectType == LogEntryEvent__e.SObjectType) {
                Cache.OrgPartition partition = getPartition();
                for (SObject log : input.triggerNew) {
                    String transactionId = (String)log.get('TransactionId__c');
                    if (transactionId != null) {
                        savedTransactionIds.add(transactionId);
                        partition.put(transactionId.replace('-', ''), true, CACHE_TTL);
                    }
                }
                for (BatchableLogger logger : loggers) {
                    if (!logger.confirmedExists && savedTransactionIds.contains(logger.loggerTransactionId)) {
                        logger.confirmedExists = true;
                    }
                }
            }
        }
    }

    private String loggerTransactionId;
    @TestVisible
    private Boolean confirmedExists; //flag which indicates whether the loggerTransactionId actually exists as a Log__c entry

    public BatchableLogger() {
        this(false);
    }

    public BatchableLogger(Boolean parentOnThisTransaction) {
        this(Logger.getTransactionId(), parentOnThisTransaction);
    }

    public BatchableLogger(BatchableLogger predecessor) {
        this(predecessor?.loggerTransactionId ?? Logger.getTransactionId(), predecessor?.confirmedExists ?? false);
    }

    public BatchableLogger(String loggerTransactionId) {
        this(loggerTransactionId, false);
    }

    private BatchableLogger(String loggerTransactionId, Boolean confirmedExists) {
        loggers.add(this);
        this.loggerTransactionId = loggerTransactionId;
        this.confirmedExists = confirmedExists;
        this.checkExists(false);
    }

    public String getLoggerTransactionId() {
        return this.loggerTransactionId;
    }

    // IMPORTANT: Subclasses MUST call setLoggerTransactionId() at the very start of each transaction (i.e. in start, execute, and finish methods)
    // Typically it should NOT be wrapped in try-catch, but all of the business logic should be wrapped in try-catch,
    // with a finally block that includes Logger.saveLog()
    public void setLoggerTransactionId() {
        try {
            loggers.add(this);
            if (this.checkExists(true)) {
                Logger.setParentLogTransactionId(this.loggerTransactionId);
            } else {
                // The original transaction Id was (probably) never used (barring a race condition).  Reset to the the current transaction id
                this.loggerTransactionId = Logger.getTransactionId();
                this.checkExists(false);
            }
        } catch (Exception e) {
            Logger.error('BatchableLogger.setLoggerTransactionId: ' + this.loggerTransactionId, e);
        }
    }

    private Boolean checkExists(Boolean queryDb) {
        if (this.confirmedExists) {
            return true;
        }
        if (savedTransactionIds.contains(this.loggerTransactionId)) {
            this.confirmedExists = true;
            return true;
        }
        
        /* There's a chance of a race condition here, between the timing of the PlatformEvent trigger which inserts the Log__c record,
         * and when the Batchable/Queueable Apex job runs after scheduling.
         * That's why it's preferable to use the 'parentOnThisTransaction' flag in the constructor, rather than rely on the below check
         * to catch a parent log entry that is saved *after* the BatchableLogger is serialized in Database.executeBatch(...) or System.enqueue(...)
         */
        Cache.OrgPartition partition = getPartition();
        String loggerIdNoDashes = this.loggerTransactionId.replace('-', '');
        if (partition.get(loggerIdNoDashes) == true) {
            partition.put(loggerIdNoDashes, true, CACHE_TTL); // refresh time-to-live
            savedTransactionIds.add(this.loggerTransactionId);
            this.confirmedExists = true;
            return true;
        }

        if (queryDb) {
            List<Log__c> parents = [SELECT Id, TransactionId__c FROM Log__c WHERE TransactionId__c = :this.loggerTransactionId WITH SYSTEM_MODE];
            for (Log__c log : parents) {
                if (log.TransactionId__c == this.loggerTransactionId) {
                    partition.put(loggerIdNoDashes, true, CACHE_TTL);
                    savedTransactionIds.add(this.loggerTransactionId);
                    this.confirmedExists = true;
                    return true;
                }
            }
        }
        // The original transaction Id was (probably) never used (barring a race condition)
        return false;
    }

    public class ProcessedDatabaseSaveResults {
        public final List<Object> successfulSaves = new List<Object>();
        public final List<FailedSave> failedSaves = new List<FailedSave>();
    }

    public class FailedSave {
        public final Integer index;
        public final Object forObjOrWrapper;
        public final Database.SaveResult saveResult;
        public final List<DatabaseError> errors = new List<DatabaseError>();

        public FailedSave(Integer index, Object forObjOrWrapper, Database.SaveResult saveResult) {
            this.index = index;
            this.forObjOrWrapper = forObjOrWrapper;
            this.saveResult = saveResult;
            for (Database.Error err : saveResult.getErrors()) {
                this.errors.add(new DatabaseError(err));
            }
        }

        public String errorsToJson() {
            return JSON.serializePretty(errors);
        }
    }

    //For easy JSON serialization
    public class DatabaseError {
        public final String message;
        public final String statusCode;
        public final List<String> fields;

        public DatabaseError(Database.Error err) {
            this.message = err.getMessage();
            this.statusCode = String.valueOf(err.getStatusCode());
            this.fields = err.getFields();
        }
    }

    virtual public ProcessedDatabaseSaveResults processAndLogDatabaseSaveResults(String classNameAndMethod, SObjectType soType, List<Database.SaveResult> saveResults, List<Object> objsOrWrappersToFilter) {
        ProcessedDatabaseSaveResults processedSaveResults = processDatabaseSaveResults(saveResults, objsOrWrappersToFilter);
        logProcessedSaveResults(classNameAndMethod, soType, processedSaveResults);
        return processedSaveResults;
    }

    virtual public ProcessedDatabaseSaveResults processAndLogDatabaseSaveResults(String classNameAndMethod, SObjectType soType, List<Database.SaveResult> saveResults, List<Object> objsOrWrappersToFilter, SObjectHandler handler) {
        ProcessedDatabaseSaveResults processedSaveResults = processDatabaseSaveResults(saveResults, objsOrWrappersToFilter);
        logProcessedSaveResults(classNameAndMethod, soType, processedSaveResults, handler);
        return processedSaveResults;
    }

    virtual public ProcessedDatabaseSaveResults processDatabaseSaveResults(List<Database.SaveResult> saveResults, List<Object> objsOrWrappersToFilter) {
        if (saveResults.size() != objsOrWrappersToFilter.size()) {
            throw new IllegalArgumentException('Expected both lists to be of identical size.  saveResults.size(): ' + saveResults.size()
                                               +  ', objsOrWrappersToFilter.size(): ' + objsOrWrappersToFilter.size());
        }
        ProcessedDatabaseSaveResults processedResults = new ProcessedDatabaseSaveResults();
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult sr = saveResults.get(i);
            if (sr.isSuccess()) {
                processedResults.successfulSaves.add(objsOrWrappersToFilter.get(i));
            } else {
                processedResults.failedSaves.add(new FailedSave(i, objsOrWrappersToFilter.get(i), sr));
            }
        }
        return processedResults;
    }

    virtual public void logProcessedSaveResults(String classNameAndMethod, SObjectType soType, ProcessedDatabaseSaveResults processedResults) {
        this.logProcessedSaveResults(classNameAndMethod, soType, processedResults, new DefaultSObjectHandler());
    }

    virtual public void logProcessedSaveResults(String classNameAndMethod, SObjectType soType, ProcessedDatabaseSaveResults processedResults, SObjectHandler handler) {
        this.logProcessedSaveResults(classNameAndMethod, soType, processedResults.successfulSaves, processedResults.failedSaves, handler);
    }

    virtual public void logProcessedSaveResults(String classNameAndMethod, SObjectType soType, List<Object> successfulSaves, List<FailedSave> failedSaves, SObjectHandler handler) {
        if (successfulSaves == null || failedSaves == null || handler == null) {
            throw new NullPointerException();
        }
        String soTypeStr = soType.getDescribe().getName();

        List<Id> successfulIds = new List<Id>();
        for (Object forObj : successfulSaves) {
            successfulIds.add(handler.getSObject(forObj).Id);
        }

        if (failedSaves.size() < 1) {
            Logger.info(classNameAndMethod + ': full success inserting all ' + successfulSaves.size() + ' ' + soTypeStr + ' records')
                .setRecord(successfulIds);
        } else {
            if (successfulSaves.size() > 0) {
                Integer sum = successfulSaves.size() + failedSaves.size();
                Logger.warn(classNameAndMethod + ': partial success inserting ' + sum + ' ' + soTypeStr + ' records.  '
                            + successfulSaves.size() + ' successful, ' + failedSaves.size() + ' failed')
                    .setRecord(successfulIds);
            } else {
                Logger.error(classNameAndMethod + ': full failure inserting all ' + failedSaves.size() + ' ' + soTypeStr + ' records');
            }
            for (FailedSave failure : failedSaves) {
                SObject obj = handler.getSObject(failure.forObjOrWrapper);
                LogEntryEventBuilder logBuilder = Logger.error('Failed to insert ' + obj.getSObjectType().getDescribe().getName()
                                                               + '\n' + failure.errorsToJson());
                handler.setRecord(logBuilder, failure.forObjOrWrapper);
            }
        }
    }

    /* These interfaces and handlers are intended to work with a variety of wrappers and object types, and provide custom logging behavior.
     * When not using SObjects directly (e.g. a wrapper class) the caller must submit a handler that knows how to properly cast the wrapper
     * without throwing a ClassCastException.
     * 
     * These handlers can be useful for several different purposes:
     *   - For doing any custom pre-processing on an SObject before serializing a full sObject into the logger via logEntryEventBuilder.setRecord(sObject) after an insert error
     *         (e.g. removing very long fields)
     *   - For handling custom wrapper classes, e.g. a class containing a reference to the inserted SObjet as well as a list of child objects to be inserted afterwards
     *   - For custom logging behavior in the event of insert errors, by overriding setRecord
     */
    public interface SObjectHandler {
        SObject getSObject(Object forObjOrWrapper);
        void setRecord(LogEntryEventBuilder logBuilder, Object forObjOrWrapper);
    }

    // For custom classes that 'wrap' an SObject with additional information about it 
    public interface SObjectWrapper {
        SObject getSObject();
        void setRecord(LogEntryEventBuilder logBuilder);
    }

    // Assumes forObjOrWrapper is already an SObject, not some kind of wrapper, and doesn't need any modifications before running logEntryEventBuilder.setRecord(sObject)
    virtual public class DefaultSObjectHandler implements SObjectHandler {        
        public SObject getSObject(Object forObjOrWrapper) {
            return (SObject)forObjOrWrapper;
        }

        public void setRecord(LogEntryEventBuilder logBuilder, Object forObjOrWrapper) {
            logBuilder.setRecord((SObject)forObjOrWrapper);
        }
    }

    //Assumes forObjOrWrapper implements the ObjectWrapper interface
    virtual public class SObjectWrapperHandler implements SObjectHandler {
        public SObject getSObject(Object forObjOrWrapper) {
            return ((SObjectWrapper)forObjOrWrapper).getSObject();
        }

        public void setRecord(LogEntryEventBuilder logBuilder, Object forObjOrWrapper) {
            ((SObjectWrapper)forObjOrWrapper).setRecord(logBuilder);
        }
    }
}