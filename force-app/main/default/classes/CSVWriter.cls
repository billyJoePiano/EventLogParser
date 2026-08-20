public class CSVWriter {
    public enum LineSeparator { LF, CRLF }
    public static final LineSeparator LF = LineSeparator.LF;
    public static final LineSeparator CRLF = LineSeparator.CRLF;

    public static LineSeparator defaultLineSeparator = CRLF;
    public static Boolean defaultNullIsEmpty = true;
    public static Boolean defaultAlwaysQuote = false;

    public final LineSeparator lineSeparator;
    public final Boolean nullIsEmpty;
    public final Boolean alwaysQuote;

    private final List<String> rowsRaw = new List<String>();

    public CSVWriter() {
        this(defaultLineSeparator, defaultNullIsEmpty, defaultAlwaysQuote);
    }

    public CSVWriter(LineSeparator lineSeparator, Boolean nullIsEmpty, Boolean alwaysQuote) {
        if (lineSeparator == null || nullIsEmpty == null || alwaysQuote == null) {
            throw new NullPointerException();
        }
        this.lineSeparator = lineSeparator;
        this.nullIsEmpty = nullIsEmpty;
        this.alwaysQuote = alwaysQuote;
    }

    public CSVWriter writeRows(List<List<Object>> rows) {
        for (List<Object> row : rows) {
            this.writeRow(row);
        }
        return this;
    }

    public CSVWriter writeRow(List<Object> row) {
        // deal with edge cases: empty row, and a row with a single empty cell
        if (row == null || row.size() < 1) {
            this.rowsRaw.add('');
            return this;
        } else if (row.size() == 1) {
            Object value = row.get(0);
            if (value == null || String.valueOf(value) == '') {
                this.rowsRaw.add('""');
                return this;
            }
        }
        List<String> cellsStr = new List<String>();
        for (Object value : row) {
            String strVal;
            if (value == null && this.nullIsEmpty) {
                strVal = '';
            } else {
                strVal = String.valueOf(value);
            }
            if (this.alwaysQuote || strVal.contains('"') || strVal.contains(',') || strVal.contains('\n') || strVal.contains('\r')) {
                strVal = '"' + strVal.replace('"', '""') + '"';
            }
            cellsStr.add(strVal);
        }
        this.rowsRaw.add(String.join(cellsStr, ','));
        return this;
    }

    public Blob toBlob() {
        return Blob.valueOf(String.join(this.rowsRaw, this.lineSeparator == LF ? '\n' : '\r\n'));
    }

    public Id writeRowsAsync(List<List<Object>> rows, BatchableLogger originator, AsyncCallback callback) {
        return new Async(originator, this, rows, callback).enqueue();
    }

    public Id writeToStaticResourceAsync(List<List<Object>> rows, BatchableLogger originator, String caller, String staticResourceName, String staticResourceDescription, Boolean staticResourceCachePublic) {
        return this.writeRowsAsync(rows, originator, new AsyncCallbackStaticResourceWriterAndLogger(caller, staticResourceName, staticResourceDescription, staticResourceCachePublic));
    }

    public class Async extends AsyncProcessor.WithFinish implements Database.AllowsCallouts {
        public final CSVWriter writer;
        public final AsyncCallback callback;

        private Async(BatchableLogger originator, CSVWriter writer, List<List<Object>> rows, AsyncCallback callback) {
            super(originator, new CannibalizingListIterator(rows));
            if (writer == null || rows == null || callback == null) {
                throw new NullPointerException();
            }
            this.writer = writer;
            this.callback = callback;
        }

        override public void execute(QueueableContext qc, AsyncIterator it) {
            try {
                for (Object row : it) {
                    this.writer.writeRow((List<Object>)row);
                }
            } catch (Exception e) {
                if (this.callback instanceof AsyncCallbackWithErrorHandler) {
                    ((AsyncCallbackWithErrorHandler)this.callback).error(e);
                } else {
                    throw e;
                }
            }
        }

        override public void finish(QueueableContext qc) {
            this.callback.done(this.writer);
        }
    }

    public interface AsyncCallback {
        void done(CSVWriter writer);
    }

    public interface AsyncCallbackWithErrorHandler extends AsyncCallback {
        void error(Exception e);
    }

    public abstract class AsyncCallbackWithResult implements AsyncCallback {
        public void done(CSVWriter writer) {
            this.done(writer.toBlob());
        }

        public abstract void done(Blob result);
    }

    public abstract class AsyncCallbackWithResultAndErrorHandler extends AsyncCallbackWithResult implements AsyncCallbackWithErrorHandler { }
    
    public class AsyncCallbackStaticResourceWriterAndLogger extends AsyncCallbackWithResultAndErrorHandler {
        public final String caller;
        public final String staticResourceName;
        public final String staticResourceDescription;
        public final Boolean staticResourceCachePublic;

        private AsyncCallbackStaticResourceWriterAndLogger(String caller, String staticResourceName, String staticResourceDescription, Boolean staticResourceCachePublic) {
            this.caller = caller;
            this.staticResourceName = staticResourceName;
            this.staticResourceDescription = staticResourceDescription;
            this.staticResourceCachePublic = staticResourceCachePublic;
        }

        override public void done(Blob result) {
            // setLoggerTransactionId() is already run by AsyncProcessor.execute(), via Async class (above)
            new StaticResourceUtil(this.caller)
                .updateCsvStaticResource(this.staticResourceName, this.staticResourceDescription, this.staticResourceCachePublic, result);
        }

        public void error(Exception e) {
            // setLoggerTransactionId() is already run by AsyncProcessor.execute(), via Async class (above)
            Logger.error(this.caller, e);
            Logger.saveLog();
        }
    }
}