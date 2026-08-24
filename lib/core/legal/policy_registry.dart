/// THE CANONICAL ALPHASERENA POLICY REGISTRY.
///
/// One framework, four documents, one version source — for all three apps.
///
/// **Why the content lives here as well as behind a URL.** The documents are
/// rendered in-app so a member can always read what they agreed to, even
/// offline; the same content is published at [publicBaseUrl] (register item
/// L-8, resolved 2026-08-10: Firebase Hosting on the platform's own project).
/// The hosted pages are generated from the canonical markdown — the two
/// surfaces must never disagree.
///
/// **Why this file is TWINNED across the three repositories** rather than
/// imported. Trainersarena, Alphasarena and Alphasarena Admin are separate Flutter
/// repositories with no shared package, and this ecosystem's established
/// pattern for a cross-repo contract is a twinned file plus a drift guard (see
/// `lifestyle_math.dart` and `prescription.dart`). `test/policy_registry_test`
/// pins the version, the identifiers and the section headings, so a copy that
/// drifts fails its own suite rather than silently telling one app's users a
/// different agreement from another's.
///
/// **This file is the single source of the prose.** The markdown in
/// `trainershq-backend/docs/legal/*.md` and the hosted pages under
/// `trainershq-backend/hosting/legal/` are EXPORTED from it by
/// `tool/export_policies.dart` (run from the alphaserena repo) — never edited
/// by hand. Edit here, re-export, re-sync the twins.
///
/// ⚠️ Every statement here was checked against the implementation. Do not add a
/// claim — about security, refunds, renewal, certification, deletion or health
/// — that the code does not support.
library;

/// A stable identifier for one policy document. These four strings are the
/// contract: routes, links and (later) consent records all key on them, and
/// they must not change once a consent record exists.
enum PolicyId {
  privacy('privacy', 'Privacy Policy'),
  terms('terms', 'Terms of Service'),
  refund('refund', 'Refund & Cancellation Policy'),
  healthDisclaimer(
    'health-disclaimer',
    'Health, Fitness, Nutrition & Wellness Disclaimer',
  );

  const PolicyId(this.slug, this.title);

  /// The stable identifier used in routes, links and acceptance records.
  final String slug;

  /// The document's display title.
  final String title;

  static PolicyId? fromSlug(String slug) {
    for (final id in PolicyId.values) {
      if (id.slug == slug) return id;
    }
    return null;
  }
}

/// One titled block of a document.
class PolicySection {
  const PolicySection(this.heading, this.body);
  final String heading;
  final String body;
}

/// A rendered policy document.
class PolicyDocument {
  const PolicyDocument({
    required this.id,
    required this.summary,
    required this.sections,
  });

  final PolicyId id;

  /// One line under the title explaining what the document is for.
  final String summary;

  final List<PolicySection> sections;

  String get title => id.title;
  String get slug => id.slug;
}

/// Version, identity and content for every Alphasarena policy document.
class PolicyRegistry {
  PolicyRegistry._();

  /* ─────────────────────────── version source ──────────────────────────── */

  /// THE single version string. Every app renders this; no screen hardcodes it.
  ///
  /// A displayed version that drifts from the document is worse than a missing
  /// one — it would misstate WHICH agreement a user accepted. This constant is
  /// also the identifier a future acceptance record would store.
  static const String version = '1.0';

  /// Publication status. Set to 'Published' on 2026-08-10, when the operator
  /// resolved the outstanding register items (entity, hosting, age, refunds)
  /// and approved publication of version 1.0.
  static const String status = 'Published';

  /// The date the documents take effect: the date version 1.0 was published.
  static const String effectiveDate = '10 August 2026';

  static bool get hasEffectiveDate => effectiveDate.trim().isNotEmpty;

  /* ──────────────────────────────  identity  ───────────────────────────── */

  /// The publishing identity. Register item L-1 was resolved 2026-08-10 by
  /// operator decision: the platform publishes under the name Alphasarena.
  /// The documents describe it as the name the service is operated under and
  /// claim no registration — do not add a company suffix or number here.
  static const String company = 'Alphasarena';

  /// The coach / organization application's published name. The member app is
  /// published under [company] itself, so it needs no separate constant; this
  /// one exists because the trainer app's name is NOT the platform name, and
  /// hand-typing it is how the coach app came to ship under three different
  /// names at once.
  ///
  /// The retired spellings are deliberately NOT written out here: this file is
  /// scanned for them by `policy_registry_parity_test.dart`, comments included,
  /// precisely so that a stale mention cannot teach the next reader that an old
  /// name was intentional. See that test for the list.
  static const String trainerAppName = 'Trainersarena';

  /// The operational contact, including for privacy questions and refund
  /// requests (register item L-3, operator-decided). No separate statutory
  /// grievance designation is claimed.
  static const String contact = 'frameingos@gmail.com';

  /// Public base URL for the published documents (register item L-8, resolved
  /// 2026-08-10): Firebase Hosting on the platform's own project. The pages
  /// are generated from `trainershq-backend/docs/legal/*.md` and deployed with
  /// `firebase deploy --only hosting`.
  static const String publicBaseUrl = 'https://trainershq-f5ded.web.app/legal';

