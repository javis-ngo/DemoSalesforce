/**
 * Hàm dùng chung cho các controller LWC (D.1–D.4).
 * SR_Util của Dev A không có auraError / picklistLabel nên đặt riêng ở đây, không sửa file của Dev A.
 * Owner: Dev C
 */
public inherited sharing class SR_UiUtil {

    private SR_UiUtil() {
    }

    /**
     * Lỗi trả về LWC. AuraHandledException đã soạn sẵn câu (vd MSG-20) thì giữ nguyên;
     * lỗi khác ghi Nhật ký lỗi rồi báo MSG-90 kèm mã lỗi để người dùng báo hỗ trợ (NFR-09).
     */
    public static AuraHandledException auraError(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        SR_Logger logger = SR_Logger.getInstance();
        String code = logger.errorWithCode('SR_UiUtil.auraError', 'LWC', e, null);
        logger.push();
        return auraException(SR_Util.format(System.Label.SR_MSG_90, new List<Object>{ code }));
    }

    // setMessage để getMessage() trả đúng câu báo thay vì "Script-thrown exception"
    public static AuraHandledException auraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    // Nhãn tiếng Việt của giá trị picklist; không thấy thì trả lại chính giá trị
    public static String picklistLabel(Schema.SObjectField field, String value) {
        if (field == null || String.isBlank(value)) {
            return value;
        }
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.getValue() == value) {
                return entry.getLabel();
            }
        }
        return value;
    }

    // Token chống ghi đè: cùng cách tính với SR_ApprovalService / SR_InspectionService (LastModifiedDate tính bằng ms)
    public static String versionTokenOf(Datetime lastModified) {
        return (lastModified == null) ? null : String.valueOf(lastModified.getTime());
    }
}
