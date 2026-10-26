import { formatLabel, msg, msgFromError } from 'c/srMessages';

// Trong Jest, label import trả về chính tên label (vd "c.SR_MSG_10"), nên so sánh qua msg()
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

    it('đổi lỗi của service thành câu hiển thị', () => {
        expect(msgFromError({ code: 'SELF_APPROVAL' })).toBe(msg('MSG-10'));
        expect(msgFromError({ code: 'CHUA_MAP', message: 'Lỗi riêng' })).toBe('Lỗi riêng');
        expect(msgFromError('Chuỗi lỗi')).toBe('Chuỗi lỗi');
    });
});
