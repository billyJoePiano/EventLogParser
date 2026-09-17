/**
 * @description       : Generic class with utility methods for correlating logs over multiple transactions,
 *                         i.e. in a Batchable or Queueable job.
 *                      Tested by BatchableLoggerSaveListenerTest, ApexUnexpectedExceptionParsingJobTest, and others
 */
global virtual without sharing class BatchableLogger {
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
}