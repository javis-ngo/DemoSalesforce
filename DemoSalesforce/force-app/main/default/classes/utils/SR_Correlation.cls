public class SR_Correlation {
    public static String newId() {
        String raw = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(
            String.valueOf(System.now().getTime()) + ':' + String.valueOf(Crypto.getRandomLong())
        )));
        return raw.substring(0, 32);
    }
}
