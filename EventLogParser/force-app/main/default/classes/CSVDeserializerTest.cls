@IsTest
public class CSVDeserializerTest {
    public static void assertSObjects(CSVDeserializer deserializer, SObjectType soType, List<SObject> expected) {
        List<SObject> actual = deserializer.deserialize(soType);
        System.assertEquals(expected.size(), actual.size());
        for (Integer i = 0; i < expected.size(); i++) {
            Assert.areEqual(expected.get(i), actual.get(i));
        }
    }

    public static void assertMaps(CSVDeserializer deserializer, List<Map<String, Object>> expected) {
        List<Map<String, Object>> actual = deserializer.deserialize();
        System.assertEquals(expected.size(), actual.size());
        for (Integer i = 0; i < expected.size(); i++) {
            Assert.areEqual(expected.get(i), actual.get(i));
        }
    }

    @IsTest
    public static void testEmpty() {
        assertSObjects(new CSVDeserializer('', false), Account.SObjectType, new List<SObject>());
        assertMaps(new CSVDeserializer('', false), new List<Map<String, Object>>());
    }
    
    public static final String body1 = 'Name,Employees,Rating,CreatedDate,Empty\nMy Account,6,9.5,2024-05-23T21:58:22.000+0000,';
    public static final List<SObject> expectedSObjects1 = new List<SObject> {
            new Account(Name='My Account',
                        NumberOfEmployees=6
        )};
    public static final List<Map<String, Object>> expectedMaps1 = new List<Map<String, Object>> {
        new Map<String, Object> {
            'Name' => 'My Account',
            'NumberOfEmployees' => 6,
            'Rating' => Double.valueOf('9.5'),
            'CreatedDate' => Datetime.valueOfGmt('2024-05-23 21:58:22.000'),
            'Empty' => ''
        }
    };

    @IsTest
    public static void testFieldMapping() {
        CSVDeserializer deserializer = new CSVDeserializer(body1);
        deserializer.setFieldMapping('Name', 'Name')
            .setFieldMapping('Employees', 'NumberOfEmployees', CSVDeserializer.INTEGER_CONVERTER);
        assertSObjects(deserializer, Account.SObjectType, expectedSObjects1);
        
        deserializer.setFieldMapping('Rating', 'Rating', CSVDeserializer.DOUBLE_CONVERTER)
            .setFieldMapping('CreatedDate', 'CreatedDate', CSVDeserializer.DATETIME_CONVERTER)
            .setFieldMapping('Empty', 'Empty')
            .setBody(body1);
        assertMaps(deserializer, expectedMaps1);

        deserializer.setFieldMapping('Name', 'Name', CSVDeserializer.EMPTY_TO_NULL_CONVERTER)
            .setFieldMapping('Rating', 'Rating', CSVDeserializer.DECIMAL_CONVERTER)
            .setFieldMapping('Empty', 'Empty', CSVDeserializer.EMPTY_TO_NULL_CONVERTER)
            .setBody(body1);
        expectedMaps1.get(0).put('Rating', Decimal.valueOf('9.5'));
        expectedMaps1.get(0).put('Empty', null);
        assertMaps(deserializer, expectedMaps1);
    }

    @IsTest
    public static void testColumnMapping() {
        CSVDeserializer deserializer = new CSVDeserializer(body1);
        deserializer.setColumnMapping(1, 'Name')
            .setColumnMapping(2, 'NumberOfEmployees', CSVDeserializer.INTEGER_CONVERTER);
        assertSObjects(deserializer, Account.SObjectType, expectedSObjects1);
        
        deserializer.setColumnMapping(5, 'Empty') //start at 5 to test inserting null placeholders in sourceColumns list, then overwriting them with non-null values later
            .setColumnMapping(3, 'Rating', CSVDeserializer.DOUBLE_CONVERTER)
            .setColumnMapping(4, 'CreatedDate', CSVDeserializer.DATETIME_CONVERTER)
            .setBody(Blob.valueOf(body1));
        assertMaps(deserializer, expectedMaps1);

        deserializer.setColumnMapping(1, 'Name', CSVDeserializer.EMPTY_TO_NULL_CONVERTER)
            .setColumnMapping(3, 'Rating', CSVDeserializer.DECIMAL_CONVERTER)
            .setColumnMapping(5, 'Empty', CSVDeserializer.EMPTY_TO_NULL_CONVERTER)
            .setBody(Blob.valueOf(body1));
        expectedMaps1.get(0).put('Rating', Decimal.valueOf('9.5'));
        expectedMaps1.get(0).put('Empty', null);
        assertMaps(deserializer, expectedMaps1);
    }

