/**
 * Selector cho Return_Request_Line__c (dòng sản phẩm của yêu cầu).
 * "inherited sharing": chạy theo sharing của class gọi; màn hình nội bộ nên truy vấn USER_MODE.
 * Owner: Dev C
 */
public inherited sharing class SR_ReturnRequestLineSelector {

    // D.3: đủ thông tin để tính lại tiền 1 dòng khi đổi tình trạng thực tế
    public static Return_Request_Line__c selectById(Id lineId) {
        return [
            SELECT Id, Reason__c, Unit_Price__c, Quantity__c FROM Return_Request_Line__c
            WHERE Id = :lineId
            WITH USER_MODE
        ];
    }
}
