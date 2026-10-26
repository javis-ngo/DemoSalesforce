/**
 * Selector cho API POS/App (INT-02, Phụ lục E.2).
 *  - USER_MODE: integration user chỉ thấy yêu cầu được chia sẻ theo cửa hàng và field được cấp quyền (BR-16).
 *  - KHÔNG truy vấn Internal_Note__c (BR-18): field không có trong kết quả thì không thể lọt ra API.
 * Owner: Dev B
 */
public inherited sharing class SR_ReturnRequestApiSelector {

    // [DEV A] Field Return_Request__c / Line / History do Dev A sở hữu
    public static List<Return_Request__c> selectDetailByNumber(String requestNumber) {
        return [
            SELECT Id, Name, Status__c, Estimated_Refund__c, Actual_Refund__c, Order__r.OrderNumber,
                   (SELECT Id, Order_Product__r.Product2.ProductCode, Quantity__c, Inspection_Result__c,
                           Estimated_Refund__c, Actual_Refund__c
                    FROM Return_Request_Lines__r ORDER BY Name),
                   (SELECT Id, To_Status__c, Changed_At__c, CreatedDate
                    FROM Return_Request_Histories__r ORDER BY Changed_At__c, CreatedDate, Name)
            FROM Return_Request__c
            WHERE Name = :requestNumber
            WITH USER_MODE
            LIMIT 1
        ];
    }
}
