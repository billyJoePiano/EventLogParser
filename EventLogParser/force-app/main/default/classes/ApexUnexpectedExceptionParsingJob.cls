public without sharing class ApexUnexpectedExceptionParsingJob extends BatchableLogger implements Schedulable, Database.Batchable<EventLogFile>, Database.Stateful {
    /* QueryMode enum specifies how to query for new EventLogFiles
     *
     * AFTER_MOST_RECENT is the default and most efficient mode, but may miss older EventLogFiles which were never added
     *                  (e.g. blocked by parsing errors which have since been fixed)
     * 
     * ID_NOT_YET_PARSED is less efficient, but will be sure to include all unparsed EventLogFiles
     */
    public enum QueryMode { AFTER_MOST_RECENT, ID_NOT_YET_PARSED }
    public static final QueryMode AFTER_MOST_RECENT = QueryMode.AFTER_MOST_RECENT;
    public static final QueryMode ID_NOT_YET_PARSED = QueryMode.ID_NOT_YET_PARSED;

    public static Integer DEFAULT_BATCH_SIZE = 10;
    public static QueryMode DEFAULT_QUERY_MODE = AFTER_MOST_RECENT;

    public final QueryMode mode;
    public final Integer batchSize;
    public transient Boolean rethrowExceptions = false; // set to true when running synchronously, e.g. in anonymous execute

    public ApexUnexpectedExceptionParsingJob() {
        this(DEFAULT_QUERY_MODE, DEFAULT_BATCH_SIZE);
    }

    public ApexUnexpectedExceptionParsingJob(QueryMode mode) {
        this(mode, DEFAULT_BATCH_SIZE);
    }

    public ApexUnexpectedExceptionParsingJob(Integer batchSize) {
        this(DEFAULT_QUERY_MODE, batchSize);
    }

    public ApexUnexpectedExceptionParsingJob(QueryMode mode, Integer batchSize) {
        if (mode == null) {
            throw new NullPointerException();
        }
        this.mode = mode;
        this.batchSize = batchSize;
    }

    public void executeBatch() {
        this.execute((SchedulableContext)null);
    }

	public void execute(SchedulableContext sc) {
        try {
            if (this.batchSize != null) {
                Database.executeBatch(this, this.batchSize);
            } else {
                Database.executeBatch(this);
            }
        } catch (Exception e) {
            Logger.error('ApexUnexpectedExceptionParsingJob.execute(SchedulableContext)', e);
            Logger.saveLog();
        }
    }

    public void executeSync() {
        this.executeSync(true);
    }

    public void executeSync(Boolean rethrowExceptions) {
        this.rethrowExceptions = rethrowExceptions;
        List<EventLogFile> files = this.start((Database.BatchableContext)null);
        this.execute((Database.BatchableContext)null, files);
        this.finish((Database.BatchableContext)null);
    }

    public List<EventLogFile> start(Database.BatchableContext bc) {
        this.setLoggerTransactionId();
        try {
            switch on this.mode {
                when AFTER_MOST_RECENT {
                    return queryEventsAfterMostRecent();
                }
                when ID_NOT_YET_PARSED {
                    return queryEventsNotYetParsed();
                }
                when else {
                    throw new NullPointerException();
                }
            }
        } catch (Exception e) {
            Logger.error('ApexUnexpectedExceptionParsingJob.start query', e);
            if (this.rethrowExceptions) {
                throw e;
            } else {
            	return null;
            }
        } finally {
            Logger.saveLog();
        }
    }

    public List<EventLogFile> queryEventsAfterMostRecent() {
        AggregateResult lastModResult = [SELECT MAX(LastModifiedDate__c) lastMod, MAX(SystemModStamp__c) sysMod
                                         FROM EventLogFileParsing__c WITH SYSTEM_MODE];

        Datetime lastMod = (Datetime)lastModResult.get('lastMod');
        Datetime sysMod = (Datetime)lastModResult.get('sysMod');

        List<EventLogFileParsing__c> prevParsings = [SELECT Id__c, LastModifiedDate__c, SystemModStamp__c
                                                     FROM EventLogFileParsing__c
                                                     WHERE LastModifiedDate__c >= :lastMod
                                                        OR SystemModStamp__c >= :sysMod
                                                     WITH SYSTEM_MODE
                                                     ORDER BY LastModifiedDate__c ASC, SystemModStamp__c ASC];

        List<EventLogFile> events = [SELECT Id, ApiVersion, CreatedDate, EventType, LastModifiedDate, LogDate, LogFile,
                                         LogFileFieldNames, LogFileFieldTypes, LogFileLength, Sequence, SystemModStamp
                                     FROM EventLogFile
                                     WHERE EventType = 'ApexUnexpectedException'
                                       AND (LastModifiedDate >= :lastMod OR SystemModStamp >= :sysMod)
                                     WITH SYSTEM_MODE
                                     ORDER BY LastModifiedDate ASC, SystemModStamp ASC];

        for (Integer i = 0; i < events.size(); i++) {
            EventLogFile file = events.get(i);
            Boolean alreadyParsed = false;
            for (EventLogFileParsing__c parsing : prevParsings) {
                if (parsing.Id__c == file.Id && parsing.LastModifiedDate__c <= file.LastModifiedDate && parsing.SystemModstamp__c <= file.SystemModstamp) {
                    events.remove(i);
                    i--;
                }
            }
        }

        Logger.info('ApexUnexpectedExceptionParsingJob.queryEventsAfterMostRecent: Success querying for ' + events.size()
                    + ' EventLogFile records after LastModifiedDate ' + lastMod + ' or SystemModStamp ' + sysMod)
            .setRecord(new Map<Id, EventLogFile>(events).keySet());
        return events;
    }

    public List<EventLogFile> queryEventsNotYetParsed() {
        List<EventLogFileParsing__c> prevParsings = [SELECT Id, Id__c
                                                 FROM EventLogFileParsing__c
                                                 WITH SYSTEM_MODE
                                                 ORDER BY LastModifiedDate__c ASC, SystemModStamp__c ASC];
        Set<Id> parsedIds = new Set<Id>();
        for (EventLogFileParsing__c parsing : prevParsings) {
            Id parsedId;
            try {
                parsedId = Id.valueOf(parsing.Id__c);
            } catch (Exception e) {
                Logger.warn('ApexUnexpectedExceptionParsingJob.queryEventsNotYetParsed: Invalid Id__c value: ' + parsing.Id__c, e)
                    .setRecord(parsing.Id);
                continue;
            }
            parsedIds.add(parsedId);
        }

        List<EventLogFile> events = [SELECT Id, ApiVersion, CreatedDate, EventType, LastModifiedDate, LogDate, LogFile,
                                     LogFileFieldNames, LogFileFieldTypes, LogFileLength, Sequence, SystemModStamp
                                     FROM EventLogFile
                                     WHERE EventType = 'ApexUnexpectedException'
                                       AND (NOT (Id IN :parsedIds))
                                     WITH SYSTEM_MODE
                                     ORDER BY LastModifiedDate ASC, SystemModStamp ASC];

        Logger.info('ApexUnexpectedExceptionParsingJob.queryEventsNotYetParsed: Success querying for ' + events.size()
                    + ' EventLogFile records not yet parsed')
            .setRecord(new Map<Id, EventLogFile>(events).keySet());
        return events;
    }

    public void execute(Database.BatchableContext bc, List<EventLogFile> events) {
        this.setLoggerTransactionId();
        try {
            List<ParsingResult> parsingResults = this.processEvents(events);
            if (parsingResults != null && parsingResults.size() > 0) {
                this.processExceptions(parsingResults);
            }
        } catch (Exception e) {
            Logger.error('ApexUnexpectedExceptionParsingJob.execute EXCEPTION', e)
                .setRecord(new Map<Id, EventLogFile>(events).keySet());
            if (this.rethrowExceptions) {
                throw e;
            }
        } finally {
            Logger.saveLog();
        }
    }

    public static CSVDeserializer makeDeserializer() {
        return new CSVDeserializer()
            .setFieldMapping('EVENT_TYPE', 'EventType__c')
            .setFieldMapping('REQUEST_ID', 'RequestId__c')
            .setFieldMapping('ORGANIZATION_ID', 'OrganizationId__c')
            .setFieldMapping('APEX_ENTITY_NAME', 'ApexEntityName__c')
            .setFieldMapping('EXCEPTION_TYPE', 'ExceptionType__c')
            .setFieldMapping('EXCEPTION_MESSAGE', 'ExceptionMessage__c')
            .setFieldMapping('STACK_TRACE', 'StackTrace__c')
            .setFieldMapping('EXCEPTION_CATEGORY', 'ExceptionCategory__c')
            .setFieldMapping('TIMESTAMP_DERIVED', 'Timestamp__c', CSVDeserializer.DATETIME_CONVERTER)
            .setFieldMapping('USER_ID_DERIVED', 'UserId__c')
            .setUnmappedValuesSObjectHandler(new UnmappedValuesHandler());
    }

    public class ParsingResult implements SObjectWrapper {
        public final EventLogFileParsing__c parsing;
        public final List<ApexUnexpectedException__c> exceptions;

        private ParsingResult(EventLogFileParsing__c parsing, List<ApexUnexpectedException__c> exceptions) {
            this.parsing = parsing;
            this.exceptions = exceptions;
        }

        public SObject getSObject() {
            return this.parsing;
        }

        public void setRecord(LogEntryEventBuilder logBuilder) {
            logBuilder.setRecord(this.parsing);
        }
    }

    public static ParsingResult parseFile(EventLogFile file, CSVDeserializer ds) {
        EventLogFileParsing__c parsing = new EventLogFileParsing__c(
            ApiVersion__c = file.ApiVersion,
            CreatedDate__c = file.CreatedDate,
            EventType__c = file.EventType,
            Id__c = file.Id,
            LastModifiedDate__c = file.LastModifiedDate,
            LogDate__c = file.LogDate,
            LogFileFieldNames__c = file.LogFileFieldNames,
            LogFileFieldTypes__c = file.LogFileFieldTypes,
            LogFileLength__c = file.LogFileLength,
            Sequence__c = file.Sequence,
            SystemModStamp__c = file.SystemModstamp
        );
        parsing.ParsingTimestamp__c = Datetime.now();
        Long start = System.now().getTime();
        ds.setBody(file.LogFile);
        parsing.LogFileLengthActual__c = ds.getParser().body.length();
        parsing.LogFileFieldNamesActual__c = String.join(ds.getHeaders(), ',');
        
        List<ApexUnexpectedException__c> exceptions = (List<ApexUnexpectedException__c>)ds.deserialize(ApexUnexpectedException__c.SObjectType);
        Long fin = System.now().getTime();
        parsing.ParsingTime__c = fin - start;
        return new ParsingResult(parsing, exceptions);
    }

    private List<ParsingResult> processEvents(List<EventLogFile> events) {
        CSVDeserializer ds = makeDeserializer();
        List<EventLogFileParsing__c> parsingsToInsert = new List<EventLogFileParsing__c>();
        List<ParsingResult> parsingResults = new List<ParsingResult>();

        for (EventLogFile file : events) {
            ParsingResult result;
            try {
                result = parseFile(file, ds);
            } catch (Exception e) {
                Logger.error('ApexUnexpectedExceptionParsingJob.processEvents', e).setRecord(file.Id);
                continue;
            }
            parsingResults.add(result);
            parsingsToInsert.add(result.parsing);
        }

        List<Database.SaveResult> saveResults = Database.insert(parsingsToInsert, false, AccessLevel.SYSTEM_MODE);
        ProcessedDatabaseSaveResults processed = this.processAndLogDatabaseSaveResults(
            'ApexUnexpectedExceptionParsingJob.processEvents',
            EventLogFileParsing__c.SObjectType,
            saveResults, parsingResults,
            new SObjectWrapperHandler()
        );

        //convert List<Object> to List<ParsingResult>
        List<ParsingResult> successfulSaves = new List<ParsingResult>();
        for (Object result : processed.successfulSaves) {
            successfulSaves.add((ParsingResult)result);
        }
        return successfulSaves;
    }
    
    private void processExceptions(List<ParsingResult> parsingResults) {
        List<ApexUnexpectedException__c> excsToInsert = new List<ApexUnexpectedException__c>();
        //Verify that the UserIds still actually exist in the system, and remove any that are invalid
        Set<Id> userIds = new Set<Id>();
        for (ParsingResult result : parsingResults) {
            for (ApexUnexpectedException__c exc : result.exceptions) {
                exc.EventLogFileParsing__c = result.parsing.Id;
                exc.EventLogFileParsing__r = result.parsing;
                Id userId;
                try {
                    userId = Id.valueOf(exc.UserId__c);
                } catch (StringException e) {
                    continue;
                }
                userIds.add(userId);
                exc.User__c = userId;
            }
            excsToInsert.addAll(result.exceptions);
        }

        Set<Id> users = new Map<Id, User>([SELECT Id FROM User WHERE Id IN :userIds WITH SYSTEM_MODE]).keySet();
        userIds.removeAll(users); // remaining Ids will only be for Users which do NOT actually exist in the system
        if (userIds.size() > 0) {
            List<Id> eventLogFileIds = new List<Id>();
            for (Id userId : userIds) {
                //set User__c field to null in relevant exc records
                for (ApexUnexpectedException__c exc : excsToInsert) {
                    if (exc.User__c == userId) {
                        exc.User__c = null;
                        eventLogFileIds.add(exc.EventLogFileParsing__r.Id__c); //Id of EventLogFile
                        eventLogFileIds.add(exc.EventLogFileParsing__c); //Id of EventLogFileParsing__c
                    }
                }
            }
            Logger.warn('ApexUnexpectedExceptionParsingJob.processEvents: Invalid UserIds provided in CSV parsing output(s):\n' + String.join(userIds, ' , '))
                .setRecord(eventLogFileIds);
        }

        List<Database.SaveResult> saveResults = Database.insert(excsToInsert, false, AccessLevel.SYSTEM_MODE);
        this.processAndLogDatabaseSaveResults('ApexUnexpectedExceptionParsingJob.processExceptions', ApexUnexpectedException__c.SObjectType, saveResults, excsToInsert);
    }

    public class UnmappedValuesHandler extends CSVDeserializer.UnmappedValuesJsonSerializer {
        public UnmappedValuesHandler() {
            super('UnmappedValues__c', true);
        }

        override public void handle(SObject o, List<CSVDeserializer.UnmappedValue> unmappedValues) {
            ApexUnexpectedException__c obj = (ApexUnexpectedException__c)o;
            for (Integer i = 0; i < unmappedValues.size(); i++) {
                CSVDeserializer.UnmappedValue value = unmappedValues.get(i);
                if (value.columnHeader == 'USER_ID') {
                    Id userId;
                    try {
                        userId = Id.valueOf(value.value);
                    } catch (Exception e) {
                        continue;
                    }
                    if (userId == obj.UserId__c) {
                        unmappedValues.remove(i);
                        i--;
                    }
                } else if (value.columnHeader == 'TIMESTAMP' && value.value.length() > 12) {
                    String val = value.value;
                    Datetime timestamp;
                    try {
                        String formatted = val.substring(0, 4) + '-' + val.substring(4, 6) + '-' + val.substring(6, 8)
                            + 'T' + val.substring(8, 10) + ':' + val.substring(10, 12) + ':' + val.substring(12);
                        timestamp = CSVDeserializer.DATETIME_CONVERTER.convert(formatted);
                    } catch (Exception e) {
                        continue;
                    }
                    if (timestamp == obj.Timestamp__c) {
                        unmappedValues.remove(i);
                        i--;
                    }
                }
            }
            if (unmappedValues.size() > 0) {
                super.handle(o, unmappedValues);
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        this.setLoggerTransactionId();
        Logger.info('ApexUnexpectedExceptionParsingJob.finish');
        Logger.saveLog();
    }
}