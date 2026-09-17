/**
 * @description       : Generic class with utility methods for logging DB transactions
 *                      For example of implementation, see: ApexUnexpectedExceptionParsingJob
 */
global class DmlLogger {
    global class ProcessedDatabaseDmlResults {
        global final List<Object> successfulDmls = new List<Object>();
        global final List<FailedDml> failedDmls = new List<FailedDml>();
    }

    global abstract class FailedDml {
        global final Integer index;
        global final Object forObjOrWrapper;
        global final List<DatabaseError> errors = new List<DatabaseError>();

        global FailedDml(Integer index, Object forObjOrWrapper) {
            this.index = index;
            this.forObjOrWrapper = forObjOrWrapper;
        }

        global String errorsToJson() {
            return JSON.serializePretty(errors);
        }
    }

    global class FailedSave extends FailedDml {
        global final Database.SaveResult saveResult;

        global FailedSave(Integer index, Object forObjOrWrapper, Database.SaveResult saveResult) {
            super(index, forObjOrWrapper);
            this.saveResult = saveResult;
            for (Database.Error err : saveResult.getErrors()) {
                this.errors.add(new DatabaseError(err));
            }
        }
    }

    global class FailedUpsert extends FailedDml {
        global final Database.UpsertResult upsertResult;

        global FailedUpsert(Integer index, Object forObjOrWrapper, Database.UpsertResult upsertResult) {
            super(index, forObjOrWrapper);
            this.upsertResult = upsertResult;
            for (Database.Error err : upsertResult.getErrors()) {
                this.errors.add(new DatabaseError(err));
            }
        }
    }

    //For easy JSON serialization
    global class DatabaseError {
        global final String message;
        global final String statusCode;
        global final List<String> fields;

        global DatabaseError(Database.Error err) {
            this.message = err.getMessage();
            this.statusCode = String.valueOf(err.getStatusCode());
            this.fields = err.getFields();
        }
    }

    global static ProcessedDatabaseDmlResults processAndLogDatabaseSaveResults(String classNameAndMethod, SObjectType soType, List<Database.SaveResult> saveResults, List<Object> objsOrWrappersToFilter) {
        ProcessedDatabaseDmlResults processedResults = processDatabaseSaveResults(saveResults, objsOrWrappersToFilter);
        logProcessedDmlResults(classNameAndMethod, soType, processedResults);
        return processedResults;
    }

    global static ProcessedDatabaseDmlResults processAndLogDatabaseSaveResults(String classNameAndMethod, SObjectType soType, List<Database.SaveResult> saveResults, List<Object> objsOrWrappersToFilter, SObjectHandler handler) {
        ProcessedDatabaseDmlResults processedResults = processDatabaseSaveResults(saveResults, objsOrWrappersToFilter);
        logProcessedDmlResults(classNameAndMethod, soType, processedResults, handler);
        return processedResults;
    }
    
    global static ProcessedDatabaseDmlResults processAndLogDatabaseUpsertResults(String classNameAndMethod, SObjectType soType, List<Database.UpsertResult> upsertResults, List<Object> objsOrWrappersToFilter) {
        ProcessedDatabaseDmlResults processedResults = processDatabaseUpsertResults(upsertResults, objsOrWrappersToFilter);
        logProcessedDmlResults(classNameAndMethod, soType, processedResults);
        return processedResults;
    }

    global static ProcessedDatabaseDmlResults processAndLogDatabaseUpsertResults(String classNameAndMethod, SObjectType soType, List<Database.UpsertResult> upsertResults, List<Object> objsOrWrappersToFilter, SObjectHandler handler) {
        ProcessedDatabaseDmlResults processedResults = processDatabaseUpsertResults(upsertResults, objsOrWrappersToFilter);
        logProcessedDmlResults(classNameAndMethod, soType, processedResults, handler);
        return processedResults;
    }

    global static ProcessedDatabaseDmlResults processDatabaseSaveResults(List<Database.SaveResult> saveResults, List<Object> objsOrWrappersToFilter) {
        if (saveResults.size() != objsOrWrappersToFilter.size()) {
            throw new IllegalArgumentException('Expected both lists to be of identical size.  saveResults.size(): ' + saveResults.size()
                                               +  ', objsOrWrappersToFilter.size(): ' + objsOrWrappersToFilter.size());
        }
        ProcessedDatabaseDmlResults processedResults = new ProcessedDatabaseDmlResults();
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult sr = saveResults.get(i);
            if (sr.isSuccess()) {
                processedResults.successfulDmls.add(objsOrWrappersToFilter.get(i));
            } else {
                processedResults.failedDmls.add(new FailedSave(i, objsOrWrappersToFilter.get(i), sr));
            }
        }
        return processedResults;
    }

    global static ProcessedDatabaseDmlResults processDatabaseUpsertResults(List<Database.UpsertResult> upsertResults, List<Object> objsOrWrappersToFilter) {
        if (upsertResults.size() != objsOrWrappersToFilter.size()) {
            throw new IllegalArgumentException('Expected both lists to be of identical size.  upsertResults.size(): ' + upsertResults.size()
                                               +  ', objsOrWrappersToFilter.size(): ' + objsOrWrappersToFilter.size());
        }
        ProcessedDatabaseDmlResults processedResults = new ProcessedDatabaseDmlResults();
        for (Integer i = 0; i < upsertResults.size(); i++) {
            Database.UpsertResult ur = upsertResults.get(i);
            if (ur.isSuccess()) {
                processedResults.successfulDmls.add(objsOrWrappersToFilter.get(i));
            } else {
                processedResults.failedDmls.add(new FailedUpsert(i, objsOrWrappersToFilter.get(i), ur));
            }
        }
        return processedResults;
    }

    global static void logProcessedDmlResults(String classNameAndMethod, SObjectType soType, ProcessedDatabaseDmlResults processedResults) {
        logProcessedDmlResults(classNameAndMethod, soType, processedResults, new DefaultSObjectHandler());
    }

    global static void logProcessedDmlResults(String classNameAndMethod, SObjectType soType, ProcessedDatabaseDmlResults processedResults, SObjectHandler handler) {
        logProcessedDmlResults(classNameAndMethod, soType, processedResults.successfulDmls, processedResults.failedDmls, handler);
    }

    global static void logProcessedDmlResults(String classNameAndMethod, SObjectType soType, List<Object> successfulDmls, List<FailedDml> failedDmls, SObjectHandler handler) {
        if (successfulDmls == null || failedDmls == null || handler == null) {
            throw new NullPointerException();
        }
        String soTypeStr = soType.getDescribe().getName();

        List<Id> successfulIds = new List<Id>();
        for (Object forObj : successfulDmls) {
            successfulIds.add(handler.getSObject(forObj).Id);
        }

        if (failedDmls.size() < 1) {
            Logger.debug(classNameAndMethod + ': full success inserting/updating all ' + successfulDmls.size() + ' ' + soTypeStr + ' records')
                .setRecord(successfulIds);
        } else {
            if (successfulDmls.size() > 0) {
                Integer sum = successfulDmls.size() + failedDmls.size();
                Logger.warn(classNameAndMethod + ': partial success inserting/updating ' + sum + ' ' + soTypeStr + ' records.  '
                            + successfulDmls.size() + ' successful, ' + failedDmls.size() + ' failed')
                    .setRecord(successfulIds);
            } else {
                Logger.error(classNameAndMethod + ': full failure inserting all ' + failedDmls.size() + ' ' + soTypeStr + ' records');
            }
            for (FailedDml failure : failedDmls) {
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
    global interface SObjectHandler {
        SObject getSObject(Object forObjOrWrapper);
        void setRecord(LogEntryEventBuilder logBuilder, Object forObjOrWrapper);
    }

    // For custom classes that 'wrap' an SObject with additional information about it 
    global interface SObjectWrapper {
        SObject getSObject();
        void setRecord(LogEntryEventBuilder logBuilder);
    }

    // Assumes forObjOrWrapper is already an SObject, not some kind of wrapper, and doesn't need any modifications before running logEntryEventBuilder.setRecord(sObject)
    global virtual class DefaultSObjectHandler implements SObjectHandler {        
        global SObject getSObject(Object forObjOrWrapper) {
            return (SObject)forObjOrWrapper;
        }

        global void setRecord(LogEntryEventBuilder logBuilder, Object forObjOrWrapper) {
            logBuilder.setRecord((SObject)forObjOrWrapper);
        }
    }

    //Assumes forObjOrWrapper implements the ObjectWrapper interface
    global virtual class SObjectWrapperHandler implements SObjectHandler {
        global SObject getSObject(Object forObjOrWrapper) {
            return ((SObjectWrapper)forObjOrWrapper).getSObject();
        }

        global void setRecord(LogEntryEventBuilder logBuilder, Object forObjOrWrapper) {
            ((SObjectWrapper)forObjOrWrapper).setRecord(logBuilder);
        }
    }
}