    @IsTest
    public static void testInvalidSObjectFieldMapping() {
        CSVDeserializer deserializer = new CSVDeserializer(body1);
        deserializer.setFieldMapping('Name', 'Name')
            .setFieldMapping('Employees', 'NumberOfEmployees', CSVDeserializer.INTEGER_CONVERTER)
            .setFieldMapping('CreatedDate', 'CreatedDate', CSVDeserializer.DATETIME_CONVERTER); //CreatedDate can't be set

        try {
            assertSObjects(deserializer, Account.SObjectType, expectedSObjects1);
            System.assert(false, 'Expected CSVDeserializationException');
        } catch (CSVDeserializer.CSVDeserializationException e) {
            System.assertEquals('Field CreatedDate is not editable\nFor CSVParser output: 2024-05-23T21:58:22.000+0000\nFor field mapping: CreatedDate => CreatedDate\nDocument character position: 86\n2024-05-23T21:58:22.000+0000', e.getMessage());
        }
    }

    @IsTest
    public static void testInvalidSObjectColumnMapping() {
        CSVDeserializer deserializer = new CSVDeserializer(Blob.valueOf(body1), true);
        deserializer.setColumnMapping(1, 'Name')
            .setColumnMapping(2, 'NumberOfEmployees', CSVDeserializer.INTEGER_CONVERTER)
            .setColumnMapping(4, 'CreatedDate', CSVDeserializer.DATETIME_CONVERTER); //CreatedDate can't be set

        try {
            assertSObjects(deserializer, Account.SObjectType, expectedSObjects1);
            System.assert(false, 'Expected CSVDeserializationException');
        } catch (CSVDeserializer.CSVDeserializationException e) {
            System.assertEquals('Field CreatedDate is not editable\nFor CSVParser output: 2024-05-23T21:58:22.000+0000\nFor field mapping: 4 => CreatedDate\nDocument character position: 86\n2024-05-23T21:58:22.000+0000', e.getMessage());
        }

        deserializer.setBody(body1);
        deserializer.removeTargetFieldMapping('CreatedDate');
        deserializer.setFieldForUnmappedValues('Nonexistent');

        try {
            assertSObjects(deserializer, Account.SObjectType, expectedSObjects1);
            System.assert(false, 'Expected CSVDeserializationException');
        } catch (CSVDeserializer.CSVDeserializationException e) {
            System.assertEquals('Invalid field Nonexistent for Account\nFor CSVParser output: N/A (UnmappedValuesJsonSerializer: while handling unmapped values)\nDocument character position: 86\n', e.getMessage());
        }
    }

    @IsTest
    public static void testInvalidConverterValues() {
        iterateInvalidConverterValues(CSVDeserializer.INTEGER_CONVERTER, 'Invalid integer: My Account');
        iterateInvalidConverterValues(CSVDeserializer.DOUBLE_CONVERTER, 'Invalid double: My Account');
        iterateInvalidConverterValues(CSVDeserializer.DECIMAL_CONVERTER, 'Invalid decimal: My Account');
        iterateInvalidConverterValues(CSVDeserializer.DATETIME_CONVERTER, 'Invalid format: "My Account"');
    }
    
