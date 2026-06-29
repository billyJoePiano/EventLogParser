public class CSVDeserializer {
    public static final EmptyStringToNullConverter EMPTY_TO_NULL_CONVERTER = new EmptyStringToNullConverter();
    public static final IntegerConverter INTEGER_CONVERTER = new IntegerConverter();
    public static final DecimalConverter DECIMAL_CONVERTER = new DecimalConverter();
    public static final DoubleConverter DOUBLE_CONVERTER = new DoubleConverter();
    public static final DatetimeConverter DATETIME_CONVERTER = new DatetimeConverter();

    private CSVParser parser = null;
    private List<String> headers = null;
    private UnmappedValuesMapHandler unmappedMapHandler = null;
    private UnmappedValuesSObjectHandler unmappedSObjectHandler = null;

    private final Map<String, FieldMapping> targetFields = new Map<String, FieldMapping>();
    private final Map<String, List<FieldMapping>> sourceFields = new Map<String, List<FieldMapping>>();
    private final List<List<FieldMapping>> sourceColumns = new List<List<FieldMapping>>();

    public CSVDeserializer() { }

    public CSVDeserializer(String body) {
        this(new CSVParser(body));
    }

    public CSVDeserializer(Blob body) {
        this(new CSVParser(body));
    }

    public CSVDeserializer(CSVParser parser) {
        this(parser, true);
    }

    public CSVDeserializer(String body, Boolean useHeaders) {
        this(new CSVParser(body), useHeaders);
    }

    public CSVDeserializer(Blob body, Boolean useHeaders) {
        this(new CSVParser(body), useHeaders);
    }

    public CSVDeserializer(CSVParser parser, Boolean useHeaders) {
        this.setParser(parser, useHeaders);
    }

    public void setBody(String body) {
        this.setBody(body, true);
    }

    public void setBody(Blob body) {
        this.setBody(body, true);
    }

    public void setBody(String body, Boolean useHeaders) {
        this.setParser(new CSVParser(body), useHeaders);
    }

    public void setBody(Blob body, Boolean useHeaders) {
        this.setParser(new CSVParser(body), useHeaders);
    }

    public void setParser(CSVParser parser, Boolean useHeaders) {
        if (parser == null) throw new NullPointerException();
        this.parser = parser;
        if (useHeaders) {
            this.headers = parser.getHeaderRow().toList();
        }
    }

    public CSVParser getParser() {
        return this.parser;
    }

    public void setHeaders(List<String> headers) {
        this.headers = headers;
    }

    public List<String> getHeaders() {
        if (this.headers == null) {
            return null;
        } else {
            return new List<String>(this.headers);
        }
    }

    // Container to store mappings from CSV source columns or header-named fields, to target field names
    public class FieldMapping {
        /* sourceField is either an Integer for column number, or a String for header-named field mapping.
         * NOTE: When it is an integer, sourceField is stored as a 0-indexed ordinal to assist with deserialization,
         * HOWEVER the setFieldMapping() method of CSVDeserializer takes a 1-indexed column ordinal
         */
        public final Object sourceField;
        public final String targetField; // field name on the target object or Map
        public final ValueConverter converter; //if null, the String passed from CSVParser is used


        private FieldMapping(Object sourceField, String targetField, ValueConverter converter) {
            this.targetField = targetField;
            this.sourceField = sourceField;
            this.converter = converter;
        }

        private String sourceFieldStr() {
            if (this.sourceField instanceof Integer) {
                return (((Integer)this.sourceField) + 1).toString(); // convert from 0-indexed to 1-indexed
            }
            return (String)this.sourceField;
        }
    }

    public CSVDeserializer setFieldMapping(String headerFieldName, String targetFieldName) {
        return this.setFieldMapping(headerFieldName, targetFieldName, null);
    }

    // columnOrdinal should be provided as 1-indexed value
    public CSVDeserializer setColumnMapping(Integer columnOrdinal, String targetFieldName) {
        return this.setColumnMapping(columnOrdinal, targetFieldName, null);
    }

    public CSVDeserializer setFieldMapping(String headerFieldName, String targetFieldName, ValueConverter converter) {
        if (headerFieldName == null || targetFieldName == null) {
            throw new NullPointerException();
        }
        removeTargetFieldMapping(targetFieldName);

        FieldMapping mapping = new FieldMapping(headerFieldName, targetFieldName, converter);
        this.targetFields.put(targetFieldName, mapping);
        List<FieldMapping> sourceMappings;
        if (this.sourceFields.containsKey(headerFieldName)) {
            sourceMappings = this.sourceFields.get(headerFieldName);
        } else {
            sourceMappings = new List<FieldMapping>();
            this.sourceFields.put(headerFieldName, sourceMappings);
        }
        sourceMappings.add(mapping);
        return this;
    }

    public CSVDeserializer setColumnMapping(Integer columnOrdinal, String targetFieldName, ValueConverter converter) {
        if (columnOrdinal == null || targetFieldName == null) {
            throw new NullPointerException();
        } else if (columnOrdinal < 1) {
            throw new IllegalArgumentException('columnOrdinal is 1-indexed and must be >= 1, provided: ' + columnOrdinal);
        }
        removeTargetFieldMapping(targetFieldName);
        columnOrdinal -= 1; //convert from 1-indexed to 0-indexed for deserialization purposes

        FieldMapping mapping = new FieldMapping(columnOrdinal, targetFieldName, converter);
        this.targetFields.put(targetFieldName, mapping);
        List<FieldMapping> sourceMappings;
        if (this.sourceColumns.size() <= columnOrdinal) {
            while (this.sourceColumns.size() < columnOrdinal) {
                this.sourceColumns.add(null); //use null as placeholder when there are no mapping for the column
            }
            sourceMappings = new List<FieldMapping>();
            this.sourceColumns.add(sourceMappings);
        } else {
            sourceMappings = this.sourceColumns.get(columnOrdinal);
            if (sourceMappings == null) {
                sourceMappings = new List<FieldMapping>();
                this.sourceColumns.set(columnOrdinal, sourceMappings);
            }
        }
        sourceMappings.add(mapping);
        return this;
    }

    public CSVDeserializer setFieldForUnmappedValues(String targetFieldName) {
        return this.setFieldForUnmappedValues(targetFieldName, false);
    }

    public CSVDeserializer setFieldForUnmappedValues(String targetFieldName, Boolean toJsonForBoth) {
        UnmappedValuesJsonSerializer jsonSerializer = new UnmappedValuesJsonSerializer(targetFieldName);
        this.unmappedSObjectHandler = jsonSerializer;
        this.unmappedMapHandler = toJsonForBoth ? (UnmappedValuesMapHandler)jsonSerializer : new UnmappedValuesToMapField(targetFieldName);
        removeTargetFieldMapping(targetFieldName);
        return this;
    }

    public CSVDeserializer setUnmappedValuesMapHandler(UnmappedValuesMapHandler unmappedMapHandler) {
        this.unmappedMapHandler = unmappedMapHandler;
        return this;
    }

    public CSVDeserializer setUnmappedValuesSObjectHandler(UnmappedValuesSObjectHandler unmappedSObjectHandler) {
        this.unmappedSObjectHandler = unmappedSObjectHandler;
        return this;
    }

    public UnmappedValuesMapHandler getUnmappedValuesMapHandler() {
        return this.unmappedMapHandler;
    }

    public UnmappedValuesSObjectHandler getUnmappedValuesSObjectHandler() {
        return this.unmappedSObjectHandler;
    }

    public Set<String> getTargetFieldMappings() {
        return new Set<String>(this.targetFields.keySet());
    }

    public Set<Integer> getSourceColumnMappings() {
        Set<Integer> columns = new Set<Integer>();
        for (Integer col = 0; col < this.sourceColumns.size(); col++) {
            List<FieldMapping> colMapping = this.sourceColumns.get(col);
            if (colMapping != null && colMapping.size() > 0) {
                columns.add(col);
            }
        }
        return columns;
    }

    public Set<String> getSourceFieldMappings() {
        Set<String> fields = new Set<String>(this.sourceFields.keySet());
        for (String field : this.sourceFields.keySet()) {
            List<FieldMapping> fieldMapping = this.sourceFields.get(field);
            if (fieldMapping != null && fieldMapping.size() > 0) {
                fields.add(field);
            }
        }
        return fields;
    }

    public FieldMapping getTargetFieldMapping(String targetFieldName) {
        return this.targetFields.get(targetFieldName);
    }

    public List<FieldMapping> getSourceColumnMappings(Integer columnOrdinal) {
        columnOrdinal--; //convert from 1-indexed to 0-indexed
        if (columnOrdinal < this.sourceColumns.size()) {
            List<FieldMapping> columnMappings = this.sourceColumns.get(columnOrdinal);
            if (columnMappings != null) {
                return new List<FieldMapping>(columnMappings);
            }
        }
        return new List<FieldMapping>();
    }

    public List<FieldMapping> getSourceFieldMappings(String headerFieldName) {
        List<FieldMapping> sourceMappings = this.sourceFields.get(headerFieldName);
        if (sourceMappings != null) {
            return new List<FieldMapping>(sourceMappings);
        } else {
            return new List<FieldMapping>();
        }
    }

    public FieldMapping removeTargetFieldMapping(String targetFieldName) {
        FieldMapping mapping = this.targetFields.remove(targetFieldName);
        if (mapping != null) {
            this.removeFieldMappingUnchecked(mapping);
        }
        return mapping;
    }

    public Boolean removeFieldMapping(FieldMapping mapping) {
        FieldMapping existing = this.targetFields.get(mapping.targetField);
        if (mapping === existing) {
            this.targetFields.remove(mapping.targetField);
            this.removeFieldMappingUnchecked(mapping);
        }
        return false;
    }

    // unchecked meaing this does NOT confirm that the mapping was the existing mapping for the targetField,
    // and does NOT remove it from this.targetFields map
    private void removeFieldMappingUnchecked(FieldMapping mapping) {
        List<FieldMapping> columnOrFieldMappings;
        if (mapping.sourceField instanceof Integer) {
            columnOrFieldMappings = this.sourceColumns.get((Integer)mapping.sourceField);
        } else if (mapping.sourceField instanceof String) {
            columnOrFieldMappings = this.sourceFields.get((String)mapping.sourceField);
        } else {
            throw new CSVDeserializationException('Unexpected state'); //probably unreachable???
        }
        columnOrFieldMappings.remove(columnOrFieldMappings.indexOf(mapping)); //unchecked non-null and index > -1 ... those scenarios should be unreachable (???)
    }

	//converts the String value output by the CSVParser into another value type (e.g. Integer, Double, DateTime, etc)
    public interface ValueConverter {
        Object convert(String parserOutput);
    }

    public class EmptyStringToNullConverter implements ValueConverter {
        virtual public String convert(String parserOutput) {
            if (parserOutput == '') {
                return null;
            } else {
                return parserOutput;
            }
        }
    }

    public class IntegerConverter implements ValueConverter {
        virtual public Integer convert(String parserOutput) {
            try {
                return Integer.valueOf(parserOutput);
            } catch (Exception e) {
                throw new CSVDeserializationException(e.getMessage(), parserOutput);
            }
        }
    }

    public class DecimalConverter implements ValueConverter {
        virtual public Decimal convert(String parserOutput) {
            try {
                return Decimal.valueOf(parserOutput);
            } catch (Exception e) {
                throw new CSVDeserializationException(e.getMessage(), parserOutput);
            }
        }
    }

    public class DoubleConverter implements ValueConverter {
        virtual public Double convert(String parserOutput) {
            try {
                return Double.valueOf(parserOutput);
            } catch (Exception e) {
                throw new CSVDeserializationException(e.getMessage(), parserOutput);
            }
        }
    }

    public class DatetimeConverter implements ValueConverter {
        virtual public Datetime convert(String parserOutput) {
            try {
                return (Datetime)JSON.deserialize(JSON.serialize(parserOutput), Datetime.class);
            } catch (Exception e) {
                throw new CSVDeserializationException(e.getMessage(), parserOutput);
            }
        }
    }

    public class UnmappedValue {
        public final Integer columnNumber; //1-indexed column ordinal
        public final String columnHeader; //null indicates no header available.  This field is excluded from JSON serialization when null
        public final String value; // String value output by the CSVParser (null only when UnmappedValue is used internally to represent a possible overwrite -- see runDeserialize() method)

        /* The below 2 fields are only applicable for overwrites, which are only possible when there are duplicate column headers.
         * These fields are included in JSON serialization when they are non-null, and excluded from JSON when null;
         */
        public final Integer overwrittenByColumnNumber; //1-indexed column ordinal.  Null when this unmapped value is not the result of an overwrite
        public final String overwrittenByColumnHeader; //Null when this unmapped value is not the result of an overwrite

        @TestVisible
        private UnmappedValue(Integer columnNumber, String columnHeader, String value) {
            this(columnNumber, columnHeader, value, null, null);
        }

        @TestVisible
        private UnmappedValue(Integer columnNumber, String columnHeader, String value, Integer overwrittenByColumnNumber, String overwrittenByColumnHeader) {
            this.columnNumber = columnNumber;
            this.columnHeader = columnHeader;
            this.value = value;
            this.overwrittenByColumnNumber = overwrittenByColumnNumber;
            this.overwrittenByColumnHeader = overwrittenByColumnHeader;
        }

        public void toJson(JSONGenerator gen) {
            gen.writeStartObject();
            gen.writeStringField('value', this.value);
            gen.writeNumberField('columnNumber', this.columnNumber);
            if (this.columnHeader != null) {
                gen.writeStringField('columnHeader', this.columnHeader);
            }
            if (this.overwrittenByColumnNumber != null) {
                gen.writeNumberField('overwrittenByColumnNumber', this.overwrittenByColumnNumber);
                gen.writeStringField('overwrittenByColumnHeader', this.overwrittenByColumnHeader);
            }
            gen.writeEndObject();
        }

        public Boolean equals(Object obj) {
            if (obj === this) {
                return true;
            }
            if (obj instanceof UnmappedValue) {
                UnmappedValue other = (UnmappedValue)obj;
                return other.columnNumber == this.columnNumber
                    && other.columnHeader == this.columnHeader
                    && other.value == this.value
                    && other.overwrittenByColumnNumber == this.overwrittenByColumnNumber
                    && other.overwrittenByColumnHeader == this.overwrittenByColumnHeader;
            } else {
                return false;
            }
        }

        public Integer hashCode() {
            Integer hash = this.columnNumber;
            if (this.columnHeader != null) {
                hash ^= this.columnHeader.hashCode();
            }
            if (this.value != null) {
                hash ^= this.value.hashCode();
            }
            if (this.overwrittenByColumnNumber != null) {
                hash ^= this.overwrittenByColumnNumber.hashCode() ^ this.overwrittenByColumnHeader.hashCode();
            }
            return hash;
        }
    }
    
    public static JsonGenerator unmappedValuesToJson(JsonGenerator gen, List<UnmappedValue> unmappedValues) {
        gen.writeStartArray();
        for (UnmappedValue val : unmappedValues) {
            val.toJson(gen);
        }
        gen.writeEndArray();
        return gen;
    }

    public interface UnmappedValuesSObjectHandler {
        void handle(SObject obj, List<UnmappedValue> unmappedValues);
    }

    public interface UnmappedValuesMapHandler {
        void handle(Map<String, Object> mp, List<UnmappedValue> unmappedValues);
    }

    virtual public class UnmappedValuesToMapField implements UnmappedValuesMapHandler {
        public final String targetField;

        public UnmappedValuesToMapField(String targetField) {
            if (targetField == null) {
                throw new NullPointerException();
            }
            this.targetField = targetField;
        }

        public void handle(Map<String, Object> mp, List<UnmappedValue> unmappedValues) {
            try {
                mp.put(this.targetField, unmappedValues);
            } catch (Exception e) {
                throw new CSVDeserializationException(e.getMessage(), 'N/A (UnmappedValuesToMapField: while handling unmapped values)');
            }
        }
    }

    virtual public class UnmappedValuesJsonSerializer implements UnmappedValuesSObjectHandler, UnmappedValuesMapHandler {
        public final String targetField;
        public final Boolean prettyPrint;

        public UnmappedValuesJsonSerializer(String targetField) {
            this(targetField, true);
        }

        public UnmappedValuesJsonSerializer(String targetField, Boolean prettyPrint) {
            if (targetField == null || prettyPrint == null) {
                throw new NullPointerException();
            }
            this.targetField = targetField;
            this.prettyPrint = prettyPrint;
        }

        virtual public void handle(SObject obj, List<UnmappedValue> unmappedValues) {
            try {
                obj.put(this.targetField, this.toJson(unmappedValues));
            } catch (Exception e) {
                throw new CSVDeserializationException(e.getMessage(), 'N/A (UnmappedValuesJsonSerializer: while handling unmapped values)');
            }
        }

        virtual public void handle(Map<String, Object> mp, List<UnmappedValue> unmappedValues) {
            try {
                mp.put(this.targetField, this.toJson(unmappedValues));
            } catch (Exception e) {
                throw new CSVDeserializationException(e.getMessage(), 'N/A (UnmappedValuesJsonSerializer: while handling unmapped values)');
            }
        }

        virtual public String toJson(List<UnmappedValue> unmappedValues) {
            return unmappedValuesToJson(JSON.createGenerator(this.prettyPrint), unmappedValues).getAsString();
        }
    }

    public List<Map<String, Object>> deserialize() {
        CSVParser oldParser = currentParser;
        FieldMapping oldFieldMapping = currentFieldMapping;
        try {
            currentParser = this.parser;
            currentFieldMapping = null;
            MapMaker result = new MapMaker(this.unmappedMapHandler);
            runDeserialize(result);
            return result.result;
        } finally {
            currentParser = oldParser;
            currentFieldMapping = oldFieldMapping;
        }
    }

    public List<SObject> deserialize(SObjectType soType) {
        if (soType == null) {
            throw new NullPointerException();
        }
        CSVParser oldParser = currentParser;
        FieldMapping oldFieldMapping = currentFieldMapping;
        try {
            currentParser = this.parser;
            currentFieldMapping = null;
            SObjectMaker result = new SObjectMaker(soType, this.unmappedSObjectHandler);
            runDeserialize(result);
            return result.result;
        } finally {
            currentParser = oldParser;
            currentFieldMapping = oldFieldMapping;
        }
    }

    // shared interface for constructing both Maps and SObjects during deserialization
    private interface ResultMaker {
        void newObj();
        void put(FieldMapping mapping, String parserOutput);
        Boolean trackUnmapped();
        void handleUnmapped(List<UnmappedValue> unmappedValues);
    }

    private class MapMaker implements ResultMaker {
        private Map<String, Object> mp;
        private final List<Map<String, Object>> result = new List<Map<String, Object>>();
        private final UnmappedValuesMapHandler unmappedValuesHandler;

        private MapMaker(UnmappedValuesMapHandler unmappedValuesHandler) {
            this.unmappedValuesHandler = unmappedValuesHandler;
        }

        public void newObj() {
            this.mp = new Map<String, Object>();
            this.result.add(this.mp);
        }

        public void put(FieldMapping mapping, String parserOutput) {
            FieldMapping oldFieldMapping = currentFieldMapping;
            currentFieldMapping = mapping;
            try {
                Object value;
                if (mapping.converter != null) {
                    value = mapping.converter.convert(parserOutput);
                } else {
                    value = parserOutput;
                }
                try {
                    this.mp.put(mapping.targetField, value);
                } catch (Exception e) {
                    throw new CSVDeserializationException(e.getMessage(), parserOutput);
                }
            } finally {
                currentFieldMapping = oldFieldMapping;
            }
        }

        public Boolean trackUnmapped() {
            return this.unmappedValuesHandler != null;
        }

        public void handleUnmapped(List<UnmappedValue> unmappedValues) {
            this.unmappedValuesHandler.handle(this.mp, unmappedValues);
        }
    }

    private class SObjectMaker implements ResultMaker {
        private final SObjectType soType;
        private SObject obj;
        private final List<SObject> result = new List<SObject>();
        private final UnmappedValuesSObjectHandler unmappedValuesHandler;

        private SObjectMaker(SObjectType soType, UnmappedValuesSObjectHandler unmappedValuesHandler) {
            this.soType = soType;
            this.unmappedValuesHandler = unmappedValuesHandler;
        }

        public void newObj() {
            this.obj = soType.newSObject();
            this.result.add(this.obj);
        }

        public void put(FieldMapping mapping, String parserOutput) {
            FieldMapping oldFieldMapping = currentFieldMapping;
            currentFieldMapping = mapping;
            try {
                Object value;
                if (mapping.converter != null) {
                    value = mapping.converter.convert(parserOutput);
                } else {
                    value = parserOutput;
                }
                try {
                    this.obj.put(mapping.targetField, value);
                } catch (Exception e) {
                    throw new CSVDeserializationException(e.getMessage(), parserOutput);
                }
            } finally {
                currentFieldMapping = oldFieldMapping;
            }
        }

        public Boolean trackUnmapped() {
            return this.unmappedValuesHandler != null;
        }

        public void handleUnmapped(List<UnmappedValue> unmappedValues) {
            this.unmappedValuesHandler.handle(this.obj, unmappedValues);
        }
    }

    private void runDeserialize(ResultMaker result) {
        List<String> headers = this.headers;
        List<List<FieldMapping>> sourceColumns = this.sourceColumns;
        Map<String, List<FieldMapping>> sourceFields = this.sourceFields;

        // initial check for field overwrite possibilities
        Boolean trackUnmapped = result.trackUnmapped();
        Map<Integer, UnmappedValue> overwritten = null; //maps column # of the field that could be overwritten to details about the possible overwrite
        if (trackUnmapped && headers != null && sourceFields.size() > 0) {
            overwritten = new Map<Integer, UnmappedValue>();
            Integer col = 0;
            for (String header : headers) {
                if (!sourceFields.containsKey(header)) {
                    continue;
                }
                // Iterate backwards from the current column, to find the most recent header with the same value
                for (Integer i = col - 1; i >= 0; i--) {
                    String prevHeader = headers.get(i);
                    if (header == prevHeader) {
                        overwritten.put(i, new UnmappedValue(i, prevHeader, null, col, header));
                        break;
                    }
                }
                col++;
            }
            if (overwritten.size() < 1) {
                overwritten = null;
            }
        }

        // iterate over rows and perform deserialization
        for (CSVParser.Row row : this.parser) {
            result.newObj();
            Integer col = 0;
            Map<Integer, UnmappedValue> overwriteCandidates = null; // maps column # of the field that could do the overwritting to the actual UnmappedValue for this record
            List<UnmappedValue> unmappedValues = null;
            if (trackUnmapped) {
                unmappedValues = new List<UnmappedValue>();
                if (overwritten != null) {
                    overwriteCandidates = new Map<Integer, UnmappedValue>();
                }
            }

            for (String parserOutput : row) {
                Boolean mapped = false;
                if (col < sourceColumns.size()) {
                    List<FieldMapping> columnMappings = sourceColumns.get(col);
                    if (columnMappings != null) {
                        for (FieldMapping mapping : columnMappings) {
                            result.put(mapping, parserOutput);
                            mapped = true;
                        }
                    }
                }
                String header = null;
                if (headers != null && col < headers.size()) {
                    header = headers.get(col);
                    if (sourceFields.containsKey(header)) {
                        List<FieldMapping> fieldMappings = sourceFields.get(header);
                        for (FieldMapping mapping : fieldMappings) {
                            result.put(mapping, parserOutput);
                            mapped = true;
                        }
                    }
                }
                if (mapped) {
                    if (overwritten != null) {
                        //determine if this field could be overwritten by a subsequent field
                        if (overwritten.containsKey(col)) {
                            UnmappedValue details = overwritten.get(col);
                            overwriteCandidates.put(details.overwrittenByColumnNumber, new UnmappedValue(col + 1, header, parserOutput, details.overwrittenByColumnNumber + 1, details.overwrittenByColumnHeader)); // col + 1 is to restore 1-indexing, from 0-indexing
                        }
                        //determine if this field is currently overwriting a previous field
                        if (overwriteCandidates.containsKey(col)) {
                            unmappedValues.add(overwriteCandidates.get(col));
                        }
                    }
                    
                } else if (trackUnmapped) {
                    unmappedValues.add(new UnmappedValue(col + 1, header, parserOutput)); // col + 1 is to restore 1-indexing, from 0-indexing
                }
                col++;
            }
            if (unmappedValues != null && unmappedValues.size() > 0) {
                result.handleUnmapped(unmappedValues);
            }
        }
    }

    private static CSVParser currentParser = null;
    private static FieldMapping currentFieldMapping = null;
    public class CSVDeserializationException extends CSVParser.CSVParsingException {
        // Apex does not allow overriding of string-only constructor for Exception subclasses
        public CSVDeserializationException(String msg, String parserOutput) {
            super(currentParser,
                  msg + '\nFor CSVParser output: ' + parserOutput + (currentFieldMapping == null ? '' :
                      ('\nFor field mapping: ' + currentFieldMapping.sourceFieldStr() + ' => ' + currentFieldMapping.targetField)),
                  false);
        }
    }
}