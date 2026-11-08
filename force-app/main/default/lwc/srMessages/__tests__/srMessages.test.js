import { formatLabel, msg, msgFromError } from 'c/srMessages';

jest.mock(
    '@salesforce/label/c.SR_MSG_04',
    () => ({ default: 'Số lượng trả của {0} vượt quá số lượng còn được trả ({1}).' }),
    { virtual: true }
);
jest.mock(
    '@salesforce/label/c.SR_MSG_13',
    () => ({ default: 'Yêu cầu {0} vừa được người khác cập nhật. Vui lòng tải lại.' }),
    { virtual: true }
);

// Label không mock thì Jest trả về chính tên label (vd "c.SR_MSG_12"), nên so sánh qua msg()
describe('c/srMessages', () => {
    it('thay {0}, {1}, {2} theo thứ tự, thiếu tham số thì để trống', () => {
        expect(formatLabel('Đã xử lý {0}/{1} yêu cầu. Không xử lý được: {2}.', 8, 10, 2)).toBe(
            'Đã xử lý 8/10 yêu cầu. Không xử lý được: 2.'
        );
        expect(formatLabel('{0}-{1}', 'A')).toBe('A-');
    });

    it('nhận tên label ở nhiều dạng, tên sai thì trả lại chính tên đó', () => {
        expect(msg('MSG-04')).toBe(msg('SR_MSG_04'));
        expect(msg('KHONG_CO')).toBe('KHONG_CO');
    });

    it('đổi lỗi của service (mã theo SR_ErrorCode / SR_StatusMachine) thành câu hiển thị', () => {
        expect(msgFromError({ code: 'REJECTION_REASON_REQUIRED' })).toBe(msg('MSG-12'));
        expect(msgFromError({ code: 'QUANTITY_EXCEEDED', params: ['Nồi chiên 5L', 1] })).toBe(
            'Số lượng trả của Nồi chiên 5L vượt quá số lượng còn được trả (1).'
        );
        expect(msgFromError({ code: 'FORBIDDEN', message: 'Người tạo yêu cầu không được tự duyệt.' })).toBe(
            'Người tạo yêu cầu không được tự duyệt.'
        );
        expect(msgFromError('Chuỗi lỗi')).toBe('Chuỗi lỗi');
    });

    it('label cần tham số mà service không gửi params thì dùng câu service gửi về', () => {
        const stale = { code: 'STALE_RECORD', message: 'Yêu cầu đã được người khác cập nhật. Vui lòng tải lại.' };
        expect(msgFromError(stale)).toBe(stale.message);
        expect(msgFromError({ ...stale, params: ['RR-2610-00001'] })).toBe(
            'Yêu cầu RR-2610-00001 vừa được người khác cập nhật. Vui lòng tải lại.'
        );
    });
});