    public static void iterateInvalidConverterValues(CSVDeserializer.ValueConverter converter, String msgStart) {
        CSVDeserializer deserializer = new CSVDeserializer(Blob.valueOf(body1));
        deserializer.setColumnMapping(1, 'Name', converter);
        try {
            assertSObjects(deserializer, Account.SObjectType, expectedSObjects1);
            System.assert(false, 'Expected CSVDeserializationException');
        } catch (CSVDeserializer.CSVDeserializationException e) {
            System.assertEquals(msgStart + '\nFor CSVParser output: My Account\nFor field mapping: 1 => Name\nDocument character position: 51\nMy Account', e.getMessage());
        }
    }
    
    @IsTest
    public static void testInvalidArguments() {
        CSVDeserializer ds = new CSVDeserializer(body1);
        try {
            ds.setFieldMapping(null, null);
            System.assert(false, 'Expected NullPointerException');
        } catch (NullPointerException e) { }

        try {
            ds.setColumnMapping(null, null);
            System.assert(false, 'Expected NullPointerException');
        } catch (NullPointerException e) { }

        try {
            ds.setColumnMapping(0, 'Name');
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) { }

        try {
            ds.deserialize(null);
            System.assert(false, 'Expected NullPointerException');
        } catch (NullPointerException e) { }

        try {
            new CSVDeserializer.UnmappedValuesToMapField(null);
            System.assert(false, 'Expected NullPointerException');
        } catch (NullPointerException e) { }

        try {
            new CSVDeserializer.UnmappedValuesJsonSerializer(null, null);
            System.assert(false, 'Expected NullPointerException');
        } catch (NullPointerException e) { }
    }


    public static final String JSON_UNMAPPED = '''
[ {
  "value" : "My Account",
  "columnNumber" : 1,
  "columnHeader" : "Name",
  "overwrittenByColumnNumber" : 2,
  "overwrittenByColumnHeader" : "Name"
}, {
  "value" : "6",
  "columnNumber" : 2,
  "columnHeader" : "Name",
  "overwrittenByColumnNumber" : 3,
  "overwrittenByColumnHeader" : "Name"
}, {
  "value" : "2024-05-23T21:58:22.000+0000",
  "columnNumber" : 4,
  "columnHeader" : "Something Else"
}, {
  "value" : "",
  "columnNumber" : 5
} ]''';

    public static CSVDeserializer makeUnmappedDeserializer() {
        CSVDeserializer deserializer = new CSVDeserializer(body1);
        deserializer.setHeaders(new List<String> {'Name', 'Name', 'Name', 'Something Else'});
        deserializer.setFieldMapping('Name', 'Name');
        return deserializer;
    }

    @IsTest
    public static void testUnmappedValuesSObjectHandler() {
        assertSObjects(
            makeUnmappedDeserializer()
                .setUnmappedValuesSObjectHandler(
                    new CSVDeserializer.UnmappedValuesJsonSerializer('Description')
                ),
            Account.SObjectType,
            new List<SObject> {
                new Account(
                    Name='9.5',
                    Description=JSON_UNMAPPED
                )
            }
        );
    }

    public static final String JSON_UNMAPPED_2 = '''
[ {
  "value" : "9.5",
  "columnNumber" : 3,
  "columnHeader" : "Rating"
}, {
  "value" : "2024-05-23T21:58:22.000+0000",
  "columnNumber" : 4,
  "columnHeader" : "CreatedDate"
}, {
  "value" : "",
  "columnNumber" : 5,
  "columnHeader" : "Empty"
} ]''';
    
    @IsTest
    public static void testUnmappedValuesSObjectHandler2() {
        assertSObjects(
            new CSVDeserializer(body1)
                .setFieldMapping('Name', 'Name')
                .setColumnMapping(2, 'NumberOfEmployees', CSVDeserializer.INTEGER_CONVERTER)
                .setFieldForUnmappedValues('Description'), //test unmapped values without any overwrites
            Account.SObjectType,
            new List<SObject> {
                new Account(
                    Name='My Account',
                    NumberOfEmployees=6,
                    Description=JSON_UNMAPPED_2
                )
            }
        );
    }

