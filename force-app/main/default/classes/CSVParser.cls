/**
 * Parses CSV files into iterator of iterators of Strings.  Each CSVParser is a stateful iterator that returns
 * Rows (inner class), and each Row is a stateful iterator that return Strings
 */
public class CSVParser implements Iterator<CSVParser.Row>, Iterable<CSVParser.Row> {
    public static final Integer LF = '\n'.charAt(0);
    public static final Integer CR = '\r'.charAt(0);
    public static final Integer QT = '"'.charAt(0);
    public static final Integer CM = ','.charAt(0);
    public static final Integer SPACE = ' '.charAt(0);
    public static final Integer TAB = '\t'.charAt(0);

	public final String body;

    private Integer pos = 0; //current cursor position in parsing
    private Row currentRow = null;
    private Integer currentCellStartPos = null;
    private Integer currentCellEndPos = null;

    public CSVParser(String body) {
        this.body = body;
    }

    public CSVParser(Blob body) {
        this.body = body.toString();
    }

    public Iterator<Row> iterator() {
        return this;
    }

    public Boolean hasNext() {
        if (this.currentRow != null) {
             while (this.currentRow.hasNextToParse) {
                 this.currentRow.parsedCellQueue.add(this.parseNextCell());
            }
        }
        return this.pos < this.body.length();
    }

    public Row next() {
        if (!this.hasNext()) {
            throw new NoSuchElementException('CSVParser has no more rows in this document');
        }
        Row row = new Row(this);
        this.currentRow = row;
        return row;
    }

    public List<List<String>> toList() {
        List<List<String>> result = new List<List<String>>();
        for (Row row : this) {
            result.add(row.toList());
        }
        return result;
    }

    public Integer getPos() {
        return this.pos;
    }

    public Integer getCurrentCellStartPos() {
        return this.currentCellStartPos;
    }

    public Integer getCurrentCellEndPos() {
        return this.currentCellEndPos;
    }

    public Row getHeaderRow() {
        if (this.currentRow != null) {
            throw new NoSuchElementException('CSVParser.getHeaderRow can only be called before the CSVParser iterator has started');
        }
        return this.next();
    }

    public class Row implements Iterator<String>, Iterable<String> {
        private final CSVParser parent;
        private boolean hasNextToParse;
        private final List<String> parsedCellQueue = new List<String>();

        private Row(CSVParser parent) {
            this.parent = parent;
            this.hasNextToParse = parent.rowEndCheck();
        }

        public Iterator<String> iterator() {
            return this;
        }

        public Boolean hasNext() {
            return this.hasNextToParse || this.parsedCellQueue.size() > 0;
        }

        public String next() {
            if (this.parsedCellQueue.size() > 0) {
                String next = this.parsedCellQueue.get(0);
                this.parsedCellQueue.remove(0);
                return next;
            }
            if (!this.hasNextToParse) {
                throw new NoSuchElementException('CSVParser.Row has no more cells in this row');
            }
            return this.parent.parseNextCell();
        }
        
        public List<String> toList() {
            List<String> result = new List<String>();
            for (String cell : this) {
                result.add(cell);
            }
            return result;
        }

        public Integer getPos() {
            return this.parent.pos;
        }
    }

    // returns true if the row continues, false if the row ends
    private Boolean rowEndCheck() {
        if (this.pos >= this.body.length()) {
            return false;
        }
        if (this.body.charAt(this.pos) == LF) {
            this.pos++;
            if (this.pos < this.body.length() && this.body.charAt(this.pos) == CR) {
                this.pos++;
            }
            return false;
        } else {
            return true;
        }
    }
    
    private String parseNextCell() {
        this.currentCellStartPos = null;
        this.currentCellEndPos = null;
        if (this.currentRow == null  || !this.currentRow.hasNextToParse) {
            throw new CSVParsingException(this, 'Unexpected State');
        }

        if (this.pos >= this.body.length()) {
            // deal with the corner-case where the final cell in the document is an implied empty cell after a comma
            if (this.pos == this.body.length() && this.body.charAt(this.pos - 1) == CM) {
                this.currentCellStartPos = this.pos;
                this.currentCellEndPos = this.pos;
                this.currentRow.hasNextToParse = false;
                return '';
            }
            throw new CSVParsingException(this, 'Unexpected State: EOF');
        }

        this.currentCellStartPos = this.pos;
        if (this.body.charAt(this.pos) == QT) {
            return this.parseQuotedCell();
        } else {
            return this.parseUnquotedCell();
        }
    }
    
