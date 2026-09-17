/**
 * Re-usable class for HTTP Mock Callouts in Apex Tests, that can auto-install itself upon creation,
 * and tracks each request submitted.  Test classes can modify the static 'default' variables for their
 * own purposes, or pass desired values into the constructors.  The respond method can also be overridden
 * by custom subclasses if desired, as well as the makeException method in the ExceptionThrower subclass.
 * 
 * Used for testing only, but the @IsTest annotation is not allowed on virtual classes.
 * 
 * Created By: Bill Anderson
 * Created On: 6-15-2026
 */
virtual public class HttpMock implements HttpCalloutMock {
    // static defaults for HttpMock, can be adjusted so each new instance uses these values by default (unless overridden by the constructor)
    public static Boolean autoInstall = true;
    public static Integer defaultStatus = 200;
    public static String defaultBody = '{"status": "success"}';
    public static Map<String, String> defaultHeaders = new Map<String, String> {
        'Content-Type' => 'application/json'
    };


    // instance variables
    public List<HttpRequest> requests = new List<HttpRequest>();
    public Integer status;
    public String body = defaultBody;
    public Map<String, String> headers = new Map<String, String>(defaultHeaders);

    public HttpMock() {
        this(defaultStatus, autoInstall);
    }

    public HttpMock(Integer status) {
        this(status, autoInstall);
    }

    public HttpMock(Boolean autoInstall) {
        this(defaultStatus, autoInstall);
    }

    public HttpMock(Integer status, Boolean autoInstall) {
        this.status = status;
        if (autoInstall) {
            Test.setMock(HttpCalloutMock.class, this);
        }
    }

    virtual public HttpResponse respond(HttpRequest request) {
        this.requests.add(request);
        HttpResponse response = new HttpResponse();
        for (String header : this.headers.keySet()) {
            response.setHeader(header, this.headers.get(header));
        }
        response.setBody(this.body);
        response.setStatusCode(this.status);
        return response;
    }

    //static defaults for ExceptionThrower, can be adjusted so each new instance uses these values by default (unless overridden by the constructor)
    public static String defaultExceptionMsg = 'Callout Exception';
    public static Type defaultExceptionType = CalloutException.class;

    virtual public class ExceptionThrower extends HttpMock {
        public String msg;
        public Type exceptionType;

        public ExceptionThrower() {
            this(defaultExceptionMsg, defaultExceptionType, autoInstall);
        }

        public ExceptionThrower(String msg) {
            this(msg, defaultExceptionType, autoInstall);
        }

        public ExceptionThrower(String msg, Type exceptionType) {
            this(msg, exceptionType, autoInstall);
        }
    
        public ExceptionThrower(String msg, Type exceptionType, Boolean autoInstall) {
            super(autoInstall);
            this.msg = msg;
            if (!Exception.class.isAssignableFrom(exceptionType)) {
                throw new TypeException('exceptionType argument must be a subclass of Exception.  Actual ' + exceptionType);
            }
            this.exceptionType = exceptionType;
        }
        
        override virtual public HttpResponse respond(HttpRequest request) {
            this.requests.add(request);
            throw this.makeException();
        }
        
        virtual public Exception makeException() {
            Exception e = (Exception)this.exceptionType.newInstance();
            e.setMessage(this.msg);
            return e;
        }
    }
}