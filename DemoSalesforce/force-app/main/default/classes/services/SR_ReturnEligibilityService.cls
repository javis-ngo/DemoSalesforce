public with sharing class SR_ReturnEligibilityService {
    public static Date resolveAnchorDate(Order orderRow) {
        if (orderRow == null) {
            return null;
        }
        return orderRow.Delivery_Date__c ?? orderRow.EffectiveDate;
    }

    public static Date resolveDeadline(Date anchorDate, SR_CategoryPolicy policy) {
        if (anchorDate == null || policy == null || policy.returnWindowDays == null) {
            return null;
        }
        return anchorDate.addDays(policy.returnWindowDays);
    }

    public static Decimal reservedQuantity(Id orderItemId, Map<Id, Decimal> reservedByOrderItemId) {
        if (orderItemId == null || reservedByOrderItemId == null || !reservedByOrderItemId.containsKey(orderItemId)) {
            return 0;
        }
        Decimal reserved = reservedByOrderItemId.get(orderItemId);
        return reserved == null || reserved < 0 ? 0 : reserved;
    }

    public static Decimal remainingQuantity(Decimal purchasedQuantity, Decimal reservedQuantity) {
        Decimal remaining = (purchasedQuantity == null ? 0 : purchasedQuantity) - (reservedQuantity == null ? 0 : reservedQuantity);
        return remaining < 0 ? 0 : remaining;
    }

    public static Boolean isCategoryReturnable(SR_CategoryPolicy policy) {
        return policy != null && policy.active == true && policy.isReturnable == true;
    }

    public static Boolean isWithinReturnWindow(Date todayValue, Date deadline) {
        return todayValue != null && deadline != null && todayValue <= deadline;
    }

    public static void populateLine(
        SR_ReturnableLineDTO dto,
        Order orderRow,
        OrderItem item,
        Map<Id, Decimal> reservedByOrderItemId,
        Date todayValue
    ) {
        if (dto == null || item == null) {
            return;
        }
        SR_CategoryPolicy policy = SR_Config.getCategoryPolicy(item.Product2 == null ? null : item.Product2.Family);
        dto.previouslyReturnedQuantity = reservedQuantity(item.Id, reservedByOrderItemId);
        dto.returnableQuantity = remainingQuantity(item.Quantity, dto.previouslyReturnedQuantity);
        dto.returnDeadline = resolveDeadline(resolveAnchorDate(orderRow), policy);
        applyLock(dto, policy, todayValue);
    }

    public static void applyLock(SR_ReturnableLineDTO dto, SR_CategoryPolicy policy, Date todayValue) {
        if (dto == null) {
            return;
        }
        dto.eligible = true;
        dto.lockCode = null;
        dto.lockMessage = null;
        if (policy == null || policy.active != true) {
            dto.eligible = false;
            dto.lockCode = SR_ErrorCode.CONFIGURATION_ERROR;
            dto.lockMessage = 'Không tìm thấy policy ngành hàng.';
        } else if (policy.isReturnable != true) {
            dto.eligible = false;
            dto.lockCode = SR_ErrorCode.NOT_RETURNABLE;
            dto.lockMessage = SR_ErrorCode.message(SR_ErrorCode.NOT_RETURNABLE);
        } else if (!isWithinReturnWindow(todayValue, dto.returnDeadline)) {
            dto.eligible = false;
            dto.lockCode = SR_ErrorCode.RETURN_WINDOW_EXPIRED;
            dto.lockMessage = SR_ErrorCode.message(SR_ErrorCode.RETURN_WINDOW_EXPIRED);
        } else if (dto.returnableQuantity == null || dto.returnableQuantity <= 0) {
            dto.eligible = false;
            dto.lockCode = SR_ErrorCode.QUANTITY_EXCEEDED;
            dto.lockMessage = SR_ErrorCode.message(SR_ErrorCode.QUANTITY_EXCEEDED);
        }
    }
}
