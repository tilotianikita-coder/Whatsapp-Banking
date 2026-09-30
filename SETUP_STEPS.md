# LoanSeva — manual setup steps

Everything that could be source-controlled is in `force-app` and deploys with `sf project deploy start`. The steps below were **unavoidable manual or org-level** actions, either because the platform has no metadata/API path in this org or because they need a human (Meta approval, real phone numbers). Do them in order after a deploy.

## 1. Deploy, assign, seed

```bash
scripts/deploy.sh force-app
sf apex run -f scripts/apex/create_agent_user.apex -o kotak-demo   # once: Einstein Agent User "loanseva.agent.*"
sf apex run -f scripts/apex/post_deploy.apex -o kotak-demo         # perm sets (guest, agent user, you) + drop-off job
```

1. Edit the `DEMO_MOBILES` list at the top of `scripts/apex/seed.apex` with the presenters' WhatsApp numbers (10 digits, no +91). Order: Priya, Rahul, Ananya.
2. Run `sf apex run -f scripts/apex/seed.apex -o kotak-demo`. Re-running resets the demo journeys for those numbers, so run it before every demo.

## 2. Public registration site (Stage 0)

The `LoanSeva` site, its Visualforce page and the guest permission set are all deployed. The site is Active, and the guest profile "LoanSeva Profile" has access to `LoanSevaRegister` and the error pages. **At the time of writing the public URL still returns HTTP 503 "down for maintenance" for every page, including a controller-less test page.** No request reaches Apex, so this is an org/site-level state, not a code issue.

Check in **Setup → Sites**:

1. Sites → **LoanSeva** → confirm **Active** and Active Site Home Page = `LoanSevaRegister`. Toggle **Deactivate → Activate** once if needed.
2. Sites (list page) → confirm the org's Sites domain is registered and **not** shown as "in maintenance". Trial and Developer orgs sometimes need the domain re-saved (Setup → **Domains** / **My Domain** → the `*.my.salesforce-sites.com` entry).
3. LoanSeva → **Public Access Settings** → Visualforce Page Access includes `LoanSevaRegister`; Enabled Apex Class Access includes `LoanSevaRegisterController`.
4. Setup → **Sharing Settings / Guest user access**: nothing else is required. The guest only publishes `LoanSeva_Event__e`, and the subscriber runs as the admin (`LoanSevaEventTriggerConfig`).

Test URL: `https://trailsignup-5e5549adddf5d7.my.salesforce-sites.com/loanseva?src=qr` (the same URL is encoded in `docs/LoanSeva_Registration_QR.png`).

**Demo fallback:** logged-in users can open `https://<my-domain>.my.salesforce.com/apex/LoanSevaRegister?src=link`. It is the same page, controller and flow. If you move to a different site or domain, regenerate the QR:

```bash
python3 -c "import segno; segno.make('<URL>?src=qr', error='m').save('docs/LoanSeva_Registration_QR.png', scale=12, border=2, dark='#003874')"
```

## 3. Publish and activate the agent

`sf agent validate authoring-bundle -n LoanSeva_by_Kotak -o kotak-demo` **passes**, and the bundle is deployed (AiAuthoringBundle `LoanSeva_by_Kotak`). But `sf agent publish authoring-bundle` returns **404 AgentApiNotFound** in this org, even for a minimal one-topic agent. The authoring *publish* API isn't enabled here, although *compile* is.

1. Setup → **Agentforce Agents** → open *LoanSeva by Kotak* in **Agentforce Builder** (new builder / Agent Script view) → **Publish**, then **Activate**.
2. In the agent's settings, confirm the running user is `loanseva.agent.00dgl00000eqlv3@example.com`. It has the `LoanSeva_Agent` permission set from `post_deploy.apex`, so it can run all 12 `LoanSeva*` Apex actions.
3. If the publish API later becomes available: `sf agent publish authoring-bundle -n LoanSeva_by_Kotak -o kotak-demo`.

If you change the agent, edit `scripts/gen_agent.py`, run it, then validate and redeploy the bundle. Don't hand-edit the generated `.agent` file.

