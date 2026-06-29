public abstract class BatchableLogger implements Database.Stateful {
    public final String loggerTransactionId;

    public BatchableLogger() {
        this(Logger.getTransactionId());
    }

    public BatchableLogger(String loggerTransactionId) {
        this.loggerTransactionId = loggerTransactionId;
    }

    // IMPORTANT: Subclasses MUST call setLoggerTransactionId() at the very start of each transaction (i.e. in start, execute, and finish methods)
    // Typically it should NOT be wrapped in try-catch, but all of the business logic should be wrapped in try-catch,
    // with a finally block that includes Logger.saveLog()
    public void setLoggerTransactionId() {
        try {
            Logger.setParentLogTransactionId(this.loggerTransactionId);
        } catch (Exception e) {
            Logger.error('BatchableLogged.setLoggerTransactionId: ' + this.loggerTransactionId, e);
        }
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