    private String parseQuotedCell() {
        Integer cellStart = this.pos;
        this.pos++;

        List<String> substrings = new List<String>();
        while (true) {
            Integer nextQt = this.body.indexOf('"', this.pos);
            if (nextQt == -1) {
                throw new CSVParsingException(this, 'Closing quote is missing', cellStart, this.body.length());
            }
            substrings.add(this.body.substring(this.pos, nextQt));
            this.pos = nextQt + 1;
            if (this.pos >= this.body.length()) {
                //End of file
                this.currentRow.hasNextToParse = false;
                break;
            }
            Integer charAt = this.body.charAt(this.pos);
            if (charAt == QT) {
                this.pos++;
            } else if (charAt == LF) {
                this.currentCellEndPos = this.pos;
                this.currentRow.hasNextToParse = rowEndCheck();
                break;
            } else if (charAt == CM) {
                this.currentCellEndPos = this.pos;
                this.pos++;
                // there is always an implied cell after a comma, even if it is empty.  Therefore, we do NOT perform rowEndCheck() here
                break;
            } else {
                throw new CSVParsingException(this, 'Unexpected character after closing quote', cellStart, this.pos + 1);
            }
        }        
        return String.join(substrings, '"');
    }
    
    private String parseUnquotedCell() {
        Integer nextCommaOrLF = this.nextIndex(',', '\n');
        Integer nextQuoteOrCR = this.nextIndex('"', '\r');
        Integer start = this.pos;
        if (nextQuoteOrCR == -1) {
            if (nextCommaOrLF == -1) {
                // End of file
                this.pos = this.body.length();
                this.currentCellEndPos = this.pos;
                this.currentRow.hasNextToParse = false;
                return this.body.substring(start);
            }
        } else if (nextCommaOrLF == -1 || nextCommaOrLF >= nextQuoteOrCR) {
            if (this.body.charAt(nextQuoteOrCR) == QT) {
                //check for whitespace preceding quoted cell
                Boolean onlyWS = true;
                for (Integer pos = this.pos; pos < nextQuoteOrCR; pos++) {
                    Integer charCode = this.body.charAt(pos);
                    if (!(charCode == SPACE || charCode == TAB)) {
                        onlyWS = false;
                        break;
                    }
                }
                if (onlyWS) {
                    this.pos = nextQuoteOrCR;
                    return this.parseQuotedCell();
                }
            }
            throw new CSVParsingException(this, 'Unexpected quotation mark or carriage return before expected comma or newline (parsing unquoted cell)', this.pos, nextQuoteOrCR + 1);
        }
        this.currentCellEndPos = nextCommaOrLF;
        if (this.body.charAt(nextCommaOrLF) == CM) {
            this.pos = nextCommaOrLF + 1;
            // there is always an implied cell after a comma, even if it is empty.  Therefore, we do NOT perform rowEndCheck() here
        } else {
            this.pos = nextCommaOrLF;
            this.currentRow.hasNextToParse = rowEndCheck();
        }
        return this.body.substring(start, nextCommaOrLF);
    }
    
    private Integer nextIndex(String char1, String char2) {
        Integer index1 = this.body.indexOf(char1, this.pos);
        Integer index2 = this.body.IndexOf(char2, this.pos);
        if (index1 != -1) {
            if (index2 != -1) {
                return Math.min(index1, index2);
            }
            return index1;
        } 
        return index2;
    }

    private Integer exceptionStartPos() {
        if (this.currentCellStartPos != null) {
            return this.currentCellStartPos;
        } else {
            return Math.max(this.pos - 10, 0);
        }
    }

    private Integer exceptionEndPos() {
        if(this.currentCellEndPos != null) {
            return this.currentCellEndPos;
        } else {
            return Math.min(this.pos + 10, this.body.length());
        }
    }

    virtual public class CSVParsingException extends Exception {
        protected CSVParsingException(CSVParser parser, String msg) {
            this(parser, msg, parser.exceptionStartPos());
        }

        protected CSVParsingException(CSVParser parser, String msg, Boolean invalidateParser) {
            this(parser, msg, parser.exceptionStartPos(), invalidateParser);
        }

        protected CSVParsingException(CSVParser parser, String msg, Integer startIndex) {
            this(parser, msg, startIndex, parser.exceptionEndPos());
        }

        protected CSVParsingException(CSVParser parser, String msg, Integer startIndex, Boolean invalidateParser) {
            this(parser, msg, startIndex, parser.exceptionEndPos(), invalidateParser);
        }

        protected CSVParsingException(CSVParser parser, String msg, Integer startIndex, Integer endIndex) {
            this(parser, msg, startIndex, endIndex, true);
        }

        protected CSVParsingException(CSVParser parser, String msg, Integer startIndex, Integer endIndex, Boolean invalidateParser) {
            this(msg + '\nDocument character position: ' + parser.pos + '\n' + parser.body.substring(startIndex, endIndex));
            if (invalidateParser) {
                parser.pos = parser.body.length();
                if (parser.currentRow != null) {
                    parser.currentRow.hasNextToParse = false;
                }
            }
        }
    }
}