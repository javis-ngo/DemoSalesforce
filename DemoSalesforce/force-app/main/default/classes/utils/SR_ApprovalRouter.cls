public inherited sharing class SR_ApprovalRouter {
    public static final String LEVEL_AUTO = 'AUTO';
    public static final String LEVEL_CHT = 'CHT';
    public static final String LEVEL_QLV = 'QLV';

    private static final Set<String> SUPPORTED_CHANNELS = new Set<String>{
        'COUNTER', 'POS', 'APP'
    };

    public static SR_ApprovalPreviewResultDTO route(
        SR_ApprovalPreviewDTO input,
        Store__c storeRow
    ) {
        if (input == null) {
            return failure(
                SR_ErrorCode.MISSING_FIELD,
                'Approval preview input không được null.'
            );
        }
        if (input.estimatedRefund == null) {
            return failure(
                SR_ErrorCode.MISSING_FIELD,
                'estimatedRefund là bắt buộc.'
            );
        }
        if (input.estimatedRefund < 0) {
            return failure(
                SR_ErrorCode.INVALID_VALUE,
                'estimatedRefund không được âm.'
            );
        }
        if (String.isBlank(input.channel) ||
            !SUPPORTED_CHANNELS.contains(input.channel.trim().toUpperCase())) {
            return failure(
                SR_ErrorCode.INVALID_VALUE,
                'channel phải là COUNTER, POS hoặc APP.'
            );
        }

        Decimal autoThreshold = SR_Config.autoApprovalThreshold();
        Decimal managerThreshold = SR_Config.storeManagerMaxThreshold();
        if (autoThreshold == null || managerThreshold == null ||
            autoThreshold < 0 || managerThreshold < autoThreshold) {
            return failure(
                SR_ErrorCode.CONFIGURATION_ERROR,
                'Cấu hình ngưỡng duyệt không hợp lệ.'
            );
        }

        String channel = input.channel.trim().toUpperCase();
        Decimal amount = input.estimatedRefund;
        Boolean risk = input.riskFlag == true;

        if (risk || amount > managerThreshold) {
            if (storeRow == null || storeRow.Regional_Manager__c == null) {
                return failure(
                    SR_ErrorCode.CONFIGURATION_ERROR,
                    'Không xác định được Quản lý vùng cho cửa hàng.'
                );
            }
            return success(
                LEVEL_QLV,
                storeRow.Regional_Manager__c,
                SR_StatusMachine.PENDING_APPROVAL
            );
        }

        if (SR_Config.isAutoApprovalEnabled() && amount <= autoThreshold) {
            return success(
                LEVEL_AUTO,
                null,
                channel == 'APP'
                    ? SR_StatusMachine.AWAITING_GOODS
                    : SR_StatusMachine.INSPECTING
            );
        }

        if (storeRow != null && storeRow.Store_Manager__c != null) {
            return success(
                LEVEL_CHT,
                storeRow.Store_Manager__c,
                SR_StatusMachine.PENDING_APPROVAL
            );
        }

        // Fallback bắt buộc của DUC-06: Store không có CHT thì chuyển QLV.
        if (storeRow != null && storeRow.Regional_Manager__c != null) {
            return success(
                LEVEL_QLV,
                storeRow.Regional_Manager__c,
                SR_StatusMachine.PENDING_APPROVAL
            );
        }

        return failure(
            SR_ErrorCode.CONFIGURATION_ERROR,
            'Cửa hàng chưa cấu hình Cửa hàng trưởng hoặc Quản lý vùng.'
        );
    }

    private static SR_ApprovalPreviewResultDTO success(
        String approvalLevel,
        Id assignedApproverId,
        String targetStatus
    ) {
        SR_ApprovalPreviewResultDTO result = new SR_ApprovalPreviewResultDTO();
        result.success = true;
        result.approvalLevel = approvalLevel;
        result.assignedApproverId = assignedApproverId;
        result.targetStatus = targetStatus;
        return result;
    }

    private static SR_ApprovalPreviewResultDTO failure(
        String errorCode,
        String message
    ) {
        SR_ApprovalPreviewResultDTO result = new SR_ApprovalPreviewResultDTO();
        result.success = false;
        result.errorCode = errorCode;
        result.message = message;
        return result;
    }
}