  static bool get hasPublicUrls => publicBaseUrl.trim().isNotEmpty;

  /// The public URL of a document, or null while hosting is unresolved.
  static String? urlOf(PolicyId id) =>
      hasPublicUrls ? '$publicBaseUrl/${id.slug}' : null;

  /* ──────────────────────────────  documents  ──────────────────────────── */

  static PolicyDocument of(PolicyId id) => switch (id) {
    PolicyId.privacy => _privacy,
    PolicyId.terms => _terms,
    PolicyId.refund => _refund,
    PolicyId.healthDisclaimer => _health,
  };

  static List<PolicyDocument> get all =>
      PolicyId.values.map(of).toList(growable: false);

  /// A short provenance line shown above every document.
  static const String draftNotice =
      'This document was prepared from how the platform actually works, and '
      'every statement in it was checked against the implementation. The '
      'version and effective date identify the agreement that applies.';

  /* ───────────────────────────── PRIVACY POLICY ────────────────────────── */

  static const PolicyDocument _privacy = PolicyDocument(
    id: PolicyId.privacy,
    summary:
        'What Alphasarena collects, why, who can see it, and what happens when '
        'you delete your account.',
    sections: [
      PolicySection(
        'Who we are',
        'Alphasarena provides coaching software used by fitness coaches, '
            'coaching organizations and their members. It has three '
            'applications sharing one backend: Trainersarena (for organizations '
            'and trainers), the Alphasarena member app, and Alphasarena Admin '
            '(for the platform operator).\n\n'
            'Alphasarena is the name under which the service is operated and '
            'published. It is operated from India.\n\n'
            'Contact: $contact',
      ),
      PolicySection(
        'Your role changes what applies',
        'If you are a MEMBER, you receive coaching from an organization, and '
            'your coach can see the information you record.\n\n'
            'If you are a COACH, TRAINER or ORGANIZATION OWNER, you run a '
            'coaching organization and can see data for the members assigned '
            'to you.\n\n'
            'The organization you joined decides what coaching information is '
            'collected from you, sets the questions you are asked, writes your '
            'plans, and keeps its own business record of you. Alphasarena '
            'operates the software those activities run on, and is '
            'responsible for the platform itself — not for the coaching '
            'decisions your organization makes.',
      ),
      PolicySection(
        'Account and identity information',
        'Name, email address and phone number. Gender, date of birth and '
            'address where you provide them. Profile photograph. For coaches: '
            'specialization, experience, certifications and biography you '
            'enter yourself, plus your organization details.',
      ),
      PolicySection(
        'Signing in',
        'Sign-in is handled by Firebase Authentication, provided by Google.\n\n'
            // ⚠️ THIS SENTENCE MUST NAME WHAT THE LOGIN SCREEN ACTUALLY OFFERS.
            // It read "The member app signs you in with Google Sign-In" until
            // 2026-08-19, which stopped being true when email/password became
            // the member app's PRIMARY way in — and the wrong version was live
            // on the published policy, so members were signing in by a method
            // their own privacy policy did not disclose. Guarded by
            // `policy_registry_test.dart` → "the sign-in section names every
            // method the login screen offers", which reads `login_screen.dart`
            // rather than trusting this comment.
            'The member app signs you in with an email address and password, '
            'or with Google Sign-In. Trainersarena and Alphasarena Admin use an '
            'email address and password.\n\n'
            'We do not store your password — it is handled entirely by Firebase '
            'Authentication and never reaches our application code.\n\n'
            'When you enable notifications we store that device\'s messaging '
            'token on your own record. Tokens are written only by our server, '
            'are limited to ten devices per account, are removed from a '
            'previous account when the same device signs in as someone else, '
            'and are removed when you sign out.',
      ),
      PolicySection(
        'Health, body and fitness information',
        'This is the most sensitive information on the platform.\n\n'
            // ⚠️ EVERY FIELD THE PROFILE EDITOR COLLECTS MUST APPEAR IN THIS
            // POLICY. `height` and `goalWeight` were collected by
            // `ProfileEditField` and written to
            // `clientProfiles.profile.bodyMetrics` from the first release, and
            // appeared ZERO times in the published policy until 2026-08-19 —
            // under-disclosure, which is the direction that harms members and
            // the direction a Play Data Safety review compares against. Guarded
            // by `policy_registry_test.dart` → "every field the profile editor
            // collects is disclosed", which reads the ProfileEditField enum
            // rather than trusting this comment.
            '• Height, body weight and the goal weight you set\n'
            '• Body fat and measurements such as waist, chest, arms, hips and '
            'thighs\n'
            '• Sleep — bedtime and wake time, and the duration derived from '
            'them\n'
            '• Step counts and water intake\n'
            '• The supplement plan your coach sets and the doses you record\n'
            '• Food you log, with calories, protein, carbohydrate, fat, fibre '
            'and related values\n'
            '• Workouts prescribed to you and what you actually performed, '
            'including per-set repetitions and weights\n'
            '• Check-ins and weekly reports, including free text you write\n'
            '• Onboarding answers, including any health information you provide '
            'and any documents you upload\n\n'
            'Your coaching organization can see this information. That is how '
            'coaching works here.',
      ),
      PolicySection(
        'Emergency contact',
        // ⚠️ THIS IS PERSONAL DATA ABOUT SOMEONE WHO NEVER AGREED TO ANYTHING.
        // The member types another person's phone number. That person is not a
        // user of Alphasarena, cannot see the record, and cannot ask for it to
        // be removed — only the member can. A policy that lists every field the
        // MEMBER gives about THEMSELVES and stays silent about the one field
        // that is about a THIRD PARTY has the disclosure gap exactly backwards.
        //
        // The sentence about it not reaching the organization is a claim about
        // code, and it is checked: `clientProfiles/{uid}` is readable only by
        // `request.auth.uid == uid` (firestore.rules), and the coach projection
        // in `member_profile_form.dart` deliberately keeps `emergencyContact`
        // out of `contact` so the projection cannot carry it. If either changes,
        // this paragraph becomes false and must change with it.
        'If you choose to give an emergency contact, we store the phone number '
            'you enter on your own profile.\n\n'
            'That number belongs to another person, so give it only if they are '
            'content for you to. It is not shared with your coaching '
            'organization or your coach, and it is not used to contact anyone '
            'automatically — it is held so it can be found if you or someone '
            'acting for you needs it.\n\n'
            'You can change or remove it at any time from your profile, and it '
            'is deleted with the rest of your profile when you delete your '
            'account.',
      ),
      PolicySection(
        'Photographs and documents',
        '• Progress and transformation photographs you upload\n'
            '• Profile photographs\n'
            '• Exercise demonstration videos and organization media uploaded '
            'by coaches\n'
            '• Documents you upload when answering onboarding questions',
      ),
      PolicySection(
        'Messages',
        'The messages exchanged between a member and their coaching '
            'organization, including message text, who sent it, when, and any '
            'media attached.',
      ),
      PolicySection(
        'Payment information',
        'Payments are processed by Razorpay.\n\n'
            'Card, bank and other payment credentials are entered in '
            'Razorpay\'s own payment interface and do not reach our servers.\n\n'
            'We hold order and payment identifiers, the amount and currency, '
            'any discount or coupon applied, receipts, the result of payment '
            'verification, and records relating to refunds and settlement.\n\n'
            'We hold bank account details only where a coaching organization '
            'provides them so it can be paid. Those belong to the '
            'organization, not to members.',
      ),
      PolicySection(
        'Employment information (organizations only)',
        'Where an organization uses the staff-management features, we hold '
            'employment records for its trainers — which may include date of '
            'birth, home address, employment type and dates, salary '
            'agreements, salary payments, and documents such as contracts and '
            'identity documents.\n\n'
            'This information is private to that organization, and is not '
            'readable by Alphasarena operators — see "Operator access".',
      ),
      PolicySection(
        'Who can see your information',
        'You see your own information.\n\n'
            'Your TRAINER sees members assigned to them, within their own '
            'organization only, and their access to specific features is '
            'controlled by permissions the organization grants. Trainers '
            'cannot read member feedback submitted about them.\n\n'
            'Your ORGANIZATION OWNER sees all data belonging to their own '
            'organization, and cannot see another organization\'s data.\n\n'
            'Access is enforced by server-side security rules, not only by '
            'what an app chooses to display.',
      ),
      PolicySection(
        'Alphasarena operator access',
        'We would rather tell you this plainly.\n\n'
            'Direct database access by Alphasarena operators is limited to a '
            'specific, listed set of collections needed to run the platform. '
            'Anything not explicitly listed is denied by default. Employment '
            'records, salary agreements, salary payments and HR documents are '
            'NOT readable by Alphasarena operators — that restriction is '
            'enforced by the security rules themselves.\n\n'
            'Some platform functions run with administrative privileges on our '
            'servers so we can provide support, resolve payment problems and '
            'operate the service. Those functions can reach organization and '
            'member data, including health information, where it is necessary '
            'for the task.\n\n'
            'These accesses are recorded. Every privileged function call is '
            'written to an access register, and privileged changes are written '
            'to an audit log. Neither record can be edited or deleted by '
            'anyone, including Alphasarena operators.',
      ),
      PolicySection(
        'How we use your information',
        'To create and secure your account and sign you in; to deliver '
            'coaching — plans, targets, messages, calls and progress; to show '
            'you and your coach the information described here; to process '
            'payments and memberships; to send notifications you have not '
            'turned off; to detect and investigate misuse; and to provide '
            'support.\n\n'
            'We do not sell your personal information.\n\n'
            'There is no advertising, analytics or tracking software in any '
            'Alphasarena application. We do not build advertising profiles and '
            'we do not share your information with advertising networks. That '
            'is a property of how the apps are built, not only a promise.',
      ),
      PolicySection(
        'Notifications',
        'We send notifications through Firebase Cloud Messaging and an in-app '
            'notification centre, across categories including calls, messages, '
            'coaching, membership, billing, organization, security, system, '
            'announcements and marketing.\n\n'
            'You can turn most notifications off, by category or by individual '
            'event, and set quiet hours and a do-not-disturb period.\n\n'
            'Some are always delivered because silencing them would be unsafe '
            'or misleading: incoming calls, security notices, notice that an '
            'organization has been blocked, and notice that a membership or '
            'subscription has ended.\n\n'
            'Marketing notifications are off unless you turn them on — the only '
            'category that works this way.\n\n'
            'In-app notification items are kept for 90 days and then removed '
            'automatically.\n\n'
            'The only email the platform itself sends is a password-reset '
            'email, and only for operator accounts.',
      ),
      PolicySection(
        'Your device',
        'We hold the notification token described above, and information '
            'needed to operate and secure the service, including records of '
            'function calls and errors generated by our hosting provider.\n\n'
            'Permissions: the member app uses your camera and your photo '
            'library (progress and profile photos), and notifications. '
            'Trainersarena additionally '
            'uses the camera and photo library for exercise media. Alphasarena '
            'Admin is a web application and asks for no device permissions.',
      ),
      PolicySection(
        'Information stored on your device',
        'A small amount, so the apps work properly: your light/dark theme '
            'preference, unsent workout drafts, a local record of recent '
            'actions, a cached postcode lookup, and setup markers.\n\n'
            'The applications contain no cookies, no tracking technologies, no '
            'advertising identifiers and no analytics software.\n\n'
            'Alphasarena Admin runs in a browser, where the Google sign-in '
            'library keeps its own session so you are not signed out on every '
            'page load.',
      ),
      PolicySection(
        'Where your information goes',
        'Your information is stored using Google Firebase — Cloud Firestore, '
            'Cloud Storage, Firebase Authentication, Cloud Functions, Cloud '
            'Messaging and App Check.\n\n'
            'Other services that receive information:\n'
            '• RAZORPAY — payment transaction information, to process payments '
            'and refunds\n'
            '• GOOGLE SIGN-IN — account information you choose to share, if you '
            'sign in that way\n'
            '• USDA FOODDATA CENTRAL — the TEXT OF FOOD SEARCHES you run. When '
            'you search for a food that is not already in the app\'s own data, '
            'the words you type are sent to this public service to retrieve '
            'nutrition values.\n'
            '• GOOGLE FONTS — a request for the fonts the apps display\n\n'
            'Our backend runs on Google infrastructure in the United States '
            '(our server functions run in the us-central1 region), so your '
            'information is stored and processed outside India. Each provider '
            'above processes information on its own infrastructure under its '
            'own terms.',
      ),
      PolicySection(
        'Deleting your account',
        'IF YOU ARE A MEMBER, you can delete your account in the app. This '
            'deletes your member profile record — the identity details you '
            'entered, your contact details, your notification preferences and '
            'your measurement log — your profile photograph, your '
            'transformation photographs, photographs attached to your weekly '
            'reports, and your sign-in account.\n\n'
            'WHAT IS NOT DELETED: your coaching organization\'s own record of '
            'you — the client record it created, your payment history, the '
            'training and coaching logs it reviewed, the documents you '
            'uploaded when answering its onboarding questions, and your chat '
            'correspondence with your coach, including any photographs and '
            'voice notes you sent in it. That record '
            'belongs to the organization as the business record of a '
            'commercial relationship, and may be subject to its own accounting '
            'and record-keeping obligations. Contact your organization '
            'directly about its record of you.\n\n'
            'Deletion is carried out by our server, so it does not depend on '
            'your device staying connected once it has started. If it cannot '
            'complete — for example you are offline when you ask — the app '
            'tells you what happened rather than reporting success, and says '
            'whether anything was already removed. It never reports that '
            'nothing was deleted when something was. Asking again is safe: the '
            'process resumes where it stopped and never deletes anything '
            'twice.\n\n'
            'IF YOU ARE A COACH OR ORGANIZATION OWNER, there is currently no '
            'self-service account deletion. Contact $contact.\n\n'
            'We do not currently offer a data export or download feature. We '
            'would rather say so than imply one exists.',
      ),
      PolicySection(
        'How long we keep information',
        'In-app notification items are removed automatically after 90 days.\n\n'
            'Audit logs, the privileged-access register, financial ledger '
            'entries, employment event history and trainer identifier '
            'reservations are permanent and cannot be edited or deleted by '
            'anyone, including Alphasarena operators. They exist so privileged '
            'actions and money movements remain reconstructable.\n\n'
            'Records your organization keeps about you remain with that '
            'organization.\n\n'
            'We may retain information where needed for accounting, tax, '
            'payment, security, fraud prevention or dispute handling, or where '
            'retention is otherwise legally required.\n\n'
            'Other than the ninety-day notification period and the permanent '
            'records above, information is kept for as long as your account — '
            'or your organization\'s record of you — exists. This policy does '
            'not promise any other fixed retention period.',
      ),
      PolicySection(
        'Security',
        'We protect your information using authentication provided by Firebase '
            'Authentication; server-side security rules that decide what each '
            'account may read and write, enforced by the database rather than '
            'by the app; server-side validation of privileged actions, so a '
            'client cannot grant itself access, change its own subscription or '
            'activate a payment; cryptographic signature verification of '
            'payment notifications; App Check on the member and coach apps; '
            'and an audit log and access register that cannot be altered.\n\n'
            'WHAT WE DO NOT CLAIM. We do not claim end-to-end encryption. We do '
            'not claim that Alphasarena operators cannot access your data — '
            '"Operator access" describes when they can. We hold no security '
            'certification and claim compliance with no specific security or '
            'privacy standard or regulation. No system is completely secure.',
      ),
      PolicySection(
        'Children',
        'Alphasarena is for adults. You must be at least 18 years old to use '
            'it.\n\n'
            'The member app asks for your date of birth during onboarding and '
            'will not create a profile for anyone under 18. If we learn that '
            'an account belongs to someone under 18, we will close it.\n\n'
            'If you believe a child is using the platform, contact $contact.',
      ),
      PolicySection(
        'Your choices and contact',
        'You can change notification categories, individual events, quiet '
            'hours and do-not-disturb in the app; marketing is off unless you '
            'enable it. You can edit or clear the details you provided. '
            'Members can delete their account as described above.\n\n'
            'Alphasarena operates under the law of India. The specific rights '
            'available to you depend on the law that applies to you, and '
            'nothing in this policy takes away a right that law gives you. '
            'This policy does not claim certification under any particular '
            'data-protection regime.\n\n'
            'Questions or requests: $contact',
      ),
    ],
  );