## 4. Route WhatsApp_BYOC conversations to the agent (Omni-Channel)

Routing to an agent needs the published agent's ID, so this step can only happen after step 3.

1. Setup → **Flows** → open the package template `wpbyocdemo3__TEMPLATE_WhatsApp_Inbound_Routing` → **Save As** a new flow named `LoanSeva WhatsApp Inbound Routing`. This creates our own copy; the managed flow is untouched.
2. In the copy's **Route Work** element: Route To = **Agentforce Service Agent** → *LoanSeva by Kotak*. Fallback queue = the package's human queue (as in `TEMPLATE_WhatsApp_Route_to_Queue`). Activate.
3. Setup → **Messaging Settings** → `WhatsApp_BYOC` → Routing Type **Omni-Flow**, Flow = `LoanSeva WhatsApp Inbound Routing` → Save.
4. For the *Escalate to Human* hand-off: the agent's escalation connection → the same human queue, and at least one presence-enabled service user online during the demo.
5. Optional: after activation, retrieve the flow into source (`sf project retrieve start -m Flow:LoanSeva_WhatsApp_Inbound_Routing`) and commit it.

## 5. Go live on WhatsApp sends (nudge + re-engagement)

Out of the box, `LoanSeva_Config__mdt.Default.Send_Mode__c = LogOnly`. The nudge text is composed and stored in `Loan_Journey__c.Last_Send_Status__c` but not sent, which is safe while setting up.

1. Setup → Custom Metadata Types → LoanSeva Config → **Default**:
   - `Send_Mode__c` = `ConversationMessage` (real send through the BYOC channel).
   - `RM_Owner_Username__c` = the demo RM's username, so RM Tasks and Events are assigned to them. When blank, they're owned by the running user.
   - Optionally tune `Idle_Minutes_Before_Drop__c` (2), `Nudge_1_Delay_Minutes__c` (2) and `Nudge_2_Delay_Minutes__c` (5). Production values would be 1440 / 4320.
   - Alternatively, edit `force-app/main/default/customMetadata/LoanSeva_Config.Default.md-meta.xml` and redeploy, which keeps the change in version control.
2. **WhatsApp template (Meta).** A business-initiated first message needs an approved template. Create a *Utility* template in Meta Business Manager, for example:
   > Hi {{1}}, great news from Kotak! 🎉 You're pre-qualified for a Personal Loan Top-Up of up to ₹{{2}} on your existing loan. Get a personalised offer in about 90 seconds — right here on WhatsApp.
   > Button (quick reply): **Continue Here!**

   Map it in the BYOC package's router settings (`WhatsApp_BYOC_Setting__mdt` / router admin) as the package documents. Until it's approved, the nudge goes out as the `LoanSeva_Text` free-text definition. That text is delivered only inside the 24-hour customer service window, so have each presenter send "Hi" to the business number once before the demo.
3. Run `sf apex run -f scripts/apex/seed.apex -o kotak-demo`, submit the registration form with a seeded number, and confirm the message arrives. `Loan_Journey__c.Last_Send_Status__c` shows `Sent …` or the exact failure reason. Package-side delivery errors show in `wpbyocdemo3__Debug_Log__c`.

## 6. Drop-off job

`post_deploy.apex` schedules `LoanSevaDropOffJob`, which re-runs every `Job_Interval_Minutes__c` (1). To control it by hand in anonymous Apex:

```apex
LoanSevaDropOffJob.start(); // (re)schedule
LoanSevaDropOffJob.stop();  // unschedule
LoanSevaDropOffJob.run();   // one pass now
```

## 7. Branding asset

`staticresources/LoanSevaLogo.svg` is a **placeholder** wordmark in Kotak Red / Navy. Replace it with the official Kotak logo from the brand kit, keeping the resource name, then redeploy.

## 8. Before any external use

All rates, fees, FOIR, disbursal timelines and FAQ copy are **illustrative demo values**. Align `LoanSeva_Config__mdt` and `LoanSeva_FAQ__mdt` with Kotak's published terms, and replace the fixed demo OTP (`Demo_OTP__c`) with a real OTP provider behind a Named Credential.
