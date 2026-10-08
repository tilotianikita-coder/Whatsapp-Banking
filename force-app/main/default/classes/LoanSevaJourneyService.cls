/**
 * Journey persistence: resolves the Loan_Journey__c for a conversation, advances stages,
 * builds the one-line intent summary and creates RM follow-ups.
 */
public with sharing class LoanSevaJourneyService {
    public static final List<String> STAGES = new List<String>{
        'Nudge', 'Start', 'Verify', 'Personalise', 'Offer', 'Documents', 'Callback', 'Feedback', 'Completed'
    };
    public static final String STATUS_ACTIVE = 'Active';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_DROPPED = 'Dropped';
    public static final String STATUS_EXITED = 'Exited';
    public static final String TYPE_NEW_LOAN = 'New Loan';

    private static final String JOURNEY_FIELDS =
        'Id, Name, OwnerId, Contact__c, Contact__r.FirstName, Contact__r.Name, Lead__c, Existing_Loan__c, Loan_Application__c, ' +
        'Mobile__c, Customer_Name__c, Messaging_Session_Id__c, Messaging_End_User_Id__c, Stage__c, Status__c, Source__c, ' +
        'Language__c, Consent_WhatsApp__c, OTP_Attempts__c, OTP_Verified__c, Loan_Confirmed__c, Employment_Type__c, ' +
        'Company_Name__c, Income_Bucket__c, Purpose__c, Desired_Amount__c, Amount_Options__c, Callback_Options__c, ' +
        'Offer_Amount__c, Offer_Rate__c, Offer_Tenure_Months__c, Offer_EMI__c, Processing_Fee__c, Offer_Accepted__c, ' +
        'Reference_Number__c, Callback_DateTime__c, Feedback_Step__c, Questions_Asked__c, Question_Pending__c, Menu_Pending__c, Drop_Point__c, ' +
        'Fields_Completed__c, Intent_Summary__c, Last_Activity__c, Dropped_At__c, Nudges_Sent__c, Next_Nudge_At__c, ' +
        'RM_Followup_Created__c, Escalated__c, Nudge_Sent_At__c, Verified_At__c, Personalised_At__c, ' +
        'Offer_Presented_At__c, Accepted_At__c, Completed_At__c, Last_Send_Status__c, Journey_Type__c, Apply_Offered__c, ' +
        'Date_Of_Birth__c, PAN__c, Email__c, City__c, PIN_Code__c, Monthly_Income__c, Existing_EMIs__c, Doc_Step__c, ' +
        'Docs_Skipped__c, Submitted_At__c, Prefilled_Fields__c, Last_Voice_Note__c, Last_Voice_File_Id__c';

    /** Test seam: lets tests exercise the actions' graceful-failure path. */
    @TestVisible
    private static Exception forcedError;

    public static String journeyFields() {
        return JOURNEY_FIELDS;
    }

    /** Keeps the last 10 digits of an Indian mobile number; null if fewer than 10 digits. */
    public static String normalizeMobile(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String digits = raw.replaceAll('[^0-9]', '');
        return digits.length() < 10 ? null : digits.right(10);
    }

    public static Boolean isValidIndianMobile(String raw) {
        String digits = raw == null ? '' : raw.replaceAll('[^0-9]', '');
        if (digits.length() == 12 && digits.startsWith('91')) {
            digits = digits.substring(2);
        } else if (digits.length() == 11 && digits.startsWith('0')) {
            digits = digits.substring(1);
        }
        return Pattern.matches('[6-9][0-9]{9}', digits);
    }

    public static List<String> mobileVariants(String mobile10) {
        return new List<String>{ mobile10, '+91' + mobile10, '91' + mobile10, '+91 ' + mobile10, '0' + mobile10 };
    }

    public static Boolean isId(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        try {
            Id parsed = value.trim();
            return parsed != null;
        } catch (Exception e) {
            return false;
        }
    }

    public static Loan_Journey__c byId(Id journeyId) {
        List<Loan_Journey__c> rows = Database.query('SELECT ' + JOURNEY_FIELDS + ' FROM Loan_Journey__c WHERE Id = :journeyId');
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * Finds the journey for this conversation: explicit journey id, then messaging session,
     * then the latest open journey for the mobile number; creates one if none exists.
     */
    public static Loan_Journey__c resolve(String journeyId, String sessionId, String mobile) {
        return resolve(journeyId, sessionId, mobile, false);
    }

    /** openOnly: skip a completed journey, so a new greeting after the journey ended starts a fresh one. */
    public static Loan_Journey__c resolve(String journeyId, String sessionId, String mobile, Boolean openOnly) {
        if (forcedError != null) {
            throw forcedError;
        }
        String language;
        if (isId(journeyId)) {
            Loan_Journey__c j = byId(journeyId);
            if (j != null && openOnly && j.Status__c == STATUS_COMPLETED) {
                language = j.Language__c;
            } else if (j != null) {
                return j;
            }
        }

        String mobile10 = normalizeMobile(mobile);
        String endUserId;
        Id contactId;
        Boolean hasSession = isId(sessionId) && ((Id) sessionId).getSobjectType() == MessagingSession.SObjectType;
        if (hasSession) {
            List<Loan_Journey__c> bySession = Database.query(
                'SELECT ' + JOURNEY_FIELDS + ' FROM Loan_Journey__c WHERE Messaging_Session_Id__c = :sessionId ORDER BY CreatedDate DESC LIMIT 1'
            );
            if (!bySession.isEmpty() && openOnly && bySession[0].Status__c == STATUS_COMPLETED) {
                language = bySession[0].Language__c;
            } else if (!bySession.isEmpty()) {
                return bySession[0];
            }
            for (MessagingSession s : [
                SELECT MessagingEndUserId, MessagingEndUser.MessagingPlatformKey, MessagingEndUser.ContactId
                FROM MessagingSession WHERE Id = :sessionId
            ]) {
                endUserId = s.MessagingEndUserId;
                contactId = s.MessagingEndUser.ContactId;
                String platformMobile = normalizeMobile(s.MessagingEndUser.MessagingPlatformKey);
                if (platformMobile != null) {
                    mobile10 = platformMobile;
                }
            }
        }

        Loan_Journey__c journey;
        if (mobile10 != null) {
            List<Loan_Journey__c> open = Database.query(
                'SELECT ' + JOURNEY_FIELDS + ' FROM Loan_Journey__c WHERE Mobile__c = :mobile10 ' +
                'AND Status__c IN (\'Active\', \'Dropped\') ORDER BY CreatedDate DESC LIMIT 1'
            );
            if (!open.isEmpty()) {
                journey = open[0];
            }
        }
        if (journey == null) {
            journey = new Loan_Journey__c(
                Mobile__c = mobile10,
                Stage__c = 'Start',
                Status__c = STATUS_ACTIVE,
                Source__c = hasSession ? 'WhatsApp' : 'Agent Preview',
                Language__c = language == null ? LoanSevaI18n.EN : language,
                Contact__c = contactId,
                Last_Activity__c = Datetime.now()
            );
            if (contactId == null && mobile10 != null) {
                Contact c = findContact(mobile10);
                if (c != null) {
                    journey.Contact__c = c.Id;
                }
            }
        }
        if (hasSession) {
            journey.Messaging_Session_Id__c = sessionId;
            journey.Messaging_End_User_Id__c = endUserId;
        }
        upsert journey;
        return byId(journey.Id);
    }

    /** A new Personal Loan application (no pre-approved Top-Up offer), rather than a Top-Up journey. */
    public static Boolean isNewLoan(Loan_Journey__c j) {
        return j != null && j.Journey_Type__c == TYPE_NEW_LOAN;
    }

    public static Contact findContact(String mobile10) {
        List<String> variants = mobileVariants(mobile10);
        List<Contact> rows = [
            SELECT Id, FirstName, LastName, Name, MobilePhone
            FROM Contact
            WHERE MobilePhone IN :variants OR Phone IN :variants
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public static Existing_Loan__c activeLoan(Id contactId) {
        if (contactId == null) {
            return null;
        }
        List<Existing_Loan__c> loans = [
            SELECT Id, Name, Contact__c, Loan_Account_Number__c, Masked_Account__c, Product__c, Outstanding_Principal__c,
                Current_EMI__c, Interest_Rate__c, Tenure_Remaining_Months__c, EMIs_Paid_On_Time__c, EMIs_Due__c,
                Pre_Approved_Limit__c, Status__c
            FROM Existing_Loan__c
            WHERE Contact__c = :contactId AND Status__c = 'Active'
            ORDER BY Pre_Approved_Limit__c DESC NULLS LAST
            LIMIT 1
        ];
        return loans.isEmpty() ? null : loans[0];
    }

    /** Moves the journey forward (never backwards) and records activity. Caller performs DML. */
    public static void advance(Loan_Journey__c j, String stage) {
        if (STAGES.indexOf(stage) > STAGES.indexOf(j.Stage__c)) {
            j.Stage__c = stage;
        }
        touch(j);
    }

    /** Records activity; a returning dropped customer becomes active again. */
    public static void touch(Loan_Journey__c j) {
        j.Last_Activity__c = Datetime.now();
        if (j.Status__c == STATUS_DROPPED) {
            j.Status__c = STATUS_ACTIVE;
        }
        j.Fields_Completed__c = fieldsCompleted(j);
        j.Intent_Summary__c = intentSummary(j).abbreviate(255);
    }

    public static Integer fieldsCompleted(Loan_Journey__c j) {
        Integer n = 0;
        for (Object v : new List<Object>{ j.Employment_Type__c, j.Company_Name__c, j.Income_Bucket__c, j.Purpose__c, j.Desired_Amount__c }) {
            if (v != null && String.isNotBlank(String.valueOf(v))) {
                n++;
            }
        }
        return n;
    }

    public static String firstName(Loan_Journey__c j) {
        if (j.Contact__r != null && String.isNotBlank(j.Contact__r.FirstName)) {
            return j.Contact__r.FirstName;
        }
        if (String.isNotBlank(j.Customer_Name__c)) {
            return j.Customer_Name__c.trim().split(' ')[0].capitalize();
        }
        return '';
    }

    /** e.g. "Priya — ₹5L top-up for Home renovation, Salaried @ Infosys, income 1L-2L, accepted offer, callback Thu 11:00 AM". */
    public static String intentSummary(Loan_Journey__c j) {
        String who = firstName(j);
        if (String.isBlank(who)) {
            who = j.Mobile__c == null ? 'Customer' : 'Customer ' + j.Mobile__c;
        }
        List<String> parts = new List<String>();
        Decimal amount = j.Offer_Amount__c != null ? j.Offer_Amount__c : j.Desired_Amount__c;
        String what = (amount != null ? LoanSevaI18n.inrShort(amount) + ' ' : '') + (isNewLoan(j) ? 'new personal loan' : 'top-up');
        if (String.isNotBlank(j.Purpose__c)) {
            what += ' for ' + j.Purpose__c.toLowerCase();
        }
        parts.add(what);
        if (String.isNotBlank(j.Employment_Type__c)) {
            parts.add(j.Employment_Type__c + (String.isNotBlank(j.Company_Name__c) ? ' @ ' + j.Company_Name__c : ''));
        }
        if (String.isNotBlank(j.Income_Bucket__c)) {
            parts.add('income ' + j.Income_Bucket__c);
        }
        if (j.Offer_Accepted__c) {
            parts.add('accepted offer');
        }
        if (j.Submitted_At__c != null) {
            parts.add('application submitted');
        }
        if (j.Callback_DateTime__c != null) {
            parts.add('callback ' + j.Callback_DateTime__c.format('EEE h:mm a', LoanSevaI18n.TIMEZONE));
        }
        if (j.Status__c == STATUS_DROPPED || j.Status__c == STATUS_EXITED) {
            parts.add('dropped at ' + (String.isNotBlank(j.Drop_Point__c) ? j.Drop_Point__c : j.Stage__c));
        }
        return who + ' — ' + String.join(parts, ', ');
    }

    private static Id configuredRmId;
    private static Boolean rmLookedUp = false;

    public static final String RM_QUEUE = 'LoanSeva_RM_Callbacks';

    /** The queue RMs work booked callbacks from; null if it isn't deployed. */
    public static Id rmQueueId() {
        for (Group g : [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :RM_QUEUE LIMIT 1]) {
            return g.Id;
        }
        return null;
    }

    public static Id rmOwnerId(Loan_Journey__c j) {
        if (!rmLookedUp) {
            rmLookedUp = true;
            String username = LoanSevaConfig.get().RM_Owner_Username__c;
            if (String.isNotBlank(username)) {
                for (User u : [SELECT Id FROM User WHERE Username = :username AND IsActive = TRUE LIMIT 1]) {
                    configuredRmId = u.Id;
                }
            }
        }
        if (configuredRmId != null) {
            return configuredRmId;
        }
        if (j.OwnerId != null && ((Id) j.OwnerId).getSobjectType() == User.SObjectType) {
            return j.OwnerId;
        }
        return UserInfo.getUserId();
    }

    public static Task buildRmTask(Loan_Journey__c j, String subject, String description, Date dueDate) {
        // a Lead WhoId cannot be combined with a WhatId, so prospects link to the Lead only
        Boolean leadOnly = j.Contact__c == null && j.Lead__c != null;
        return new Task(
            OwnerId = rmOwnerId(j),
            Subject = ('LoanSeva: ' + subject).abbreviate(255),
            Description = leadOnly ? 'Journey ' + j.Name + ' (' + j.Id + ')\n' + description : description,
            WhoId = j.Contact__c != null ? j.Contact__c : j.Lead__c,
            WhatId = leadOnly ? null : j.Id,
            ActivityDate = dueDate == null ? LoanSevaI18n.todayIst() : dueDate,
            Priority = 'High',
            Status = 'Not Started',
            Type = 'Call'
        );
    }

    public static String rmDescription(Loan_Journey__c j) {
        List<String> lines = new List<String>{
            'Intent: ' + intentSummary(j),
            'Journey: ' + j.Name + ' | Stage reached: ' + j.Stage__c + ' | Fields completed: ' + fieldsCompleted(j) + '/5',
            'Mobile: ' + j.Mobile__c + ' | Language: ' + j.Language__c + ' | Source: ' + j.Source__c
        };
        if (j.Offer_Amount__c != null) {
            lines.add('Offer: ' + LoanSevaI18n.inr(j.Offer_Amount__c) + ' @ ' + j.Offer_Rate__c + '% for ' + j.Offer_Tenure_Months__c + 'm, EMI ' + LoanSevaI18n.inr(j.Offer_EMI__c));
        }
        if (String.isNotBlank(j.Reference_Number__c)) {
            lines.add('Reference: ' + j.Reference_Number__c);
        }
        if (String.isNotBlank(j.Questions_Asked__c)) {
            lines.add('Questions asked:\n' + j.Questions_Asked__c);
        }
        return String.join(lines, '\n');
    }

    public static void createRmTask(Loan_Journey__c j, String subject) {
        insert buildRmTask(j, subject, rmDescription(j), null);
        j.RM_Followup_Created__c = true;
    }
}