  /* ──────────────────────────── TERMS OF SERVICE ───────────────────────── */

  static const PolicyDocument _terms = PolicyDocument(
    id: PolicyId.terms,
    summary:
        'The agreement for using Alphasarena — accounts, coaching, payments, '
        'acceptable use and termination.',
    sections: [
      PolicySection(
        'About these terms',
        'These terms govern your use of Alphasarena and its applications: '
            'Trainersarena, the Alphasarena member app, and Alphasarena Admin.\n\n'
            'Our Privacy Policy, Refund & Cancellation Policy and Health, '
            'Fitness, Nutrition & Wellness Disclaimer form part of these '
            'terms.\n\n'
            'Alphasarena is the name under which the service is operated and '
            'published. It is operated from India. Contact: $contact.',
      ),
      PolicySection(
        'What Alphasarena provides',
        'Alphasarena provides coaching SOFTWARE. It lets coaching '
            'organizations manage members, build workout and nutrition plans, '
            'communicate and take payment; and it lets members follow those '
            'plans and record their progress.\n\n'
            'Alphasarena does not provide coaching, training, dietary or '
            'medical services. Your coaching relationship is with the '
            'organization you join, not with Alphasarena.',
      ),
      PolicySection(
        'Eligibility and accounts',
        'You must be at least 18 years old, and able to enter a binding '
            'agreement, to use Alphasarena.\n\n'
            'Members sign in with Google Sign-In. Coaches and organization '
            'owners use an email address and password.\n\n'
            'If you are a trainer, your account is created for you by your '
            'organization, which sets your initial credentials and decides what '
            'you may access. You do not register yourself.\n\n'
            'You are responsible for keeping your sign-in secure, for activity '
            'under your account, and for the accuracy of your details.',
      ),
      PolicySection(
        'The coaching relationship',
        'Your coaching organization writes your coaching. Workout plans, '
            'nutrition targets, supplement plans and lifestyle targets are '
            'created by your coach or organization. Alphasarena delivers and '
            'records them; it does not write, review or endorse them.\n\n'
            'Your organization sets its own prices, membership plans and any '
            'discounts, and is responsible for honouring them. It can see the '
            'information you record, and it keeps its own business record of '
            'you — including after you delete your account.\n\n'
            'If you have a concern about the coaching you receive, raise it '
            'with your organization first.',
      ),
      PolicySection(
        'Memberships (members)',
        'Membership plans are created and priced by your coaching '
            'organization.\n\n'
            'A membership is for a FIXED TERM. When the term ends, '
            'membership-dependent access ends until a new membership is '
            'purchased.\n\n'
            'Your organization may pause ("freeze") your membership. While '
            'frozen, remaining time is preserved and credited when it resumes. '
            'A freeze is not a refund.\n\n'
            'If your membership ends or is frozen, coaching content may stop '
            'being delivered to you. This is enforced by our servers, not only '
            'in the app.',
      ),
      PolicySection(
        'Subscriptions (organizations)',
        'A subscription enables your organization\'s use of Trainersarena and sets '
            'its usage limits, such as the number of trainers and members.\n\n'
            'A subscription is for a FIXED TERM. When it expires, your ability '
            'to create and change data is restricted until it is renewed. Your '
            'existing data remains visible — the restriction is on operating, '
            'not on reading.',
      ),
      PolicySection(
        'Payments, and no automatic renewal',
        'Alphasarena does not automatically renew memberships or subscriptions, '
            'and does not store a recurring payment mandate. When a term ends, '
            'access ends unless a new purchase is made. You will not be charged '
            'again automatically.\n\n'
            'Payments are processed by Razorpay; payment credentials are '
            'entered in Razorpay\'s own interface and do not reach our '
            'servers. The amount payable is calculated by our servers and shown '
            'to you before you pay, including any discount and any applicable '
            'tax. If you renew before your current term ends, the new term is '
            'added to the time you already have, so you do not lose days. '
            'Payments are verified by our servers before access is granted.\n\n'
            'Refunds are covered by the Refund & Cancellation Policy. Please '
            'read it before purchasing — it explains that refunds are not '
            'automatic.\n\n'
            'The price shown at checkout is the full amount charged. For any '
            'invoice or tax question, contact $contact.',
      ),
      PolicySection(
        'Acceptable use',
        'You must not use the platform unlawfully; attempt to access another '
            'organization\'s or another person\'s data; attempt to circumvent '
            'security rules, permissions, usage limits or payment '
            'verification; interfere with or disrupt the service; upload '
            'content you do not have the right to use, or content that is '
            'unlawful, abusive, harassing, deceptive or infringing; use '
            'messaging or calls to harass, threaten or abuse anyone; '
            'impersonate another person or organization; use the platform to '
            'provide medical diagnosis or treatment, or present yourself as a '
            'medical professional when you are not; or resell or provide '
            'access to people it was not provided for.\n\n'
            'If you are an organization, you are responsible for the content '
            'your organization and its trainers create.',
      ),
      PolicySection(
        'Your content',
        'You keep ownership of the content you create — plans you write, '
            'messages you send, photographs and media you upload, and the '
            'information you record.\n\n'
            'You grant Alphasarena the limited permission needed to store, '
            'process, transmit and display that content so the platform can '
            'work.\n\n'
            'We do not use your content for advertising and we do not sell it. '
            'The applications contain no advertising or analytics software.\n\n'
            'Alphasarena owns the platform itself — its software, design and '
            'branding.',
      ),
      PolicySection(
        'Communications',
        'The platform sends notifications and provides messaging between '
            'members and their coaches.\n\n'
            'You can control most notifications, and marketing notifications '
            'are off unless you enable them. Some are always delivered because '
            'silencing them would be unsafe or misleading.\n\n'
            'Do not use Alphasarena\'s messaging or calling features for '
            'emergencies. See the Health Disclaimer.',
      ),
      PolicySection(
        'Health and fitness',
        'Alphasarena is not a medical provider and does not provide medical '
            'advice. Workout plans, nutrition targets, supplement plans and '
            'wellness information are not medical advice, diagnosis or '
            'treatment, and are not a substitute for advice from an '
            'appropriately qualified professional.\n\n'
            'The Health, Fitness, Nutrition & Wellness Disclaimer forms part of '
            'these terms.',
      ),
      PolicySection(
        'Availability',
        'We work to keep Alphasarena available and working correctly, but we '
            'provide it "as is" and "as available". We do not warrant that it '
            'will be uninterrupted, error-free, or that it will meet any '
            'particular requirement. Features may change.\n\n'
            'The platform depends on third-party services — including Google '
            'Firebase for hosting and Razorpay for payments — and on your '
            'device and network.\n\n'
            'To the maximum extent permitted by applicable law, Alphasarena '
            'disclaims implied warranties and is not liable for indirect or '
            'consequential loss arising from use of the platform. Nothing in '
            'these terms excludes or limits liability that cannot be excluded '
            'or limited under applicable law.',
      ),
      PolicySection(
        'Suspension and termination',
        'You may stop using Alphasarena at any time. Members can delete their '
            'account in the app; coaches and organization owners should '
            'contact us.\n\n'
            'We may suspend, restrict or terminate access where an account or '
            'organization breaches these terms or applicable law, where '
            'required for security, or where a payment cannot be verified. An '
            'organization may also be restricted automatically when its '
            'subscription expires.\n\n'
            'Where reasonably possible we will tell you why access was '
            'restricted and how to respond — write to $contact. Provisions '
            'that by their nature should survive termination — including '
            'payment obligations, your organization\'s record-keeping, and '
            'the permanent records described in the Privacy Policy — survive '
            'it.',
      ),
      PolicySection(
        'Deletion and retention',
        'Deleting your account does not delete everything about you. Your '
            'coaching organization keeps its own business record, and some '
            'records — including audit, financial ledger and privileged-access '
            'records — are permanent by design and cannot be edited or deleted '
            'by anyone, including Alphasarena operators. The Privacy Policy '
            'describes this in full.',
      ),
      PolicySection(
        'Governing law and contact',
        'These terms are governed by the laws of India, and the courts of '
            'India have jurisdiction over disputes arising from them.\n\n'
            'If the consumer-protection law that applies where you live gives '
            'you rights that cannot be excluded by agreement, those rights are '
            'unaffected by this section.\n\n'
            'Contact: $contact',
      ),
    ],
  );

