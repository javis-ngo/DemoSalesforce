/**
 * DUC-07 handoff contract. The concrete PayHub/refund implementation belongs
 * to the refund workstream and must be injected/wired when available.
 */
public interface SR_RefundEnqueuer {
    void enqueue(Set<Id> requestIds);
}
