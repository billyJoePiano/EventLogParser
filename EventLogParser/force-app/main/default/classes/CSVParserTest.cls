@IsTest
public class CSVParserTest {
    // These are used when an exception is expected, to verify how far the verifications got before the exception was thrown
    public static Integer verifiedRows = 0;
    public static Integer verifiedCells = 0; //cells verified in current row, prior to exception being thrown
    
    public static void assertParsing(String body, List<List<String>> expected) {
        assertParsing(new CSVParser(Blob.valueOf(body)), expected);
    }
    
    public static void assertParsing(Iterable<Iterable<String>> parser, List<List<String>> expected) {
        Integer rowIndex = 0;
        verifiedRows = 0;
        verifiedCells = -1;

        for (Iterable<String> actualRow : parser) {
            Integer colIndex = 0;
            verifiedCells = 0;

            System.assert(rowIndex < expected.size(), 'Actual has more rows than expected. Expected size: ' + expected.size());
            List<String> expectedRow = expected.get(rowIndex);
            rowIndex++;
            
            for (String actualCell : actualRow) {
                System.assert(colIndex < expectedRow.size(), 'Actual row # ' + rowIndex + ' has more columns than expected. Expected: ' + expectedRow.size());
                System.assertEquals(expectedRow.get(colIndex), actualCell, 'Cell value in row # ' + rowIndex + ' column # ' + (colIndex + 1));
                colIndex++;
                verifiedCells = colIndex;
            }
            System.assertEquals(expectedRow.size(), colIndex, 'Number of cells in row # ' + rowIndex);

            verifiedRows = rowIndex;
            verifiedCells = -1;
        }
        System.assertEquals(expected.size(), rowIndex, 'Number of rows');
    }

    @IsTest
    public static void testEmpty() {
        assertParsing('', new List<List<String>>());
    }

    @IsTest
    public static void testEmptyRow() {
        List<List<String>> expected = new List<List<String>> { new List<String>() };
        assertParsing('\n', expected);
        assertParsing('\n\r', expected);
    }

    @IsTest
    public static void testEmptyCells() {
        List<List<String>> expected = new List<List<String>> { new List<String> {'',''}, new List<String> {'',''}};
        assertParsing(',\n,', expected);
        assertParsing('"",""\n"",""', expected);
        assertParsing('"",\n,""', expected);
        assertParsing(',""\n"",', expected);
        //same as above, but with a trailing newline
        assertParsing(',\n,\n', expected);
        assertParsing('"",""\n"",""\n', expected);
        assertParsing('"",\n,""\n', expected);
        assertParsing(',""\n"",\n', expected);
        //same again, but with trailing LFCR
        assertParsing(',\n\r,\n\r', expected);
        assertParsing('"",""\n\r"",""\n\r', expected);
        assertParsing('"",\n\r,""\n\r', expected);
        assertParsing(',""\n\r"",\n\r', expected);
    }

    @IsTest
    public static void testUnquotedCells() {
        assertParsing('text1,text2\ntext3', new List<List<String>> { new List<String> {'text1','text2'}, new List<String> {'text3'}});
    }

    @IsTest   
    public static void testEscapedQuotesAndNewlines() {
        assertParsing('"""text in quotes""","text\n""in quotes"" 2"', new List<List<String>> { new List<String> {'"text in quotes"', 'text\n"in quotes" 2'}});
    }

    @IsTest
    public static void testWhitespaceAfterComma() {
        assertParsing('test1, test2, \t "test3"', new List<List<String>> { new List<String> {'test1', ' test2', 'test3'}});
    }

    @IsTest
    public static void testInvalidUnquotedCell() {
        try {
            assertParsing('cell1,cell2",cell3', new List<List<String>> { new List<String> {'cell1'}});
            System.assert(false, 'Expected CSVParsingException');
        } catch (CSVParser.CSVParsingException e) {
            System.assertEquals('Unexpected quotation mark or carriage return before expected comma or newline (parsing unquoted cell)\nDocument character position: 6\ncell2"', e.getMessage());
        }
        System.assertEquals(0, verifiedRows);
        System.assertEquals(1, verifiedCells);
    }

    @IsTest
    public static void testInvalidQuotedCell1() {
        try {
            assertParsing('cell1,"cell2,cell3', new List<List<String>> { new List<String> {'cell1'}});
            System.assert(false, 'Expected CSVParsingException');
        } catch (CSVParser.CSVParsingException e) {
            System.assertEquals('Closing quote is missing\nDocument character position: 7\n"cell2,cell3', e.getMessage());
        }
        System.assertEquals(0, verifiedRows);
        System.assertEquals(1, verifiedCells);
    }

    @IsTest
    public static void testInvalidQuotedCell2() {
        try {
            assertParsing('cell1,"cell2,cell3"!', new List<List<String>> { new List<String> {'cell1'}});
            System.assert(false, 'Expected CSVParsingException');
        } catch (CSVParser.CSVParsingException e) {
            System.assertEquals('Unexpected character after closing quote\nDocument character position: 19\n"cell2,cell3"!', e.getMessage());
        }
        System.assertEquals(0, verifiedRows);
        System.assertEquals(1, verifiedCells);
    }

    @IsTest
    public static void testGetHeaderRow() {
        CSVParser parser = new CSVParser('Header1,Header2\nData1.1,Data1.2\nData2.1,Data2.2');
        Integer counter = 1;
        for (String actual : parser.getHeaderRow()) {
            System.assertEquals('Header' + counter, actual);
            counter++;
        }
        try {
            parser.getHeaderRow();
            System.assert(false, 'Exepected NoSuchElementException');
        } catch (NoSuchElementException e) {
            System.assertEquals('CSVParser.getHeaderRow can only be called before the CSVParser iterator has started', e.getMessage());
        }
        System.assertEquals(3, counter);
        assertParsing(parser, new List<List<String>> { new List<String> {'Data1.1','Data1.2'}, new List<String> {'Data2.1','Data2.2'}});
    }

    @IsTest
    public static void testIterator() {
        CSVParser parser = new CSVParser('test1,test2\ntest3,test4');
        System.assert(parser.hasNext());

        CSVParser.Row row = parser.next();
        System.assert(parser.hasNext());
        System.assert(row.hasNext());
        System.assertEquals(row.next(), 'test1');
        System.assert(row.hasNext());
        System.assertEquals(row.next(), 'test2');
        System.assert(!row.hasNext());
        try {
            row.next();
            System.assert(false, 'Expected NoSuchElementException');
        } catch (NoSuchElementException e) { }
        
        row = parser.next();
        System.assert(!parser.hasNext());
        System.assert(row.hasNext());
        System.assertEquals(row.next(), 'test3');
        System.assert(row.hasNext());
        System.assertEquals(row.next(), 'test4');
        System.assert(!row.hasNext());
        try {
            row.next();
            System.assert(false, 'Expected NoSuchElementException');
        } catch (NoSuchElementException e) { }
        
        try {
            parser.next();
            System.assert(false, 'Expected NoSuchElementException');
        } catch (NoSuchElementException e) { }
    }

    @IsTest
    public static void testToList() {
        CSVParser parser = new CSVParser('test1,test2\ntest3,test4');
        List<List<String>> expected = new List<List<String>> { new List<String> {'test1','test2'}, new List<String> {'test3','test4'}};
        assertParsing(parser.toList(), expected);
    }
}