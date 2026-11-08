public without sharing class SR_Util {

    private SR_Util() {
        // Utility class.
    }

    /**
     * Format chuỗi chứa placeholder {0}, {1}, {2}...
     *
     * Ví dụ:
     * SR_Util.format(
     * 'Không thể chuyển từ {0} sang {1}.',
     * new List<Object>{ 'COMPLETED', 'INSPECTING' }
     * );
     */
    public static String format(
        String template,
        List<Object> parameters
    ) {
        if (template == null) {
            return null;
        }

        if (parameters == null || parameters.isEmpty()) {
            return template;
        }

        List<String> stringParameters = new List<String>();

        for (Object parameter: parameters) {
            stringParameters.add(
                parameter == null
                    ? ''
                    : String.valueOf(parameter)
            );
        }

        return String.format(template, stringParameters);
    }

    /**
     * Chuẩn hóa chuỗi trước khi so sánh.
     */
    public static String normalize(String value) {
        return String.isBlank(value)
            ? null
            : value.trim().toUpperCase();
    }

    /**
     * Lấy N ký tự cuối, dùng cho Portal kiểm tra 4 số cuối SĐT.
     */
    public static String right(String value, Integer length) {
        if (
            String.isBlank(value) ||
            length == null ||
            length <= 0
        ) {
            return null;
        }

        String normalized = value.trim();

        if (normalized.length() <= length) {
            return normalized;
        }

        return normalized.substring(
            normalized.length() - length
        );
    }
}