/**
 * Test cho SR_ReturnUiController (D.1): controller báo lỗi dễ đọc khi dữ liệu sai.
 * Luồng tạo yêu cầu đầy đủ nằm ở SR_UiControllerTest.
 * Owner: Dev C
 */
@IsTest
private class SR_ReturnUiControllerTest {

    // JSON nháp hỏng: không lộ lỗi hệ thống, báo MSG-90 kèm mã lỗi
    @IsTest
    static void badInputGivesReadableError() {
        String msg90Start = System.Label.SR_MSG_90.substringBefore('{0}');
        try {
            SR_ReturnUiController.previewCreate('không phải JSON');
            Assert.fail('Phải báo lỗi khi dữ liệu nháp sai');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().startsWith(msg90Start), e.getMessage());
        }
        try {
            SR_ReturnUiController.createFromCounter('{');
            Assert.fail('Phải báo lỗi khi dữ liệu tạo sai');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().startsWith(msg90Start), e.getMessage());
        }
    }

    // Không có đơn: trả DTO rỗng để màn hình báo, không throw
    @IsTest
    static void missingOrderGivesEmptyResult() {
        SR_ReturnableOrderDTO info = SR_ReturnUiController.getReturnableOrder(null);
        Assert.isNull(info.orderId);
        Assert.isTrue(info.lines.isEmpty());
    }
}
