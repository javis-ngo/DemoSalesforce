@IsTest(SeeAllData=false)
private class SR_RefundCalculatorTest {
    private static void applyConfig() {
        SR_TestDataFactory.resetConfig();
        SR_TestDataFactory.seedSmartReturnTestConfig();
    }

    @IsTest
    static void rateFor_readsConfiguredRatesAndNormalizesKeys() {
        applyConfig();

        Assert.areEqual(
            100,
            SR_RefundCalculator.rateFor('DEFECT', 'SEALED'),
            'DEFECT/SEALED must use the configured 100% rate.'
        );
        Assert.areEqual(
            80,
            SR_RefundCalculator.rateFor(
                '  not_satisfied  ',
                '  opened  '
            ),
            'Reason and condition must be trimmed and normalized.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.rateFor(
                'CUSTOMER_DAMAGE',
                'USED'
            ),
            'A configured zero rate must be returned as zero.'
        );
    }

    @IsTest
    static void rateFor_missingOrInvalidConfiguration_returnsNull() {
        applyConfig();

        Assert.isNull(
            SR_RefundCalculator.rateFor(null, 'SEALED'),
            'Null reason must not produce a refund rate.'
        );
        Assert.isNull(
            SR_RefundCalculator.rateFor('DEFECT', null),
            'Null condition must not produce a refund rate.'
        );
        Assert.isNull(
            SR_RefundCalculator.rateFor('', 'SEALED'),
            'Blank reason must not produce a refund rate.'
        );
        Assert.isNull(
            SR_RefundCalculator.rateFor('DEFECT', 'UNKNOWN'),
            'An unconfigured reason/condition pair must return null.'
        );
    }

    @IsTest
    static void calculateLine_validInputs_exposesCalculationDetails() {
        SR_RefundCalculator.Calculation percentResult =
            SR_RefundCalculator.calculateLine(2490000, 1, 80);
        SR_RefundCalculator.Calculation ratioResult =
            SR_RefundCalculator.calculateLine(1550, 1.5, 0.8);

        Assert.isNotNull(
            percentResult,
            'A valid percentage-based calculation must return details.'
        );
        Assert.areEqual(
            0.8,
            percentResult.normalizedRate,
            'An 80 percentage rate must be normalized to 0.8.'
        );
        Assert.areEqual(
            1992000,
            percentResult.rawAmount,
            'The raw amount must be preserved before display rounding.'
        );
        Assert.areEqual(
            1992000,
            percentResult.displayAmount,
            'An already aligned raw amount must remain unchanged.'
        );

        Assert.isNotNull(
            ratioResult,
            'A valid ratio-based calculation must return details.'
        );
        Assert.areEqual(
            0.8,
            ratioResult.normalizedRate,
            'A ratio rate must remain unchanged.'
        );
        Assert.areEqual(
            1860,
            ratioResult.rawAmount,
            'Fractional quantities must be included in the raw amount.'
        );
        Assert.areEqual(
            1000,
            ratioResult.displayAmount,
            'The display amount must round the raw amount down once.'
        );
    }

    @IsTest
    static void calculateLine_nullInputs_returnNull() {
        Assert.isNull(
            SR_RefundCalculator.calculateLine(null, 1, 100),
            'Null unit price must invalidate the calculation.'
        );
        Assert.isNull(
            SR_RefundCalculator.calculateLine(1000, null, 100),
            'Null quantity must invalidate the calculation.'
        );
        Assert.isNull(
            SR_RefundCalculator.calculateLine(1000, 1, null),
            'Null refund rate must invalidate the calculation.'
        );
    }

    @IsTest
    static void rawAmount_returnsUnroundedValueOrNull() {
        Assert.areEqual(
            1860,
            SR_RefundCalculator.rawAmount(1550, 1.5, 80),
            'rawAmount must return the value before thousand-unit rounding.'
        );
        Assert.areEqual(
            500,
            SR_RefundCalculator.rawAmount(1000, 1, 0.5),
            'rawAmount must support ratio-form refund rates.'
        );
        Assert.isNull(
            SR_RefundCalculator.rawAmount(null, 1, 100),
            'rawAmount must return null when calculation inputs are invalid.'
        );
        Assert.isNull(
            SR_RefundCalculator.rawAmount(1000, 1, 101),
            'rawAmount must return null for rates above 100%.'
        );
    }

    @IsTest
    static void displayAmount_handlesNullAndRoundsDown() {
        Assert.areEqual(
            0,
            SR_RefundCalculator.displayAmount(null),
            'A null raw amount must display as zero.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.displayAmount(999.99),
            'A positive amount below 1,000 must round down to zero.'
        );
        Assert.areEqual(
            1000,
            SR_RefundCalculator.displayAmount(1999.99),
            'Display values must round down to the nearest thousand.'
        );
        Assert.areEqual(
            2000,
            SR_RefundCalculator.displayAmount(2000),
            'An exact thousand-unit value must remain unchanged.'
        );
    }

    @IsTest
    static void lineAmount_nullInputsReturnZero() {
        Assert.areEqual(
            0,
            SR_RefundCalculator.lineAmount(null, 1, 100),
            'Null unit price must return zero.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.lineAmount(1000, null, 100),
            'Null quantity must return zero.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.lineAmount(1000, 1, null),
            'Null refund rate must return zero.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.lineAmount(null, null, null),
            'All-null inputs must return zero.'
        );
    }

    @IsTest
    static void lineAmount_invalidInputsReturnZero() {
        Assert.areEqual(
            0,
            SR_RefundCalculator.lineAmount(-1, 1, 100),
            'A negative unit price must return zero.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.lineAmount(1000, 0, 100),
            'A zero quantity must return zero.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.lineAmount(1000, 1, -1),
            'A negative rate must return zero.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.lineAmount(1000, 1, 101),
            'A rate above 100% must return zero.'
        );
    }

    @IsTest
    static void lineAmount_supportsPercentAndRatioRateFormats() {
        Assert.areEqual(
            2490000,
            SR_RefundCalculator.lineAmount(2490000, 1, 100),
            '100 must be interpreted as 100%.'
        );
        Assert.areEqual(
            2490000,
            SR_RefundCalculator.lineAmount(2490000, 1, 1),
            '1 must be interpreted as a 100% ratio.'
        );
        Assert.areEqual(
            1992000,
            SR_RefundCalculator.lineAmount(2490000, 1, 80),
            '80 must be interpreted as 80%.'
        );
        Assert.areEqual(
            1992000,
            SR_RefundCalculator.lineAmount(2490000, 1, 0.8),
            '0.8 must be interpreted as an 80% ratio.'
        );
        Assert.areEqual(
            1245000,
            SR_RefundCalculator.lineAmount(2490000, 1, 50),
            '50 must be interpreted as 50%.'
        );
        Assert.areEqual(
            1245000,
            SR_RefundCalculator.lineAmount(2490000, 1, 0.5),
            '0.5 must be interpreted as a 50% ratio.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.lineAmount(2490000, 1, 0),
            'A zero rate must produce zero refund.'
        );
    }

    @IsTest
    static void lineAmount_roundsDownToNearestThousand() {
        Assert.areEqual(
            0,
            SR_RefundCalculator.lineAmount(999, 1, 100),
            'Amounts below 1,000 must round down to zero.'
        );
        Assert.areEqual(
            1000,
            SR_RefundCalculator.lineAmount(1000, 1, 100),
            'Exactly 1,000 must remain 1,000.'
        );
        Assert.areEqual(
            1000,
            SR_RefundCalculator.lineAmount(1999, 1, 100),
            '1,999 must round down to 1,000.'
        );
        Assert.areEqual(
            2000,
            SR_RefundCalculator.lineAmount(2999, 1, 100),
            '2,999 must round down to 2,000.'
        );
        Assert.areEqual(
            1000,
            SR_RefundCalculator.lineAmount(1550, 1, 100),
            '1,550 at 100% must round down to 1,000.'
        );
        Assert.areEqual(
            1000,
            SR_RefundCalculator.lineAmount(2490, 1, 80),
            '1,992 after applying rate must round down to 1,000.'
        );
    }

    @IsTest
    static void lineAmount_handlesFractionalQuantitiesBeforeRounding() {
        Assert.areEqual(
            2000,
            SR_RefundCalculator.lineAmount(1000, 2.5, 80),
            'Fractional quantity must be multiplied before rounding.'
        );
        Assert.areEqual(
            3000,
            SR_RefundCalculator.lineAmount(1550, 2, 100),
            'The combined raw line amount must be rounded once.'
        );
        Assert.areEqual(
            1000,
            SR_RefundCalculator.lineAmount(1550, 1.5, 80),
            'A fractional raw amount must round down to the nearest thousand.'
        );
    }

    @IsTest
    static void total_coversNullEmptyNullElementsAndDecimalValues() {
        Assert.areEqual(
            0,
            SR_RefundCalculator.total(null),
            'Null list must total zero.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.total(new List<Decimal>()),
            'Empty list must total zero.'
        );
        Assert.areEqual(
            0,
            SR_RefundCalculator.total(
                new List<Decimal>{ null, null }
            ),
            'Null elements must be treated as zero.'
        );
        Assert.areEqual(
            3482000,
            SR_RefundCalculator.total(
                new List<Decimal>{ 2490000, 992000, null }
            ),
            'Total must sum non-null line amounts.'
        );
        Assert.areEqual(
            3500.5,
            SR_RefundCalculator.total(
                new List<Decimal>{ 1000.25, 2500.25 }
            ),
            'Total must preserve decimal precision provided by callers.'
        );
    }

    @IsTest
    static void bulk_twoHundredCalculatedLines_areSummedCorrectly() {
        List<Decimal> amounts = new List<Decimal>();
        for (Integer index = 0; index < 200; index++) {
            amounts.add(
                SR_RefundCalculator.lineAmount(1550, 1, 100)
            );
        }

        Test.startTest();
        Decimal result = SR_RefundCalculator.total(amounts);
        Test.stopTest();

        Assert.areEqual(
            200000,
            result,
            'Two hundred rounded 1,000 amounts must total 200,000.'
        );
    }
}