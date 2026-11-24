# Stride: setup guide

Stride is a study app where students sign in with Google, or with an email and password, and pick a nickname, which is what the leaderboard shows. You unlock the Admin page once with a passcode, and from then on Admin is tied to your account. Each account can be signed in on one device at a time.

It runs on three free or pay-as-you-go services:

| Service | What it does | Cost |
|---|---|---|
| **Supabase** | Google sign-in, database, security rules | Free tier is enough to start |
| **Vercel** | Hosts the app and its small server functions | Free "Hobby" plan (non-commercial use only; if you charge students, Vercel requires the Pro plan) |
| **Claude API** | Reads syllabuses and writes lessons | Pay per use, billed by Anthropic |

Allow about an hour for the first setup. You need a Google account, and a GitHub account for deploying.

---

## 1. Create the Supabase project

1. Go to **supabase.com**, sign up and click **New project**. Pick the region closest to your students and save the database password somewhere safe.
2. When it's ready, open **SQL Editor → New query**, paste everything from `supabase/schema.sql`, and click **Run**. It should finish with "Success".
3. Open **Project Settings → API** (in newer dashboards: **API Keys**) and note three values:
   - **Project URL** → this is `SUPABASE_URL`
   - **anon / publishable** key → this is `SUPABASE_ANON_KEY` (safe to be public)
   - **service_role / secret** key → this is `SUPABASE_SERVICE_ROLE_KEY` (**never share this or put it in the app's code**)

## 2. Turn on Google sign-in

1. Go to **console.cloud.google.com**, create a project, then open **APIs & Services → OAuth consent screen**. Choose **External**, fill in the app name (Stride) and your email, and save.
2. Open **Credentials → Create credentials → OAuth client ID**, type **Web application**.
3. Under **Authorized redirect URIs** add:
   `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`
   (Your project ref is the part of your Supabase Project URL before `.supabase.co`. Supabase also shows this exact URL on its Google provider page.)
4. Copy the **Client ID** and **Client secret**.
5. In Supabase, open **Authentication → Sign In / Providers → Google**, switch it on, paste the Client ID and secret, and save.
6. Publish the consent screen (**OAuth consent screen → Publish app**) so anyone with a Google account can sign in, not just test users.
7. So that Google shows your site's address instead of the Supabase one: in the same OAuth client, add your Vercel address (for example `https://stride-study-app.vercel.app`) under **Authorized JavaScript origins**, and add a Vercel environment variable `GOOGLE_CLIENT_ID` set to the same Client ID (see step 3 below). Without it, sign-in still works through Supabase.

## 2b. Turn on email and password sign-in

Students can also create an account with an email and a password (typed twice), and sign in with those from then on. No confirmation email is needed.

1. In Supabase, open **Authentication → Sign In / Providers → Email**. Turn **Enable Email provider** on and **Confirm email** off, and save. New accounts are then signed in straight away.
2. **Forgot password?** still works by email, so it needs email sending set up: Supabase's built-in service only sends to members of your Supabase team. To set it up, use an email service such as Resend (needs a domain you own) or Brevo, and enter its SMTP details under **Authentication → Emails → SMTP Settings**. Until then, students who forget their password should ask you.

If you later want confirmation links, turn **Confirm email** back on (after setting up email sending); the app handles both.

## 3. Get a Claude API key (optional)

The API key is optional. Without one, the site's AI features switch off and you add content by importing course files instead (see **Without the Claude API** below). You can add a key at any time to switch them back on.


1. Go to **console.anthropic.com**, sign in, add a payment method and some credit under **Billing**.
2. Open **API Keys → Create key** and copy it. This is `ANTHROPIC_API_KEY`.

## 4. Deploy to Vercel

1. Put this folder in a new **GitHub** repository (on github.com: **New repository → uploading an existing file**, and drag in the folder's contents).
2. Go to **vercel.com**, sign in with GitHub, click **Add New → Project** and import the repository. Framework preset: **Other**. Leave the build settings empty.
3. Before clicking Deploy, open **Environment Variables** and add:

| Name | Value |
|---|---|
| `SUPABASE_URL` | from step 1 |
| `SUPABASE_ANON_KEY` | from step 1 |
| `SUPABASE_SERVICE_ROLE_KEY` | from step 1 |
| `ANTHROPIC_API_KEY` | from step 3 |
| `ADMIN_PASSCODE` | a passcode of **at least 8 characters** that only you know |
| `STUDENT_DAILY_AI_LIMIT` | optional, default `30` AI requests per student per day |
| `ANTHROPIC_MODEL` | optional, default `claude-sonnet-5-5` |

You'll add four more settings for reminders in step 8: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` and `CRON_SECRET`.

4. Click **Deploy**. Vercel gives you a web address like `https://stride-xyz.vercel.app`.
5. Back in Supabase, open **Authentication → URL Configuration**. Set **Site URL** to your Vercel address and add it under **Redirect URLs** too. Without this, Google sign-in sends people to the wrong place.

## 5. Make yourself admin

1. Open your Vercel address, sign in (with Google or email and password), and pick a nickname.
2. At the bottom of the home screen, tap **Admin access** and enter your `ADMIN_PASSCODE`.
3. The **Admin: add and manage subjects** button appears. Your Google account stays admin from now on, on any device.

After 5 wrong passcode attempts, that account is locked out of trying again for an hour.

**Other teachers:** give them the passcode, or skip that and make them admin yourself: Supabase **Table Editor → profiles**, find their row, set `is_admin` to `true`.
**Removing an admin:** set `is_admin` back to `false` in the same place.
**Changing the passcode:** change `ADMIN_PASSCODE` in Vercel (**Settings → Environment Variables**), then redeploy. Existing admins stay admin.

## 6. Add your first course

1. In Admin, add the course, its **category** (e.g. "JAMB & O'level", "100 Level") and the syllabus, plus any materials. Students pick one category and only see its courses, so spell each category the same way every time. Claude splits the syllabus into units and estimates how many study sessions each unit needs.
2. Under the course, set the **finish-by date**: the deadline to finish the syllabus, such as the exam date. Students never see this date; they see how long the course will take them, e.g. "Meeting your targets every day, you'll finish this course in about 6 weeks". Open **Units and sessions** to adjust how many sessions each unit has (Claude estimates them from the syllabus), then tap **Save exam date and units**. Students' daily targets are worked out from these. The **typical session length** (15 minutes by default) is only used for the time estimates students see.
3. Tap **Prepare level 1** so lessons are ready for students. Preparing is done once with your account, so it doesn't count toward students' daily limits.

### Without the Claude API: importing course files

If `ANTHROPIC_API_KEY` isn't set in Vercel, the site never calls Claude, so it needs no API credits. Lessons and past questions are prepared outside the site, by Claude in chat or by any other AI, and imported:

1. In Admin, add the course with its category. You can type its topics, one per line, or leave them for the course file. Upload its materials as PDF or Word files: their pictures are cropped out and saved, and their text is kept. Students don't see a course until it has topics.
2. Tap **Download for AI** on the course. This gives you a text file with the instructions for the AI (from `public/ai-prompt.txt`), the course's topics, its pictures and the text of its materials. For a course that isn't in the app yet, use **Download the general AI prompt** instead.
3. Give that file and the syllabus to the AI (or send everything to Claude in chat). It replies with a course file: every syllabus topic with 3 lesson levels, plus any past questions. Topics in the materials but not in the syllabus are left out. Topics the materials don't cover are still written, and marked as written by AI.
4. In Admin → **Import course content**, upload the file or paste the reply, then tap **Import**. Several batches can be imported together. Importing again updates the course: topics are matched by name, levels in the file replace the old ones, and past questions already there are skipped. Any problems in the file are listed, so you can send them back to the AI to fix just those parts.
5. Open **Review lessons → Written by AI** and check those items. Tap **Looks right** or **Edit** to clear each one.

While AI is off, students who reach a level that isn't prepared see "not ready yet". Photos of question papers and past papers in PDF form need AI to be read, so have them turned into a course file instead.

### Students and activity (Admin → Students and activity)

Only admins can open this page; the database refuses anyone else. It shows nicknames, never email addresses.
- **Overview:** total students and new sign-ups this week; how many studied today, this week and this month.
- **Engagement:** how many students with a target today have met it, average target days in the last 7 days, average current streak (and how many are on 7+ days), and how many have reminders on.
- **By category** and **by course:** students per category; for each course, registrations, how many were active this week, average topics mastered, and each topic's quiz results.
- **Topics students struggle with:** topics where at least 3 students took the quiz and fewer than 60% passed.
- **All students:** search by nickname, filter by category or activity ("Quiet for 7+ days" finds students who've gone quiet), and sort by last active, XP, streak or newest. Each shows category, join date, last studied, streak, topics mastered, lessons, reminders and registered courses.

"Today" uses the admin's date, so for students in other time zones the daily figures can be off by a few hours.

### Editing and deleting (Admin → each subject)

- **Units and sessions:** rename, add or remove units, and set each unit's sessions. **0 sessions** keeps a unit for practice but leaves it out of students' daily targets. Removing a unit also deletes its prepared lessons (you're asked to tap twice). Tap **Save exam date and units** to apply changes.
- **Study materials:** **Remove** deletes a file and any of its images that aren't used in a lesson. Lessons already written from it stay until you rewrite them in Review lessons.
- **Past-question imports:** in **Past questions → Imports**, **Delete all** removes everything from one import (one file, or one page range of a PDF) along with its images. Useful if an import went wrong or was done twice.
- **Whole subject:** **Remove subject** deletes everything in it.

### Checking content (Admin → each subject)

- **Review lessons:** every prepared level, unit by unit, with facts, explanations, worked examples, questions and their figures. **Edit** any item to fix the fact, explanation, example, worked steps, answer, common mistakes, or any question's text, options, correct answer, difficulty, explanation and steps, with a live preview of how students will see it (including maths and chemistry formatting). You can also tap an option to make it the correct one, **Remove** an item (students' progress is kept), or **Rewrite this level**.
- **Images:** every image cut out of your materials and past questions, showing which file and page it came from and how often it's used. Edit captions, **Replace with JPG** (other image types are converted to JPG automatically) or **Remove**. A replaced image updates everywhere it's used.
- **Past questions:** import and check past papers (below).

### Images in materials

Diagrams, graphs and pictures are kept when you upload materials:
- **PDF:** each page is scanned for pictures and drawn diagrams, which are cut out as JPGs. A caption is taken from a nearby "Fig…" or "Diagram…" line.
- **Word (.docx):** embedded pictures are saved.
- **Photos of pages:** Claude transcribes the text and marks where diagrams are, and they're cut out of the photo.

When Claude writes a lesson, it is shown the diagrams near the matching passages and can attach one to a fact, worked example or question ("Study the diagram above…").

Detection is automatic, so check the **Images** screen after uploading. Tables or page decorations are sometimes picked up as figures (remove them), and a figure can be cropped badly (replace it with a clean JPG).

### Past questions

Admin → subject → **Past questions** → choose files (PDF, photos or JSON) → **Import**. Questions are stored exactly as written; Claude never rewrites them. Students see a **Past questions** panel on the subject page with "Practise 10 questions" and a button per year, timed like other questions.

- **PDF past papers:** two-column layouts are read in the right order, subscripts and superscripts are kept (H₂SO₄, 10²³, Cu²⁺), and diagrams are cut out and attached to their questions. Claude is shown the diagrams, so questions whose options are drawn as pictures (e.g. structural formulas) and diagram questions can be read and solved. Pictures that don't belong to any question, like adverts, are discarded. For a book with several subjects, enter the **page range** for one subject at a time; 50–100 pages per import works well, and the browser must stay open until it finishes. Importing the same pages twice creates duplicates; delete the extra import under **Imports**. If the paper has an answer section (headed "Answers", "Answer key" or "Marking scheme"), it's used. Questions without an answer are solved by Claude and marked **Answer by Claude**.
- **Photos of a paper (JPG or PNG):** select all the pages of one paper together, including the answer page if there is one, and import. Claude reads each photo, keeps the questions exactly as written, cuts out diagrams and uses the answer key if it finds one; questions without an answer are solved by Claude and marked **Answer by Claude**. Pages are read in file-name order (IMG_1, IMG_2, …), so photograph them in order. Import one paper at a time. For best results, take each photo straight on, in good light, with the whole page in view. Each photo is one Claude request.
- **JSON files:** select the JSON together with its image files. Many layouts work, for example:

```json
{ "questions": [
  { "question": "Which apparatus is shown?", "options": {"A": "Funnel", "B": "Burette", "C": "Pipette", "D": "Beaker"},
    "answer": "A", "image": "fig12.jpg", "year": 2019, "explanation": "It is a filter funnel." },
  { "q": "\\(\\dfrac{36}{18}\\) = ?", "choices": ["1", "2", "3", "4"], "correct": 2 }
] }
```

  Options can be a list, an A–D object, or separate `optionA`… fields. The answer can be a letter, the option text, or a number (1 = first option). Images can be file names of images you select with the JSON, or `data:` images inside the file.
- **Checking:** with the checkbox on, Claude writes explanations where a question has none, sorts each question into a syllabus unit, and solves every question. If its answer differs from the file's, the question is marked **Check**. Open **Needs checking**, then tap the right option or press **Answer is right**.


**Theory questions.** A course file's `past_questions` can also hold written-answer questions (`"k": "th"`) with a `ctx` (shared intro), `p`, `marks`, `points` (each with `t`, `kw` key words, `m` marks) and a `model` answer. Students write an answer and see a green tick or red cross for each key point plus the model answer, earning 5 XP per key point covered. Without a Claude API key the app checks for the key words (it ignores them after "not"/"non", allows small spelling slips, and `a * b` means b within a few words after a). With a key set, Claude marks each point by meaning instead. Students find them under the course's **Theory questions** button; admins see them, with their key words, under **Past questions**.

**Practice questions.** A course file can also have a `practice_questions` list, in the same formats as `past_questions` (multiple choice or `"k": "th"`), for original exam-style problems that are not from past papers. They are imported with no year and marked as practice. Students see them in their own **Practice questions** box on the course page (10 multiple-choice or 3 theory at a time, new and missed ones first); admins see them under **Past questions** labelled **Practice**. Import them with **Import into this course**.

## One device per account

Each account can be signed in on only one device at a time. Signing in on a new phone or computer signs the account out everywhere else: the other device shows "Your account was signed in on another device" within about a minute, or as soon as it's opened. Progress is only saved from the device that's currently signed in, so a student's progress can't be overwritten by an old device. Several tabs in the same browser count as one device.

Clearing the browser's data or using a private window counts as a new device, so it takes over the account the same way.

## 7. Share it with students

Send students the Vercel link. An **Install Stride** card on the home screen helps them add it: on Android it opens the install prompt in one tap, and on iPhone it shows the steps. It disappears once installed, and "Not now" hides it for a week. To do it by hand:
- **Android (Chrome):** menu (three dots) → **Add to Home screen** or **Install app**.
- **iPhone (Safari):** Share button → **Add to Home Screen**. On iPhone, reminders only work when Stride is opened from the home screen icon (iOS 16.4 or newer).

When students first sign in, they pick a nickname, then their **category**, then **register** the courses they're taking (as many as they need). Only registered courses appear in their lessons, timetable, targets and reminders. They can change their category or register and drop courses any time from the home screen.

Next, in **My study plan**, they either tap **Create my timetable for me** (pick study days and a time, and the app spreads their courses across those days, giving busier courses more days) or set the timetable up themselves. Then they tap **Turn on reminders**.

**Leaderboards are per category:** students only see and compete with others in the same category, weekly and all-time.

## 8. Turn on phone reminders

Reminders arrive at each student's study time if today's target isn't done, then get more urgent:
- **Regular:** at their study time (4 pm if they didn't set one), showing the percentage of today's target done.
- **Serious:** from 7 pm.
- **Most serious:** from 9:30 pm.

Nothing is sent once the target is met, or on days they don't study.

1. In the app, open **Admin → Reminder setup → Generate reminder keys**. Copy the three values it shows (they're created on your phone and not saved anywhere).
2. In Vercel, **Settings → Environment Variables**, add:

| Name | Value |
|---|---|
| `VAPID_PUBLIC_KEY` | from the app |
| `VAPID_PRIVATE_KEY` | from the app (keep private) |
| `CRON_SECRET` | from the app (keep private) |
| `VAPID_SUBJECT` | `mailto:` followed by your email, e.g. `mailto:you@example.com` |

3. Redeploy: **Deployments → … next to the latest → Redeploy**.
4. Open `supabase/reminders.sql`, replace `YOUR-APP.vercel.app` with your address and `YOUR_CRON_SECRET` with your `CRON_SECRET`, then run it in Supabase's **SQL Editor**. This checks every 15 minutes who needs a reminder.

To confirm it's working, run `select * from cron.job_run_details order by start_time desc limit 5;` in the SQL Editor. Rows with status "succeeded" mean the check is running.

---

## Good to know

- **Who can change what:** the database rules in `schema.sql` only let admins change subjects, materials and lessons. Students can only change their own nickname and progress. No student can make themselves admin.
- **XP isn't tamper-proof:** progress is calculated in the student's browser, so a technical student could edit their own XP. To prevent that, scoring would need to move to the server; ask if you want it.
- **AI costs:** each prepared lesson level is one Claude request. Students only trigger requests for levels you haven't prepared and for "Learn anything" topics, capped by `STUDENT_DAILY_AI_LIMIT`.
- **Scanned PDFs** have no text to read. Upload photos of the pages instead.
- **Maths and chemistry display:** lessons show real fractions, powers, roots and chemical equations. Text written in LaTeX is rendered: inline maths between `\(` and `\)` or `$` and `$`, display maths between `$$` and `$$`, and chemistry with `\ce{}`. For example `\(\dfrac{22}{44} = 0.5\)`, `\(6.02 \times 10^{23}\)`, `\(\ce{2H2 + O2 -> 2H2O}\)`. Claude writes new lessons this way automatically.
- **JSON uploads:** JSON files are accepted for syllabuses and materials. The app reads every text value in the file, using the keys as headings, so any layout works. Maths written in LaTeX inside the file is kept and displays properly in lessons. Remember that in JSON each backslash is written twice: `"\\dfrac{1}{2}"`.
- **Streaks and targets:** a day counts toward the streak when the student finishes at least one lesson. Days when the full target is met are counted separately as **target days**, and the flame gets a gold outline.
- **Sessions are measured in content, not time.** Each unit's content (every fact and worked example across its 3 levels) is split evenly across its sessions. A session is complete when its share has been answered correctly, however long that takes; a fast student finishes sooner, a slower one takes longer. Levels not yet written are counted at the average size of the unit's written levels, so a session's size can shift slightly as later levels are written.
- **End-of-topic quiz:** when a student has completed every session of a topic, they're offered a 15-question quiz from all 3 levels of the topic, plus up to 5 past questions matched to it. Each question gets 30 seconds (45 for hard ones), and unused time carries over to the next question. There's no going back: once a student moves on, answered or skipped, the question is locked, and when the time runs out it moves on by itself. 70% or more marks the topic **Mastered** (+50 XP the first time). Below that, the student sees what they missed with explanations, the missed facts go into their review, and they can retake it. Answers are only shown at the end. Pressing × asks for a second tap and then ends the quiz, with unanswered questions counted as wrong. The pass mark and question count are `QUIZ_PASS` and `QUIZ_N` near the quiz code in `public/index.html`.
- **How targets work:** sessions left in each subject ÷ study days left in the student's timetable before the exam date. Getting ahead lowers future targets; missing a day raises them.
- **Study time** is still measured while a student is in a lesson, for pace feedback. Time on one screen counts for at most 3 minutes, so leaving the app open doesn't inflate it.
- **Large files and whole books:** there's no page or size limit beyond 2,000 pages per PDF. Files are stored in searchable parts of about a page each, and when a lesson is written the database finds the passages that best match the topic. Words match by their stem ("distil" finds "distillation"), rarer words count for more, and the topic name counts double. Only those passages are sent to Claude, labelled with their file and page. Up to 500 figures are kept per file. Files uploaded before this update still work and are searched the old way.
- **Long syllabuses** are read in sections of about 30,000 characters, then merged into one ordered list of topics, so nothing at the end is lost.
- **Updating from an earlier version:** run `supabase/schema.sql` again. It's safe to re-run and adds the new columns and tables. This version needs it (for the one-device rule), so run it **before** deploying the new files or sign-in will fail with "Could not load your account".
- **Screen sizes:** the app adapts to phones, tablets and laptops. On a laptop the home screen splits into two columns and course and topic cards sit side by side; lessons stay a comfortable reading width in the middle of the screen.

## Files

```
public/index.html     the app
public/manifest.json  lets phones install it to the home screen
api/ai.js             server: calls Claude with your key, enforces student limits
api/admin.js          server: checks the admin passcode
api/config.js         server: gives the app the public Supabase settings
api/remind.js         server: sends the escalating daily reminders
public/sw.js          shows reminders on the phone
public/pdfjs/         PDF reader (bundled, Mozilla pdf.js)
public/katex/         maths display (bundled, KaTeX)
supabase/reminders.sql  schedules the reminder check every 15 minutes
supabase/schema.sql   database tables and security rules
```
