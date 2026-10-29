// Chạy bằng user timezone Asia/Bangkok (GMT+7), sau khi deploy metadata và seed nhóm.
SR_NightlyJob.scheduleDaily();
SR_RefundRetryJob.scheduleEvery15Minutes();
