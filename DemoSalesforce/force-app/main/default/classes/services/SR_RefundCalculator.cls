public with sharing class SR_RefundCalculator {
    private static final Decimal ROUND_UNIT = 1000;

    public class Calculation {
        public Decimal normalizedRate { get; private set; }
        public Decimal rawAmount { get; private set; }
        public Decimal displayAmount { get; private set; }

        private Calculation(
            Decimal normalizedRate,
            Decimal rawAmount,
            Decimal displayAmount
        ) {
            this.normalizedRate = normalizedRate;
            this.rawAmount = rawAmount;
            this.displayAmount = displayAmount;
        }
    }

    public static Decimal rateFor(String reason, String condition) {
        return SR_Config.getRefundRate(reason, condition);
    }

    public static Calculation calculateLine(
        Decimal unitPrice,
        Decimal quantity,
        Decimal refundRate
    ) {
        if (unitPrice == null || quantity == null || refundRate == null) {
            return null;
        }
        if (unitPrice < 0 || quantity <= 0 || refundRate < 0) {
            return null;
        }

        Decimal normalizedRate = normalizeRate(refundRate);
        if (normalizedRate > 1) {
            return null;
        }

        Decimal rawAmount = unitPrice * quantity * normalizedRate;
        return new Calculation(
            normalizedRate,
            rawAmount,
            displayAmount(rawAmount)
        );
    }

    public static Decimal rawAmount(
        Decimal unitPrice,
        Decimal quantity,
        Decimal refundRate
    ) {
        Calculation result = calculateLine(unitPrice, quantity, refundRate);
        return result == null ? null : result.rawAmount;
    }

    public static Decimal displayAmount(Decimal rawAmount) {
        if (rawAmount == null) {
            return 0;
        }
        return (rawAmount / ROUND_UNIT)
            .setScale(0, RoundingMode.FLOOR) * ROUND_UNIT;
    }

    // Backward-compatible method for LWC/inspection callers that expect
    // the rounded amount shown to the user.
    public static Decimal lineAmount(
        Decimal unitPrice,
        Decimal quantity,
        Decimal refundRate
    ) {
        Calculation result = calculateLine(unitPrice, quantity, refundRate);
        return result == null ? 0 : result.displayAmount;
    }

    public static Decimal total(List<Decimal> lineAmounts) {
        Decimal sum = 0;
        if (lineAmounts == null) {
            return sum;
        }
        for (Decimal amount : lineAmounts) {
            sum += amount == null ? 0 : amount;
        }
        return sum;
    }

    private static Decimal normalizeRate(Decimal refundRate) {
        return refundRate > 1 ? refundRate / 100 : refundRate;
    }
}