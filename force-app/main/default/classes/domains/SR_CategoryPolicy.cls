public class SR_CategoryPolicy {
    public String family;
    public Boolean isReturnable;
    public Integer returnWindowDays;
    public Boolean active;

    public SR_CategoryPolicy(String family, Boolean isReturnable, Integer returnWindowDays, Boolean active) {
        this.family = family;
        this.isReturnable = isReturnable;
        this.returnWindowDays = returnWindowDays;
        this.active = active;
    }
}
