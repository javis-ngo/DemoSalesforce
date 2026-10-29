public class SR_ConfigurationException extends Exception {
    public String errorCode { get; private set; }

    public SR_ConfigurationException(String errorCode, String message) {
        this.errorCode = errorCode;
        this.setMessage(message);
    }
}