    @IsTest
    public static void testUnmappedValuesMapHandler() {
        assertMaps(
            makeUnmappedDeserializer().setFieldForUnmappedValues('Description'),
            new List<Map<String, Object>> {
                new Map<String, Object> {
                    'Name' => '9.5',
                    'Description' => new List<CSVDeserializer.UnmappedValue> {
                        new CSVDeserializer.UnmappedValue(1, 'Name', 'My Account', 2, 'Name'),
                        new CSVDeserializer.UnmappedValue(2, 'Name', '6', 3, 'Name'),
                        new CSVDeserializer.UnmappedValue(4, 'Something Else', '2024-05-23T21:58:22.000+0000'),
                        new CSVDeserializer.UnmappedValue(5, null, '')
                    }
                }
            }
        );
    }

    @IsTest
    public static void testUnmappedValuesMapHandlerJSON() {
        assertMaps(
            makeUnmappedDeserializer()
                .setUnmappedValuesMapHandler(
                    new CSVDeserializer.UnmappedValuesJsonSerializer('Description')
                )
            ,
            new List<Map<String, Object>> {
                new Map<String, Object> {
                    'Name' => '9.5',
                    'Description' => JSON_UNMAPPED
                }
            }
        );
    }

    @IsTest
    public static void testUnmappedValueObject() {
        CSVDeserializer.UnmappedValue same1 = new CSVDeserializer.UnmappedValue(1, 'Name', 'My Account', 2, 'Name');
        CSVDeserializer.UnmappedValue same2 = new CSVDeserializer.UnmappedValue(1, 'Name', 'My Account', 2, 'Name');
        System.assertNotEquals(
            same1,
            new CSVDeserializer.UnmappedValue(1, 'Name', 'My Account')
        );
        
        System.assertEquals(same1, same2);
        System.assertEquals(same1, same1);
        
        Set<CSVDeserializer.UnmappedValue> hashTest = new Set<CSVDeserializer.UnmappedValue>();
        hashTest.add(same1);
        hashTest.add(same2);
        System.assertEquals(1, hashTest.size());
        System.assertEquals(same1.hashCode(), same2.hashCode());
        System.assert(!same1.equals(null));
    }

