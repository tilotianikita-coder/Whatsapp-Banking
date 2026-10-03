@IsTest
private class LoanSevaVoiceTextTest {
    @IsTest
    static void panSpokenLetterByLetterOrInChunks() {
        System.assertEquals('ABCPS1234K', LoanSevaVoiceText.forState('A B C P S one two three four K', 'pan'));
        System.assertEquals('ABCPS1234K', LoanSevaVoiceText.forState('My PAN number is ABCPS 1234 K.', 'pan'));
        System.assertEquals('ABCPS1234K', LoanSevaVoiceText.forState('ay bee see pee ess twelve thirty four kay', 'pan'));
        System.assertEquals('ABCPS1234K', LoanSevaVoiceText.forState('A for Apple B for Ball C P S 1 2 3 4 K', 'pan'));
        System.assertEquals('ABOPS1234K', LoanSevaVoiceText.forState('A B zero P S one two three four K', 'pan'), 'a 0 among the letters is an O');
        System.assertEquals('ABCPS1234K', LoanSevaVoiceText.forState('मेरा पैन ए बी सी पी एस १२३४ के है', 'pan'));
        System.assertEquals('I do not have it', LoanSevaVoiceText.forState('I do not have it.', 'pan'), 'no PAN: passed through for the step to re-ask');
    }

    @IsTest
    static void mobileOtpAndPin() {
        System.assertEquals('Asha Patil 9123456780', LoanSevaVoiceText.forState('Asha Patil, nine one two three four five six seven eight zero.', 'identity'));
        System.assertEquals('Asha 9123456780', LoanSevaVoiceText.forState('Asha and 91234 56780', 'identity'));
        System.assertEquals('9988776655', LoanSevaVoiceText.forState('double nine double eight double seven double six double five', 'identity'));
        System.assertEquals('123456', LoanSevaVoiceText.forState('१२३ ४५६', 'otp'));
        System.assertEquals('411001', LoanSevaVoiceText.forState('four one one double zero one', 'pincode'));
        System.assertEquals('Pune 411001', LoanSevaVoiceText.forState('Pune 411 001', 'pincode'));
    }

    @IsTest
    static void emailDobAndAmounts() {
        System.assertEquals('priya.sharma@gmail.com', LoanSevaVoiceText.forState('My email is priya dot sharma at the rate gmail dot com', 'email'));
        System.assertEquals('a_b@x.in', LoanSevaVoiceText.forState('a underscore b at x dot in', 'email'));
        System.assertEquals('It is priya@gmail.com', LoanSevaVoiceText.forState('It is priya@gmail.com.', 'email'));
        System.assertEquals('15 August 1990', LoanSevaVoiceText.forState('August fifteenth, nineteen ninety', 'dob'));
        System.assertEquals('15 August 1990', LoanSevaVoiceText.forState('fifteenth of August 19 90', 'dob'));
        System.assertEquals('120000', LoanSevaVoiceText.forState('one lakh twenty thousand', 'income'));
        System.assertEquals('85 thousand', LoanSevaVoiceText.forState('eighty five thousand', 'income'));
        System.assertEquals('3 lakh', LoanSevaVoiceText.forState('three lakh', 'amount'));
        System.assertEquals('200', LoanSevaVoiceText.forState('two hundred', 'obligations'));
    }

    @IsTest
    static void choicesAndFreeText() {
        System.assertEquals('4', LoanSevaVoiceText.forState('Option four.', 'menu'));
        System.assertEquals('2', LoanSevaVoiceText.forState('number two', 'employment'));
        System.assertEquals('1', LoanSevaVoiceText.forState('one', 'consent'));
        System.assertEquals('Salaried', LoanSevaVoiceText.forState('Sally Read.', 'employment'));
        System.assertEquals('Salaried', LoanSevaVoiceText.forState('सैलरीड', 'employment'));
        System.assertEquals('Self employed', LoanSevaVoiceText.forState('Self employed', 'employment'));
        System.assertEquals('Tata Consultancy Services', LoanSevaVoiceText.forState('Tata Consultancy Services.', 'company'));
        System.assertEquals('', LoanSevaVoiceText.forState(null, 'purpose'));
        System.assertEquals('Yes please', LoanSevaVoiceText.forState('Yes please!', 'offer_decision'));
    }
}