  /* ───────────────────── REFUND & CANCELLATION POLICY ──────────────────── */

  static const PolicyDocument _refund = PolicyDocument(
    id: PolicyId.refund,
    summary:
        'How cancellation and refunds actually work — including what is not '
        'automatic.',
    sections: [
      PolicySection(
        'What this covers',
        'Two kinds of purchase: MEMBERSHIPS, sold by your coaching '
            'organization to members; and SUBSCRIPTIONS, sold by Alphasarena to '
            'coaching organizations.\n\n'
            'Read this together with the Terms of Service.',
      ),
      PolicySection(
        'What you are buying',
        'You are buying access for a FIXED TERM. You are not entering a '
            'recurring subscription.\n\n'
            'The term is stated before you pay. When it ends, the access it '
            'provided ends.\n\n'
            'Nothing renews automatically. You will not be charged again '
            'automatically. There is no recurring payment mandate stored '
            'anywhere in the platform.\n\n'
            'If you buy again before your current term ends, the new term is '
            'added to the time you already have, so you do not lose days.',
      ),
      PolicySection(
        'How payments are handled',
        'Payments are processed by Razorpay. Payment credentials are entered '
            'in Razorpay\'s own interface and do not reach Alphasarena\'s '
            'servers.\n\n'
            'The amount payable — including any discount and any applicable tax '
            '— is calculated by our servers and shown to you before you pay, '
            'and payments are verified by our servers before access is '
            'granted.\n\n'
            'We keep a record of each transaction, including the order and '
            'payment identifiers, the amount, any discount, and the '
            'verification result. That record is what any refund request is '
            'assessed against.',
      ),
      PolicySection(
        'Cancellation',
        'There is no cancellation button, because there is nothing recurring '
            'to cancel.\n\n'
            'To stop future charges, do nothing — your access simply ends when '
            'the paid term ends. To stop using Alphasarena sooner, you can stop '
            'at any time, and members can delete their account in the app.\n\n'
            'Cancelling, stopping use, or deleting your account does not by '
            'itself create a refund.\n\n'
            'If you are a member, your membership is sold by your coaching '
            'organization, so speak to them first. They may be able to pause '
            '("freeze") it instead — while frozen, your remaining time is '
            'preserved and credited when it resumes. A freeze is not a refund.',
      ),
      PolicySection(
        'How refunds actually work',
        'Refunds are NOT AUTOMATIC. Nothing in the platform issues a refund on '
            'its own — not on cancellation, not on account deletion, not on '
            'expiry, and not on non-use.\n\n'
            'There is NO SELF-SERVICE REFUND. There is no button, form or '
            'in-app flow that requests or issues one.\n\n'
            'Refunds are issued manually by authorized Alphasarena '
            'administration, using the payment provider, after review. A refund '
            'may be full or partial, and every refund is recorded against the '
            'original transaction.\n\n'
            'TO REQUEST ONE: if you are a member, contact your coaching '
            'organization first — they hold the commercial relationship with '
            'you and the record of what was provided. If you are an '
            'organization, or your organization cannot resolve it, contact '
            '$contact. Please include the payment identifier or receipt, the '
            'date, the amount, and what you are asking for and why.',
      ),
      PolicySection(
        'What we take into account',
        'Whether a refund is appropriate depends on the circumstances of the '
            'specific transaction, including the policy published when you '
            'bought; whether the service was actually provided and how much of '
            'the term was used; whether coaching, plans or other content were '
            'delivered; whether the payment completed and was verified '
            'correctly, and whether any technical fault occurred; whether '
            'there is an unresolved dispute or indications of fraud or abuse; '
            'and any rights you have under applicable law.\n\n'
            'This policy deliberately does not state a refund window, a '
            'refund percentage, a pro-rata formula, or conditions under which '
            'a refund is guaranteed. Refunds are considered case-by-case '
            'against the factors above, and no automatic entitlement should '
            'be inferred from this document.\n\n'
            'Where Alphasarena collects payment for a membership sold by a '
            'coaching organization, refund decisions are made together with '
            'that organization, which holds the commercial relationship with '
            'you.',
      ),
      PolicySection(
        'Applicable law takes precedence',
        'Nothing here limits any right you have under the law that applies to '
            'you. Where applicable law gives you a right to cancel or to a '
            'refund, that law prevails over this policy.\n\n'
            'Alphasarena operates under the law of India, including its '
            'consumer-protection law.',
      ),
      PolicySection(
        'Payment problems, disputes and timing',
        'If a payment is taken but access is not granted, contact us with the '
            'payment identifier. Our systems are built so one payment activates '
            'access exactly once and a retry cannot create a second charge for '
            'the same order — but if you believe you have been charged twice or '
            'charged without receiving access, tell us and we will check.\n\n'
            'If you raise a dispute or chargeback with your bank, we may pause '
            'or reverse related access while it is resolved, and we will '
            'cooperate with the payment provider\'s dispute process.\n\n'
            'We aim to acknowledge refund requests and tell you the outcome, '
            'including our reasons where we decline. No fixed response '
            'timeframe is promised.\n\n'
            'The policy that applies to a purchase is the one published at the '
            'time of that purchase.\n\n'
            'Contact: $contact',
      ),
    ],
  );

