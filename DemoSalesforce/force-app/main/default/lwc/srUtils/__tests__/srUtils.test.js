import { LEVEL_LABELS, REASON_OPTIONS, labelOf, vnd, formatDate } from 'c/srUtils';

describe('c/srUtils', () => {
    it('có nhãn cho cả 3 cấp duyệt dùng ở D.1', () => {
        expect(Object.keys(LEVEL_LABELS)).toEqual(['AUTO', 'CHT', 'QLV']);
    });

    it('định dạng tiền và ngày kiểu Việt Nam', () => {
        expect(vnd(1992000)).toBe('1.992.000');
        expect(formatDate('2026-10-08')).toBe('08/10/2026');
    });

    it('lấy nhãn tiếng Việt theo giá trị, không có thì trả lại giá trị', () => {
        expect(labelOf(REASON_OPTIONS, 'DEFECT')).toBe('Lỗi kỹ thuật');
        expect(labelOf(REASON_OPTIONS, 'XYZ')).toBe('XYZ');
    });
});