    @IsTest
    public static void testDeserializerConfigMethods() {
        CSVDeserializer ds = new CSVDeserializer();
        System.assertEquals(null, ds.getParser());
        System.assertEquals(null, ds.getHeaders());
        System.assertEquals(0, ds.getTargetFieldMappings().size());
        System.assertEquals(0, ds.getSourceColumnMappings().size());
        System.assertEquals(0, ds.getSourceFieldMappings().size());

        ds.setBody(body1, false);
        CSVParser parser1 = ds.getParser();
        System.assertNotEquals(null, parser1);
        System.assertEquals(null, ds.getHeaders());

        ds.setBody(body1);
        CSVParser parser2 = ds.getParser();
        System.assertNotEquals(null, parser2);
        System.assertNotEquals(parser1, parser2);
        System.assertNotEquals(null, ds.getHeaders());
        System.assertEquals(5, ds.getHeaders().size());

        ds.setColumnMapping(1, 'Name')
            .setColumnMapping(2, 'NumberOfEmployees')
            .setColumnMapping(2, 'Description')
            .setFieldMapping('Rating', 'Rating')
            .setFieldMapping('CreatedDate', 'CreatedDate')
            .setFieldMapping('CreatedDate', 'ModifiedDate')
            .setFieldForUnmappedValues('Unmapped', true);
        
        CSVDeserializer.FieldMapping mapping1 = ds.getTargetFieldMapping('Name');
        CSVDeserializer.FieldMapping mapping2_1 = ds.getTargetFieldMapping('NumberOfEmployees');
        CSVDeserializer.FieldMapping mapping2_2 = ds.getTargetFieldMapping('Description');
        CSVDeserializer.FieldMapping mapping3 = ds.getTargetFieldMapping('Rating');
        CSVDeserializer.FieldMapping mapping4_1 = ds.getTargetFieldMapping('CreatedDate');
        CSVDeserializer.FieldMapping mapping4_2 = ds.getTargetFieldMapping('ModifiedDate');

        System.assertEquals(6, ds.getTargetFieldMappings().size());
        System.assertEquals(2, ds.getSourceColumnMappings().size());
        System.assertEquals(2, ds.getSourceFieldMappings().size());

        List<CSVDeserializer.FieldMapping> mappings1 = ds.getSourceColumnMappings(1);
        List<CSVDeserializer.FieldMapping> mappings2 = ds.getSourceColumnMappings(2);
        List<CSVDeserializer.FieldMapping> mappings3 = ds.getSourceFieldMappings('Rating');
        List<CSVDeserializer.FieldMapping> mappings4 = ds.getSourceFieldMappings('CreatedDate');

        System.assertEquals(1, mappings1.size());
        System.assertEquals(2, mappings2.size());
        System.assertEquals(1, mappings3.size());
        System.assertEquals(2, mappings4.size());
        System.assertEquals(0, ds.getSourceColumnMappings(10).size());
        System.assertEquals(0, ds.getSourceFieldMappings('Nonexistent').size());
        
        System.assertEquals(mapping1, mappings1.get(0));
        System.assertEquals(mapping2_1, mappings2.get(0));
        System.assertEquals(mapping2_2, mappings2.get(1));
        System.assertEquals(mapping3, mappings3.get(0));
        System.assertEquals(mapping4_1, mappings4.get(0));
        System.assertEquals(mapping4_2, mappings4.get(1));

        CSVDeserializer.UnmappedValuesMapHandler mapHandler1 = ds.getUnmappedValuesMapHandler();
        CSVDeserializer.UnmappedValuesSObjectHandler sObjectHandler1 = ds.getUnmappedValuesSObjectHandler();
        System.assert(mapHandler1 instanceof CSVDeserializer.UnmappedValuesJsonSerializer);
        System.assert(sObjectHandler1 instanceof CSVDeserializer.UnmappedValuesJsonSerializer);
        System.assert((CSVDeserializer.UnmappedValuesJsonSerializer)mapHandler1 === (CSVDeserializer.UnmappedValuesJsonSerializer)sObjectHandler1);

        ds.setFieldForUnmappedValues('Description');
        ds.removeFieldMapping(mapping2_1);
        ds.removeFieldMapping(mapping4_1);
        
        mappings1 = ds.getSourceColumnMappings(1);
        mappings2 = ds.getSourceColumnMappings(2);
        mappings3 = ds.getSourceFieldMappings('Rating');
        mappings4 = ds.getSourceFieldMappings('CreatedDate');

        System.assertEquals(1, mappings1.size());
        System.assertEquals(0, mappings2.size());
        System.assertEquals(1, mappings3.size());
        System.assertEquals(1, mappings4.size());
        
        System.assertEquals(mapping1, mappings1.get(0));
        System.assertEquals(mapping3, mappings3.get(0));
        System.assertEquals(mapping4_2, mappings4.get(0));

        CSVDeserializer.UnmappedValuesMapHandler mapHandler2 = ds.getUnmappedValuesMapHandler();
        CSVDeserializer.UnmappedValuesSObjectHandler sObjectHandler2 = ds.getUnmappedValuesSObjectHandler();

        System.assert(sObjectHandler1 !== sObjectHandler2);
        System.assert(!(mapHandler2 instanceof CSVDeserializer.UnmappedValuesJsonSerializer));
        System.assert(sObjectHandler2 instanceof CSVDeserializer.UnmappedValuesJsonSerializer);
    }
}