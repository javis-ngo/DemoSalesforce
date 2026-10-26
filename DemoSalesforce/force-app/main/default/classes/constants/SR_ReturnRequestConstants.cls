public class SR_ReturnRequestConstants {
    public static final String STATUS_REJECTED = 'REJECTED';
    public static final String STATUS_CANCELLED = 'CANCELLED';

    public static Set<String> getReservationExcludedStatuses() {
        return new Set<String>{
            STATUS_REJECTED,
            STATUS_CANCELLED
        };
    }

    private SR_ReturnRequestConstants() {
    }
}