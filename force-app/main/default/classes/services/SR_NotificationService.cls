public without sharing class SR_NotificationService {

    private static final String NOTIFICATION_TYPE = 'SR_Notification';
    private static final Integer REQUEST_NAMES_IN_BODY = 3;

    public static void notifyRegionalManagers(List<Return_Request__c> escalated) {
        if (escalated == null || escalated.isEmpty()) {
            return;
        }

        Map<Id, List<Return_Request__c>> requestsByManager =
            new Map<Id, List<Return_Request__c>>();
        for (Return_Request__c requestRecord : escalated) {
            if (requestRecord.Assigned_Approver__c == null) {
                continue;
            }
            if (!requestsByManager.containsKey(requestRecord.Assigned_Approver__c)) {
                requestsByManager.put(
                    requestRecord.Assigned_Approver__c,
                    new List<Return_Request__c>()
                );
            }
            requestsByManager.get(requestRecord.Assigned_Approver__c).add(requestRecord);
        }
        if (requestsByManager.isEmpty()) {
            return;
        }

        SR_Logger logger = SR_Logger.getInstance();
        try {
            List<CustomNotificationType> types = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = :NOTIFICATION_TYPE
                LIMIT 1
            ];
            if (types.isEmpty()) {
                logger.error(
                    'SR_NotificationService.notifyRegionalManagers',
                    'SR_NotificationService',
                    null,
                    'Thiếu Custom Notification ' + NOTIFICATION_TYPE,
                    null,
                    null
                );
                return;
            }

            for (Id managerId : requestsByManager.keySet()) {
                List<Return_Request__c> managerRequests = requestsByManager.get(managerId);
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setNotificationTypeId(types[0].Id);
                notification.setTargetId(managerRequests[0].Id);
                notification.setTitle('Yêu cầu trả hàng cần duyệt');
                notification.setBody(notificationBody(managerRequests));
                try {
                    notification.send(new Set<String>{ String.valueOf(managerId) });
                } catch (Exception e) {
                    logger.error(
                        'SR_NotificationService.notifyRegionalManagers',
                        'SR_NotificationService',
                        null,
                        e.getTypeName() + ': ' + e.getMessage(),
                        managerRequests[0].Id,
                        e.getStackTraceString()
                    );
                }
            }
        } finally {
            logger.push();
        }
    }

    private static String notificationBody(List<Return_Request__c> requests) {
        List<String> names = new List<String>();
        Integer included = requests.size() < REQUEST_NAMES_IN_BODY
            ? requests.size()
            : REQUEST_NAMES_IN_BODY;
        for (Integer i = 0; i < included; i++) {
            names.add(requests[i].Name);
        }
        String body = requests.size() + ' yêu cầu đã quá hạn duyệt: ' + String.join(names, ', ');
        if (requests.size() > included) {
            body += ' và ' + (requests.size() - included) + ' yêu cầu khác';
        }
        return body;
    }
}