  /* ────────────────────────── HEALTH DISCLAIMER ────────────────────────── */

  static const PolicyDocument _health = PolicyDocument(
    id: PolicyId.healthDisclaimer,
    summary:
        'Alphasarena is not a medical provider, and coaching content is not '
        'medical advice.',
    sections: [
      PolicySection(
        'Alphasarena is not a medical provider',
        'Alphasarena provides coaching software. It is not a healthcare '
            'provider, a medical service or a clinical tool.\n\n'
            'We do not provide medical advice, diagnosis, treatment or '
            'monitoring, and using Alphasarena does not create a '
            'doctor–patient or any other clinical relationship.',
      ),
      PolicySection(
        'Your plan is written by your coach',
        'Workout plans, nutrition targets, supplement plans and lifestyle '
            'targets are created by your coach or coaching organization.\n\n'
            'Alphasarena delivers and records them. We do not write, review, '
            'approve or endorse them, and we do not assess whether a plan is '
            'appropriate for you.',
      ),
      PolicySection(
        'Coaching content is not medical advice',
        'Everything you receive through Alphasarena — workouts, exercises, '
            'calorie and macronutrient targets, meal guidance, supplement '
            'plans, hydration, step and sleep targets — is general fitness and '
            'wellness information, not medical advice.\n\n'
            'It is not a substitute for advice, diagnosis or treatment from an '
            'appropriately qualified professional, and should not be used to '
            'diagnose or treat any condition.',
      ),
      PolicySection(
        'Coaches are not automatically medical professionals',
        'Coaches and trainers set their own profiles, including any '
            'qualifications, certifications and experience they choose to '
            'list.\n\n'
            'Alphasarena does not verify those qualifications, and being on the '
            'platform does not mean a coach is a doctor, dietitian, '
            'physiotherapist or other regulated healthcare professional. If a '
            'specific qualification matters to you, ask your coach directly.',
      ),
      PolicySection(
        'Please talk to a qualified professional',
        'We recommend speaking with an appropriately qualified professional — '
            'such as your doctor — before you begin a new exercise programme or '
            'significantly increase what you already do; make significant '
            'changes to your diet or calorie intake; start taking any '
            'supplement; or follow any plan while pregnant, recovering from '
            'injury or surgery, managing an existing medical condition, or '
            'taking prescribed medication.',
      ),
      PolicySection(
        'You know your own circumstances',
        'Only you and your professional advisers know your full medical '
            'history, current condition and limitations.\n\n'
            'You are responsible for deciding whether any plan is suitable for '
            'you, for telling your coach anything relevant, and for following '
            'professional advice you have been given — including where that '
            'advice differs from what a plan suggests.\n\n'
            'Listen to your body. Stop and seek appropriate help if you feel '
            'unwell or experience pain, dizziness, shortness of breath, chest '
            'discomfort, or anything else that concerns you.\n\n'
            'Physical exercise carries an inherent risk of injury. By '
            'choosing to follow any plan, you accept that risk to the extent '
            'permitted by applicable law.',
      ),
      PolicySection(
        'In an emergency',
        'Do not use Alphasarena to seek help in an emergency.\n\n'
            'Messages go to your coach, who may not see them immediately and '
            'is not an emergency service.\n\n'
            'If you have a medical emergency, contact your local emergency '
            'services or go to your nearest emergency department.',
      ),
      PolicySection(
        'Supplements',
        'Supplement plans are created by your coach, not by Alphasarena.\n\n'
            'We make no claim about the safety, quality, legality, efficacy or '
            'suitability of any supplement, and we do not sell, supply or '
            'verify supplements. Supplements can interact with medication and '
            'with existing conditions. Speak to a qualified professional before '
            'taking any supplement, and check the product\'s own labelling.',
      ),
      PolicySection(
        'Nutrition information may not be accurate',
        'Nutrition values come from three places: figures entered by your '
            'coach, a bundled food dataset included with the app, and the '
            'United States Department of Agriculture\'s public FoodData Central '
            'service, which the app can search for foods not already in its own '
            'data.\n\n'
            'These values are ESTIMATES and may be incomplete, out of date or '
            'wrong for the specific food you ate. Preparation, portion size, '
            'brand and recipe all change the real values. Do not rely on them '
            'where accuracy matters medically without professional guidance.',
      ),
      PolicySection(
        'Tracking and scores are descriptive, not clinical',
        'Alphasarena calculates adherence percentages, progress trends, '
            'streaks and weekly summaries from what you and your coach '
            'record.\n\n'
            'These are simple descriptive summaries of the data you entered. '
            'They are not clinical measurements, diagnoses or health '
            'assessments, and they do not evaluate your health.\n\n'
            'The platform does not use artificial intelligence or machine '
            'learning to analyse your health data or generate recommendations. '
            'Every figure is produced by fixed, predefined calculations over '
            'the data you and your coach entered.\n\n'
            'Body measurements, weight, body fat, sleep and step figures are '
            'self-reported by you and are only as accurate as what you record.',
      ),
      PolicySection(
        'Results vary',
        'Outcomes depend on many factors neither Alphasarena nor your coach '
            'controls — health, genetics, consistency, sleep, stress, '
            'environment and circumstances.\n\n'
            'We make no promise about the results you will achieve. Any '
            'transformation photographs, testimonials or statistics shown on a '
            'coach\'s profile are that coach\'s own material, describing '
            'individual experiences that are not a prediction of your outcome.',
      ),
      PolicySection(
        'If you are a coach',
        'You are responsible for the plans and guidance you give, for staying '
            'within your own competence and qualifications, and for complying '
            'with any professional obligations or regulations that apply to '
            'you.\n\n'
            'Do not use Alphasarena to diagnose or treat a medical condition, '
            'or to present yourself as a healthcare professional if you are '
            'not one.',
      ),
    ],
  );
}
