@IsTest
public class CSVWriterTest {
    @IsTest
    public static void testAsyncWrite() {
        List<List<Object>> rows = new List<List<Object>> {
            new List<Object> { '1', '\n', '"', ',', null, '' },
            null,
            new List<Object> { '' }
        };

        Test.startTest();
        CSVWriter writer = new CSVWriter();
        CSVWriter.AsyncCallbackStaticResourceWriterAndLogger callback = new CSVWriter.AsyncCallbackStaticResourceWriterAndLogger('CSVWriterTest.testAsyncWriter', 'StaticResourceName', 'StaticResourceDescription', true);
        CSVWriter.AsyncCSVProcessor proc = new CSVWriter.AsyncCSVProcessor(new BatchableLogger(), writer, rows, callback);
        
        proc.executeSync(false);
        System.assertEquals(3, writer.rowsRaw.size());
        System.assertEquals(0, rows.size());
        System.assertEquals('1,"\n","""",",",,', writer.rowsRaw.get(0));
        System.assertEquals('', writer.rowsRaw.get(1));
        System.assertEquals('""', writer.rowsRaw.get(2));

        StaticResourceUtil.mockResource = null;
        StaticResourceUtil.useMockResource = true;
        HttpMock mock = new HttpMock(201);

        proc.executeSync(false);
        Test.stopTest();

        Boolean callout = false;
        String url = URL.getOrgDomainUrl().toExternalForm() + '/services/data/v66.0/tooling/sobjects/StaticResource';
        for (HttpRequest request : mock.requests) {
            if (request.getEndpoint() == url) {
                callout = true;
            }
        }
        System.assert(callout, 'Callout expected to URL ' + url + ' , actual number of callouts: ' + mock.requests.size());
    }

    @IsTest
    public static void testSyncWrite() {
        List<List<Object>> rows = new List<List<Object>> {
            new List<Object> { '1', '\n', '"', ',', null, '' },
            null,
            new List<Object> { '' }
        };
        CSVWriter writer = new CSVWriter();
        writer.writeRows(rows);

        System.assertEquals(3, writer.rowsRaw.size());
        System.assertEquals(3, rows.size());
        System.assertEquals('1,"\n","""",",",,', writer.rowsRaw.get(0));
        System.assertEquals('', writer.rowsRaw.get(1));
        System.assertEquals('""', writer.rowsRaw.get(2));
    }
}