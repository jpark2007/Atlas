/* =====================================================================
   Atlas — "Atlas vs. ___"
   Every competitor mark was checked against that company's own site or
   documentation on 2026-08-29. Where something could not be confirmed the
   cell holds '?' rather than a guess.

   Values: 'y' yes · 'n' no · 'p' partly/workaround · '?' unverified
   ===================================================================== */

const CHECKED_ON = "August 29, 2026";

const rows = [
  {
    "id": "mac",
    "label": "Works on Mac",
    "atlas": "y"
  },
  {
    "id": "mobile",
    "label": "Works on iPhone and iPad",
    "atlas": "y"
  },
  {
    "id": "apple2way",
    "label": "Syncs both ways with Apple Calendar",
    "atlas": "y"
  },
  {
    "id": "gcal2way",
    "label": "Syncs both ways with Google Calendar",
    "atlas": "y"
  },
  {
    "id": "canvas",
    "label": "Pull assignments from Canvas / your syllabus calendar",
    "atlas": "y",
    "note": "Through the Canvas calendar feed: courses, assignments and due dates. No grades and no submissions."
  },
  {
    "id": "timeline",
    "label": "Tasks and classes on one calendar",
    "atlas": "y"
  },
  {
    "id": "drag",
    "label": "Schedule work time for tasks",
    "atlas": "y",
    "note": "On the Mac, by dragging a task onto the calendar. The iPhone and iPad apps are built for capturing and glancing."
  },
  {
    "id": "capture",
    "label": "Turn a brain dump into a to-do list",
    "atlas": "y",
    "note": "Typed or spoken."
  },
  {
    "id": "review",
    "label": "Confirms before it saves anything",
    "atlas": "y"
  },
  {
    "id": "areas",
    "label": "Keeps school and personal separate",
    "atlas": "y"
  },
  {
    "id": "gdocs",
    "label": "Notes that live in Google Docs",
    "atlas": "y",
    "note": "Two-way, over the narrow drive.file scope \u2014 Atlas can only touch documents it created or that were explicitly picked."
  },
  {
    "id": "windows",
    "label": "Windows or web version",
    "atlas": "n",
    "note": "No, and none planned. Atlas is an Apple-platform app."
  },
  {
    "id": "teams",
    "label": "Shared workspaces for teams",
    "atlas": "p",
    "note": "Shared spaces and invites work in the Mac app, but Atlas is not a team collaboration tool and does not try to be."
  },
  {
    "id": "price",
    "label": "Price",
    "atlas": "Free"
  }
];

const competitors = [
  {
    "id": "notion",
    "name": "Notion",
    "tagline": "All-in-one workspace for docs, databases, projects",
    "url": "https://www.notion.com/",
    "cells": {
      "mac": "p",
      "mobile": "y",
      "apple2way": "p",
      "gcal2way": "p",
      "canvas": "n",
      "timeline": "p",
      "drag": "p",
      "capture": "y",
      "review": "p",
      "areas": "y",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "$10/user/mo (annual)"
    },
    "prose": {
      "dek": "Notion is the most flexible workspace ever built, and that flexibility is why a student calendar is the one thing it cannot hand over ready-made.",
      "intro": [
        "Notion is a workshop for building software without writing any. Pages nest inside pages, databases take whatever shape is asked of them, and millions of people run entire companies inside the result. For anyone who enjoys designing a system as much as using one, nothing else here comes close.",
        "Atlas is the opposite proposition: a native macOS app with one structure already chosen, already knowing what a course is and what a Thursday afternoon looks like. The trade-off is blunt. Notion asks what the system should be. Atlas answers that question and asks only what the week holds."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Notion's own help documentation states that the app does not natively display external calendar events beside database items. Connecting Apple, Google or Outlook means installing Notion Calendar, a separate application. Neither product can subscribe to an ICS feed, which Notion also says plainly.",
            "In Atlas, Apple Calendar and Google Calendar both sync two ways into a single timeline that also holds tasks. Dragging a task onto Thursday at four gives it a time, and the change lands back in the calendar it came from."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Notion's AI handles natural language well, but everything it produces is a page or a database row. A sentence containing a deadline, a recurring workout and a phone call has to be sorted into whatever tables exist, and those tables exist only because someone built them.",
            "Atlas takes the same messy sentence typed or spoken, splits it into tasks and events, files each into the right space and project, and shows the whole set for review before saving."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Because Notion cannot subscribe to an ICS feed, there is no clean route for a Canvas class schedule to arrive. The usual fix is a student template, and the template is the tell: what gets handed over is a shape, and keeping it accurate is manual work.",
            "Atlas pulls course calendars, assignments and due dates through the Canvas feed directly. The courses selected become projects with their assignments already inside them, so a syllabus change shows up on the timeline instead of waiting for someone to retype it."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Notion wins on notes.",
          "body": [
            "This is Notion's home ground and the margin is wide. Linked databases, synced blocks, relations between pages and real collaborative editing make it the better place to write anything long or structured.",
            "Atlas has long-form notes built in, kept two-way with Google Docs over the narrow drive.file scope, so it only ever touches documents it created or that were explicitly picked. That is a clean setup for coursework, not an attempt to out-build Notion's editor."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Notion wins on platforms.",
          "body": [
            "Notion runs on macOS, Windows, iPhone, iPad, Android and the web, so a workspace is reachable from a library desktop, a borrowed laptop or a phone with equal ease. For anyone moving between operating systems in a normal week, that reach settles the question on its own.",
            "Atlas is Apple platforms only: a native Mac app plus native iPhone and iPad apps on the App Store. There is no Windows build and no web version. Someone whose school issues a Windows machine should read that as disqualifying."
          ]
        },
        {
          "title": "Price",
          "verdict": "It's a tie on price.",
          "body": [
            "Notion's free personal plan is genuinely generous for a single user. Paid plans start at $10 per user per month billed annually, which is where collaboration limits, longer version history and the fuller AI features live.",
            "Atlas is free, with no paid tier above it and no advertising. Neither app costs a solo student anything to start, so price should not decide this."
          ]
        }
      ],
      "bottom": [
        "Someone who likes building a system, works with other people, or needs the same workspace on Windows and the web should pick Notion. A student running a group project across three operating systems will be better served there.",
        "Atlas suits the person whose week is classes, deadlines and a life around them, on a Mac and an iPhone, who would rather have the structure arrive finished. One more distinction: Notion's AI can be connected to read Gmail, while Atlas never asks for access to email at all."
      ],
      "faq": [
        {
          "q": "Can Notion sync with Apple Calendar?",
          "a": "Not on its own. Notion's help pages state the main app does not natively show external calendar events, so Apple Calendar requires installing Notion Calendar as a second application. Atlas syncs Apple Calendar two ways inside the app itself."
        },
        {
          "q": "Can Notion import a Canvas calendar?",
          "a": "No. Notion cannot subscribe to an ICS feed, which is how Canvas publishes a class schedule, so students typically rebuild the semester by hand in a template. Atlas reads the Canvas feed and turns chosen courses into projects with their assignments included."
        },
        {
          "q": "Is Atlas free?",
          "a": "Yes. Atlas is free on Mac, iPhone and iPad, with no paid tier and no advertising. Notion has a free personal plan, and its paid plan runs $10 per user each month on annual billing."
        },
        {
          "q": "Which is better for students, Atlas or Notion?",
          "a": "Atlas, for a student on Apple hardware who wants a calendar and a course schedule working on day one. Notion is the better answer for group coursework, for anyone on Windows, and for anyone who wants to design their own system."
        }
      ]
    },
    "sources": [
      "https://www.notion.com/pricing",
      "https://www.notion.com/help/calendars",
      "https://www.notion.com/help/manage-your-calendars-and-events",
      "https://www.notion.com/help/notion-ai-connector-for-gmail",
      "https://apps.apple.com/us/app/notion-notes-tasks-ai/id1232780281"
    ]
  },
  {
    "id": "notion-calendar",
    "name": "Notion Calendar",
    "tagline": "Standalone calendar wired into Notion databases",
    "url": "https://www.notion.com/product/calendar",
    "cells": {
      "mac": "p",
      "mobile": "p",
      "apple2way": "y",
      "gcal2way": "y",
      "canvas": "n",
      "timeline": "y",
      "drag": "y",
      "capture": "p",
      "review": "n",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "Free"
    },
    "prose": {
      "dek": "Notion Calendar is one of the best calendars available and costs nothing, but it holds a schedule rather than a life.",
      "intro": [
        "Notion Calendar began as Cron, a keyboard-driven calendar with a devoted following, and Notion acquired it rather than rebuild it. It connects Apple, Google and Outlook accounts properly and two ways, moves faster under the keyboard than anything else here, and surfaces dated items from a Notion workspace on the grid. It is free.",
        "Atlas is a native macOS app that treats the calendar as one surface of a larger system: tasks on the same timeline, courses from Canvas, projects, notes. The trade-off is straightforward. Notion Calendar is the better calendar. Atlas is the better place to keep everything the calendar refers to."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Notion Calendar wins on calendars.",
          "body": [
            "Apple, Google and Outlook accounts all connect two ways, multiple accounts sit side by side cleanly, and the keyboard handling remains the fastest in the category. For a person who only needs every account on one grid, this is the sharper tool.",
            "Atlas syncs Apple Calendar and Google Calendar two ways onto a shared timeline with tasks, and dragging a task onto a slot schedules it. That covers the accounts most people carry, but on pure calendar craft Notion Calendar is ahead."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Notion Calendar has no capture layer of its own. Tasks exist only if they already live in a Notion database, so the front end is fast but the workspace behind it still has to be built and maintained separately. There is no voice input.",
            "Atlas accepts a messy sentence typed or spoken, breaks it into tasks and events, routes each to the right space and project, and presents the result for confirmation before saving."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Notion Calendar cannot subscribe to an ICS feed. Notion's documentation directs people to add the feed in Google Calendar and let it flow through from there, a workable detour but a strange gap in a product recommended to students.",
            "Atlas takes the Canvas feed as a first-class source. Course calendars, assignments and due dates come in, and the chosen courses become projects holding their own assignments, so a class is a place to work rather than a coloured band on a grid."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Notion Calendar has no writing surface. It can link out to Notion pages, useful if a workspace already exists, but the calendar itself is not somewhere to draft an essay outline or keep lecture notes.",
            "Atlas includes long-form notes and keeps them two-way with Google Docs through the narrow drive.file scope, touching only documents it created or that were explicitly selected. Notes attach to the same projects the assignments sit in."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "It's a tie on platforms.",
          "body": [
            "Notion Calendar covers macOS, Windows, iPhone and the web, so it survives a switch to a school-issued PC. It still has no iPad app, several years after the acquisition, which is a conspicuous absence for anyone who takes notes on a tablet in lecture.",
            "Atlas runs natively on Mac, iPhone and iPad, all available on the App Store, and nowhere else. No Windows, no web. Each product covers ground the other does not, so the right answer depends entirely on which devices actually appear in a given week."
          ]
        },
        {
          "title": "Price",
          "verdict": "It's a tie on price.",
          "body": [
            "Notion Calendar is free and does not gate calendar features behind a subscription, though the Notion workspace it draws items from may itself be a paid plan depending on how it is used.",
            "Atlas is free as well, with no upgrade tier and no advertising. Cost is not the deciding variable here; scope is."
          ]
        }
      ],
      "bottom": [
        "Anyone already living inside Notion who simply wants its calendar to be excellent should run Notion Calendar. It costs nothing, it handles three account types properly, and pairing it with an existing workspace is a sound setup that no comparison page should argue against.",
        "Atlas is the better choice for a student who does not want to build and maintain that workspace at all. Classes, assignments, tasks, notes and a capture bar that accepts speech are attached to the calendar from the first launch, on Mac, iPhone and iPad."
      ],
      "faq": [
        {
          "q": "Can Notion Calendar subscribe to an ICS feed?",
          "a": "No. Notion's documentation says to add the feed to Google Calendar and let it appear through that account instead. Atlas reads a Canvas feed directly, without routing it through a third-party calendar first."
        },
        {
          "q": "Is there a Notion Calendar iPad app?",
          "a": "No. Notion Calendar ships on macOS, Windows, iPhone and the web, but an iPad version has still not appeared since the Cron acquisition. Atlas has a native iPad app on the App Store."
        },
        {
          "q": "Is Atlas free?",
          "a": "Yes. Atlas costs nothing, has no paid tier and shows no advertising. Notion Calendar is also free, so the comparison comes down to what each app holds rather than what it charges."
        }
      ]
    },
    "sources": [
      "https://www.notion.com/product/calendar",
      "https://www.notion.com/help/manage-your-calendars-and-events",
      "https://www.notion.com/help/use-notion-calendar-with-notion",
      "https://www.notion.com/help/notion-calendar-apps",
      "https://apps.apple.com/us/app/notion-calendar/id1607562761"
    ]
  },
  {
    "id": "todoist",
    "name": "Todoist",
    "tagline": "Natural-language task manager with calendar time-blocking",
    "url": "https://www.todoist.com/",
    "cells": {
      "mac": "p",
      "mobile": "y",
      "apple2way": "p",
      "gcal2way": "y",
      "canvas": "n",
      "timeline": "y",
      "drag": "y",
      "capture": "y",
      "review": "y",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "$5/mo (annual)"
    },
    "prose": {
      "dek": "Todoist reads plain English better than anything else in the category, then stops at the edge of the calendar.",
      "intro": [
        "Todoist has been parsing natural language into tasks since long before the category had a name, and it still does it best. Typing “essay draft every Tuesday at 4 starting next week” simply works, and Ramble, its voice capture, turns spoken sentences into structured tasks for editing before saving.",
        "Atlas approaches the same week from the calendar side. Tasks and events share one timeline, Canvas courses arrive as projects, and notes live alongside both. The trade-off comes down to shape: Todoist is a task manager that learned to sit beside a calendar, and Atlas is a calendar that learned to hold everything a task refers to."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Todoist's well-known iCal feed points outward. It publishes tasks so other calendars can read them, but there is no way to subscribe to an incoming feed. Apple Calendar reaches Todoist only by routing iCloud through Google first, and the layout that allows dragging a task onto a time slot sits behind Pro.",
            "Atlas syncs Apple Calendar and Google Calendar two ways with no relay in between. Tasks and events share a single timeline by default, and dropping a task onto a slot gives it a time."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Todoist wins on capture.",
          "body": [
            "The parser is the reason people stay. Recurrence, relative dates, priorities and project routing all come out of one typed line, reliably, refined over years. Ramble extends the same accuracy to speech and shows the parsed result for editing before it is committed.",
            "Atlas handles a messy typed or spoken sentence, splits it into tasks and events, files them into the right space and project, and shows everything for review before saving. It routes to more places, but on raw parsing precision Todoist remains the sharper instrument."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "A Canvas class schedule cannot get into Todoist. The feed only travels outward, so every assignment becomes something typed by hand, and a shifted due date becomes an edit nobody remembers to make.",
            "Atlas reads course calendars, assignments and due dates from the Canvas feed. Selected courses become projects with their assignments inside, which puts a deadline and the work it belongs to in the same place."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Todoist has task descriptions and comments and nothing beyond them. There is no document, no outline, nowhere to draft. A reading response or a set of lecture notes has to live in another application entirely.",
            "Atlas has long-form notes built in, kept two-way with Google Docs over the narrow drive.file scope so it only ever touches documents it created or that were chosen explicitly. A note can sit in the same project as the assignment it belongs to."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Todoist wins on platforms.",
          "body": [
            "Todoist runs on macOS, Windows, iPhone, iPad, Android, the web and a long tail of integrations besides. The same list appears identically on a work PC and a phone of any make, which matters for shared projects and mixed hardware.",
            "Atlas is Apple only: native Mac, iPhone and iPad apps from the App Store, with no Windows build and no web version. That is a real limitation, and for a mixed-device household it ends the conversation."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Todoist's free plan is usable, but the calendar layout that makes time-blocking possible requires Pro, at $5 per month billed annually. The calendar view is the feature most relevant to this comparison, and it is the one behind the paywall.",
            "Atlas is free, including the calendar, the Canvas feed, the notes and the capture bar. Nothing in it is reserved for a higher tier."
          ]
        }
      ],
      "bottom": [
        "Someone whose week genuinely is a list should pick Todoist, especially across Windows, Android and the web, or when tasks are shared with other people. A graduate student coordinating a lab rota on mixed hardware will get more from Todoist Pro than from any Apple-only app.",
        "Atlas fits the student whose deadlines attach to classes, whose classes attach to documents, and whose devices all carry an Apple logo. Getting a Canvas schedule and a calendar onto one timeline, at no cost, is the specific job it was built for."
      ],
      "faq": [
        {
          "q": "Can Todoist import a Canvas calendar?",
          "a": "No. Todoist's iCal feed publishes tasks outward and cannot subscribe to an incoming feed, so a Canvas schedule has to be retyped. Atlas ingests the Canvas feed and turns selected courses into projects with their assignments."
        },
        {
          "q": "Does Todoist sync with Apple Calendar?",
          "a": "Only indirectly. Reaching Todoist from iCloud means routing the calendar through Google first, which adds a hop and a point of failure. Atlas syncs Apple Calendar two ways with no intermediary."
        },
        {
          "q": "Is Todoist's calendar view free?",
          "a": "No. Time-blocking in the calendar layout requires Todoist Pro, which is $5 per month on annual billing. In Atlas the calendar, along with everything else in the app, costs nothing."
        }
      ]
    },
    "sources": [
      "https://www.todoist.com/pricing",
      "https://www.todoist.com/help/articles/todoist-pro-plan-pricing-update-bxBvHZuJZ",
      "https://www.todoist.com/help/articles/use-the-calendar-integration-rCqwLCt3G",
      "https://www.todoist.com/help/articles/dictate-to-add-tasks-with-ramble-P1Raq7vVF",
      "https://www.todoist.com/help/articles/time-blocking-in-todoist-d6Pf1uTpc"
    ]
  },
  {
    "id": "things3",
    "name": "Things 3",
    "tagline": "Apple-only task manager with areas",
    "url": "https://culturedcode.com/things/",
    "cells": {
      "mac": "y",
      "mobile": "y",
      "apple2way": "p",
      "gcal2way": "n",
      "canvas": "n",
      "timeline": "p",
      "drag": "n",
      "capture": "y",
      "review": "p",
      "areas": "y",
      "gdocs": "n",
      "windows": "n",
      "teams": "n",
      "price": "one-time $49.99 Mac"
    },
    "prose": {
      "dek": "Things 3 is the most refined task app on the Mac, and Atlas is the one that also owns the calendar those tasks land on.",
      "intro": [
        "Things 3 is Cultured Code's task manager for Mac, iPhone and iPad. It organises work into Areas and Projects, it is genuinely native on every Apple platform it ships to, and it is bought once rather than rented. It has been refined for more than a decade and still receives updates in 2026. Nothing about the app feels careless.",
        "Atlas is a free native macOS app, with iPhone and iPad apps on the App Store, built around one timeline where tasks and calendar events sit together. The trade-off is straightforward. Things 3 is the better-made list. Atlas is the app that can write to a calendar, pull a Canvas course in on its own, and hold the notes that go with it."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Cultured Code's support documentation is explicit: Things communicates with Apple Calendar in one direction only. Events are displayed beside to-dos in Today and Upcoming, and nothing is ever written back. Google Calendar has to be routed through Apple Calendar first, there is no ICS subscription, and because Things has no calendar surface, a task cannot be dropped onto Thursday afternoon.",
            "Atlas keeps two-way sync with both Apple Calendar and Google Calendar, so an edit made in Atlas appears in the other app and the reverse holds. Tasks and calendar events share a single timeline, and dragging a task onto the calendar is how it gets a time."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Things reads dates out of typed text well, which handles one to-do at a time. Atlas is built for the sentence people actually think in. Type or speak “essay due Thursday, gym three times this week, call mom Sunday” and Atlas splits it into separate tasks and events, files each one into the right space and project, and puts the whole set on screen for review and confirmation before anything is saved."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Things has no connection to a learning management system. Coursework is typed in by hand and kept current by hand, which is fine in September and less fine in week nine.",
            "Atlas reads Canvas directly. Course calendars, assignments and due dates arrive through the Canvas feed, and the courses chosen become projects with their assignments inside them. Areas and Projects in Things are a capable manual approximation of that structure, and Atlas borrowed the idea for Spaces, but the filling-in is still manual."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "A note in Things is a field attached to a to-do or a project: useful for a line of context, not for a draft. Atlas has long-form notes built in, kept beside the projects they belong to and synced two-way with Google Docs over the narrow drive.file scope, so Atlas only ever touches documents it created or that the user picked. Atlas never asks for access to email."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "It's a tie on platforms.",
          "body": [
            "Both apps are Apple-only. Things ships native Mac, iPhone and iPad apps; Atlas ships a native macOS app alongside iPhone and iPad apps on the App Store. Neither has a Windows client and neither has a web version. For a student whose main machine runs Windows, both are the wrong answer, and that limitation deserves stating flatly rather than burying."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Things 3 has no free tier at all. The Mac app is $49.99, iPhone and iPad are sold separately, and owning the set runs to roughly eighty dollars. Spread across four years that can undercut any subscription in the category, which is a fair argument in its favour. Atlas is free on every platform it runs on, and calendar sync, Canvas and notes are not gated behind a plan."
          ]
        }
      ],
      "bottom": [
        "Someone who wants the nicest task app on the Mac, who is content keeping the calendar in a separate window, and who would rather pay once than subscribe, should buy Things 3. It is a better-crafted list than anything else in this category, and the people who have loved it for a decade are right about it.",
        "Atlas is the better pick for someone running a semester plus the rest of life on a Mac: Canvas courses arriving without data entry, Apple and Google calendar edits travelling in both directions, notes sitting next to the project they describe, and a task becoming a block of time by being dragged onto one."
      ],
      "faq": [
        {
          "q": "Can Things 3 sync with Google Calendar?",
          "a": "No. Things reads from Apple Calendar only, and reads in one direction, so Google events must be routed into Apple Calendar first and still cannot be edited from Things. Atlas syncs two-way with both Apple Calendar and Google Calendar."
        },
        {
          "q": "Can Things 3 import a Canvas calendar?",
          "a": "No. Things has no ICS subscription and no Canvas integration, so assignments have to be entered manually. Atlas brings course calendars, assignments and due dates in through the Canvas feed and turns the courses selected into projects."
        },
        {
          "q": "Is Atlas free?",
          "a": "Yes. Atlas is free on Mac, iPhone and iPad, with no paid tier holding back calendar sync or Canvas. Things 3 has no free tier and costs about eighty dollars to own across all three devices."
        },
        {
          "q": "Which is better for students, Atlas or Things 3?",
          "a": "Atlas, for most students on a Mac, because coursework arrives from Canvas and an assignment can be dragged onto the calendar as a study block. Things 3 is the better choice for a student who wants the finest list app on the platform and is happy running a separate calendar beside it."
        }
      ]
    },
    "sources": [
      "https://culturedcode.com/things/support/articles/2803583/",
      "https://culturedcode.com/things/support/articles/2803561/",
      "https://culturedcode.com/things/support/articles/9780167/",
      "https://apps.apple.com/us/app/things-3/id904280696",
      "https://apps.apple.com/us/app/things-3-for-ipad/id904244226"
    ]
  },
  {
    "id": "ticktick",
    "name": "TickTick",
    "tagline": "To-do list, calendar, and habit tracker",
    "url": "https://ticktick.com/",
    "cells": {
      "mac": "p",
      "mobile": "y",
      "apple2way": "y",
      "gcal2way": "y",
      "canvas": "p",
      "timeline": "y",
      "drag": "y",
      "capture": "y",
      "review": "p",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "$4.17/mo (annual)"
    },
    "prose": {
      "dek": "TickTick is the closest thing to Atlas on any platform, and the choice comes down to school structure, notes and which computer is on the desk.",
      "intro": [
        "TickTick is a to-do list, calendar and habit tracker that has been shipping for a decade across Mac, Windows, iPhone, Android, iPad and the web. It syncs two-way with Google Calendar, Apple Calendar and Outlook, subscribes to any ICS feed pasted into it, parses typed and spoken input into dated tasks, and costs $4.17 a month on the annual plan.",
        "Atlas is a free native macOS app with iPhone and iPad apps, organised into Spaces with Projects inside them, wired directly to Canvas, and keeping long-form notes two-way with Google Docs. The trade-off is narrow and real: TickTick reaches more devices and covers more ground per dollar, while Atlas is shaped around a semester."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "TickTick wins on calendars.",
          "body": [
            "TickTick handles more account types than Atlas does. It syncs two-way with Google Calendar and, unusually for a task app, with Apple Calendar as well; it supports Outlook; and it subscribes to an arbitrary ICS feed. Tasks and events share one timeline and a task can be dragged onto a slot.",
            "Atlas matches the two-way sync with Apple Calendar and Google Calendar and the single timeline with drag-to-schedule, but has no Outlook account type and no generic ICS subscription. On breadth of calendar accounts, TickTick is ahead."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "TickTick's voice capture with AI parsing pulls a date, a list and a priority out of a spoken line, and it shows what it extracted before committing. That is good work on a single item.",
            "Atlas takes the messier version of the same input. One sentence describing several unrelated things becomes several tasks and events at once, each filed into the space and project it belongs to, with the entire set shown for review and confirmation before it is saved."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "TickTick's Canvas story is a generic feed subscription. Assignments arrive as calendar entries with no course behind them and nothing to attach work to. Its hierarchy is lists, folders and tags under one account, with no top-level partition, so school and personal share a drawer and are told apart by labels.",
            "Atlas reads the Canvas feed as coursework. Course calendars, assignments and due dates come in, and the courses chosen become projects with their assignments inside them, held in a School space that stays separate from Personal at the top level."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "TickTick describes its own notes as minimalistic, and nothing in them syncs to Google Docs. Atlas has long-form notes built in, sitting next to the projects they belong to and kept two-way with Google Docs over the narrow drive.file scope, so Atlas only touches documents it created or that the user picked. It never asks for access to email."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "TickTick wins on platforms.",
          "body": [
            "TickTick runs on Windows, Android and the web in addition to Mac, iPhone and iPad, and it adds habit tracking and shared lists that Atlas does not have. Atlas is Apple platforms only: no Windows client, no web version. Anyone carrying a Windows laptop or an Android phone should stop here and pick TickTick.",
            "The counterweight is narrow. TickTick's Mac app is a cross-platform build, while Atlas is written for macOS and nothing else, which shows up in small ways over the course of a day."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "TickTick has a genuinely usable free tier, and the paid plan is $4.17 a month billed annually, which is where calendar sync and the AI capture live. Over four years of school that is around two hundred dollars. Atlas is free, with no plan gating calendar sync, Canvas, capture or notes, and no ads."
          ]
        }
      ],
      "bottom": [
        "TickTick is the right answer for anyone who is not all-Apple, who wants habit tracking sitting alongside the list, or who puts weight on ten years of shipping and a deep support library. On a Windows laptop or an Android phone the comparison is over before it starts.",
        "Atlas suits the Mac-and-iPhone student who wants school treated as a real structure rather than a folder of labels: Canvas courses as projects, notes that round-trip to Google Docs, and one timeline where a task turns into a scheduled block by being dragged onto it."
      ],
      "faq": [
        {
          "q": "Does TickTick sync two-way with Google Calendar?",
          "a": "Yes. Two-way Google Calendar sync is part of the paid plan, and TickTick also syncs two-way with Apple Calendar and supports Outlook. Atlas syncs two-way with Apple Calendar and Google Calendar but has no Outlook account type."
        },
        {
          "q": "Can TickTick import a Canvas calendar?",
          "a": "Yes, by subscribing to the Canvas ICS feed, which is unusual for a task app. The assignments land as calendar entries rather than as coursework; Atlas reads the Canvas feed and turns the courses chosen into projects with their assignments inside."
        },
        {
          "q": "Is Atlas free?",
          "a": "Yes. Atlas is free on Mac, iPhone and iPad, and nothing central is held behind a subscription. TickTick's free tier is real, but calendar sync and AI capture require the $4.17-a-month annual plan."
        },
        {
          "q": "Which is better for students, Atlas or TickTick?",
          "a": "Atlas, for a student on Apple hardware, because Canvas courses become projects and school stays partitioned from personal life. TickTick is the better answer for a student on a Windows or Android device, or one who wants habit tracking in the same app."
        }
      ]
    },
    "sources": [
      "https://ticktick.com/upgrade",
      "https://help.ticktick.com/articles/7055781593733922816",
      "https://help.ticktick.com/articles/7209387325833347072",
      "https://help.ticktick.com/articles/7358389904469917696",
      "https://help.ticktick.com/articles/7444677039392555008"
    ]
  },
  {
    "id": "fantastical",
    "name": "Fantastical",
    "tagline": "Calendar app with tasks and scheduling",
    "url": "https://flexibits.com/fantastical",
    "cells": {
      "mac": "y",
      "mobile": "y",
      "apple2way": "y",
      "gcal2way": "y",
      "canvas": "p",
      "timeline": "y",
      "drag": "p",
      "capture": "y",
      "review": "p",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "p",
      "price": "$4.75/mo (annual)"
    },
    "prose": {
      "dek": "Fantastical is the best calendar on the Mac, and Atlas is the app that also owns the tasks, courses and notes attached to those events.",
      "intro": [
        "Fantastical is Flexibits' calendar app, fifteen years old and native on Mac, iPhone and iPad, with a Windows client since 2024. It connects to every account type that matters, including Apple, Google, Outlook and any ICS feed pasted into it, and its natural-language event parser is still the one every other app is measured against. The annual plan works out to $4.75 a month.",
        "Atlas is a free native macOS app with iPhone and iPad apps, built so that a task, an event, a course and a note are pieces of the same system on one timeline. The trade-off is easy to state: Fantastical is the better calendar by a distance, and it stays a calendar."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Fantastical wins on calendars.",
          "body": [
            "Fantastical supports more account types, has the more mature week view, and offers scheduling links for booking time with other people. Its parser handles edge cases that younger parsers miss, and a Canvas ICS feed pastes straight in and renders as events. Fifteen years of work is visible in the details.",
            "Atlas syncs two-way with Apple Calendar and Google Calendar and puts tasks on the same grid as events, which covers the common week. On calendar craft alone, Fantastical has been ahead for years and remains so."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Fantastical's parser is excellent at turning one line into one event, and that is what it is designed to do. Atlas is built for the paragraph. “Essay due Thursday, gym three times this week, call mom Sunday” becomes several tasks and several events at once, each routed to the right space and project, with the full set shown for review before anything is saved. Speaking it behaves the same way as typing it."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "A Canvas feed in Fantastical produces events on a grid. There is no course, no assignment that belongs to anything, and nowhere for the work itself to live. Calendar Sets can switch context between school and personal, but they filter which calendars are visible rather than owning any content.",
            "Atlas ingests the Canvas feed as coursework: the courses chosen become projects with their assignments inside them, so an assignment carries its class, its notes and the time blocked out to do it."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Fantastical has nowhere to write anything down, which is a deliberate scope decision rather than an oversight. Atlas keeps long-form notes beside the projects they belong to and syncs them two-way with Google Docs through the narrow drive.file scope, touching only documents it created or that the user picked. Atlas never asks for access to email."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Fantastical wins on platforms.",
          "body": [
            "Fantastical is native on Mac, iPhone and iPad and has shipped a Windows client since 2024, so a household with mixed machines is covered. Atlas runs on Apple platforms only, with no Windows version and no web version. For a student whose lab or work computer runs Windows, that is a real limitation and worth knowing before installing anything."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Fantastical has a free tier, but the features people actually subscribe for sit behind Flexibits Premium at $4.75 a month on the annual plan. The frequent recommendation of Fantastical plus a separate task app is a genuinely good setup, and it is also two subscriptions and two places to look. Atlas is free, and calendar sync, Canvas, capture and notes are not behind a plan."
          ]
        }
      ],
      "bottom": [
        "Someone whose week is meetings and appointments, who wants the finest calendar on the Mac, and who already has a task manager they are happy with, should choose Fantastical and keep that task app beside it. It is a good arrangement and plenty of people should not change it.",
        "Atlas suits the person tired of checking two apps to answer one question. The class, the assignment, the note and the block of time set aside for it are one object, kept in sync with Apple Calendar and Google Calendar on a Mac and an iPhone, at no cost."
      ],
      "faq": [
        {
          "q": "Does Fantastical have tasks?",
          "a": "Sort of. Fantastical displays Apple Reminders, Google Tasks or Todoist items next to events, but it does not own them and cannot organise them into projects. Atlas owns tasks outright and puts them on the same timeline as calendar events."
        },
        {
          "q": "Can Fantastical import a Canvas calendar?",
          "a": "Yes, as an ICS subscription, so Canvas due dates appear as events. They stay events, with no course or project behind them. Atlas reads the Canvas feed and turns the courses selected into projects with their assignments inside."
        },
        {
          "q": "Is Atlas free?",
          "a": "Yes. Atlas is free on Mac, iPhone and iPad. Fantastical offers a free tier, but the calendar features most people want require Flexibits Premium at $4.75 a month on the annual plan."
        },
        {
          "q": "Which is better for students, Atlas or Fantastical?",
          "a": "Atlas, for a student on Apple hardware, because Canvas courses become projects, notes live with the coursework, and assignments can be dragged onto the calendar. Fantastical is the better pick for a student whose week is mostly appointments and who already keeps tasks somewhere else."
        }
      ]
    },
    "sources": [
      "https://flexibits.com/fantastical",
      "https://flexibits.com/pricing",
      "https://apps.apple.com/us/app/fantastical-calendar/id718043190",
      "https://flexibits.com/fantastical/help/adding-events-and-tasks",
      "https://flexibits.com/blog/2024/10/fantastical-for-windows-is-finally-here/"
    ]
  },
  {
    "id": "apple-stock",
    "name": "Apple Calendar + Reminders",
    "tagline": "Stock Apple calendar and reminders apps",
    "url": "https://support.apple.com/guide/calendar/welcome/mac",
    "cells": {
      "mac": "y",
      "mobile": "y",
      "apple2way": "y",
      "gcal2way": "y",
      "canvas": "p",
      "timeline": "y",
      "drag": "p",
      "capture": "y",
      "review": "p",
      "areas": "p",
      "gdocs": "n",
      "windows": "p",
      "teams": "y",
      "price": "Free (with your device)"
    },
    "prose": {
      "dek": "Apple Calendar and Reminders cost nothing and sync everywhere; Atlas closes the seam between them and adds Canvas, projects and long-form notes.",
      "intro": [
        "Apple Calendar and Reminders ship on every Mac, iPhone and iPad. Calendar takes every account type worth naming, including iCloud, Google, Outlook, Exchange and any ICS subscription. Reminders handles lists, groups and due dates, dated reminders now surface in Calendar’s own timeline, and Siri will take a task by voice. Nothing to install, nothing to pay.",
        "The trade-off is that they stay two apps. The list and the schedule are two separate thoughts, Reminders knows about lists but not about a Comp Sci course, and there is nowhere to write more than a line, so notes end up in a third place. Atlas is the argument that those seams cost more over a semester than they appear to cost on a quiet Tuesday."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "It’s a tie on calendars.",
          "body": [
            "Apple Calendar has the broader account list. Outlook and Exchange are first-class, ICS subscriptions take a URL and a click, and calendar sharing between people works the way it has for years.",
            "Atlas syncs two ways with Apple Calendar and two ways with Google Calendar, then puts tasks on the same grid as the events. Drag a task onto Thursday afternoon and it has a time. That single timeline is the difference, not the number of account types."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Siri and the Reminders quick-entry field are good at one item. A sentence like “essay due Thursday, gym three times this week, call mom Sunday” becomes five separate trips through the interface, some to Reminders and some to Calendar, each typed by hand.",
            "Atlas takes that sentence typed or spoken, splits it into tasks and events, files each one into the right space and project, then shows the whole batch for review before anything is saved."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Canvas can be subscribed to in Apple Calendar, and it arrives as a wall of due-date events with nothing attached to them. Reminders has lists and groups, but no concept of a course, so the structure of a semester has to be rebuilt by hand every term.",
            "In Atlas the Canvas feed brings course calendars, assignments and due dates, and the courses selected become projects with their assignments already inside them. Spaces keep School and Personal apart without keeping them in different apps."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Neither Calendar nor Reminders holds more than a line of text, so lecture notes and essay drafts go somewhere else and lose their connection to the assignment they belong to.",
            "Atlas has long-form notes built in, attached to the project they concern, and kept two-way with Google Docs over the narrow drive.file scope, so it only ever touches documents it created or that were handed to it. Atlas never asks for access to email."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Apple Calendar and Reminders win on platforms.",
          "body": [
            "They are already there. No download, no account, no migration, and iCloud.com gives a serviceable browser view from a machine that is not yours.",
            "Atlas is Apple platforms only: a native Mac app plus native iPhone and iPad apps on the App Store. No Windows version, no web version. For anyone who has to touch a school lab PC, that is a genuine reason to stay put."
          ]
        },
        {
          "title": "Price",
          "verdict": "It’s a tie on price.",
          "body": [
            "Apple Calendar and Reminders come with the hardware. Atlas is free. Neither carries ads or charges per device."
          ]
        }
      ],
      "bottom": [
        "Someone whose week is a few recurring commitments, a grocery list and the occasional dentist appointment should keep the two apps already on the machine. They cost nothing, they sync to every device without being asked, and adding software there solves a problem that does not exist. The same goes for anyone who spends part of the week on Windows.",
        "Atlas is the better pick when the week has a shape: four courses, eleven assignments, a job, and a personal life colliding with all of it. One timeline holding Apple, Google and Canvas, one sentence becoming five items, and notes that live where the work does."
      ],
      "faq": [
        {
          "q": "Can Apple Reminders import a Canvas calendar?",
          "a": "No. Canvas publishes an ICS feed, which Apple Calendar can subscribe to, but it arrives as plain due-date events and Reminders is not involved at all. Atlas reads the same feed and turns the chosen courses into projects with their assignments inside."
        },
        {
          "q": "Is Atlas free?",
          "a": "Yes, free on Mac, iPhone and iPad, with no ads and no paid tier. There is no trial to run out."
        },
        {
          "q": "Which is better for students, Atlas or Apple Calendar and Reminders?",
          "a": "Atlas, for a student carrying a full course load, because Canvas courses become projects and tasks share a timeline with classes. A student with a light schedule and a short list will be fine with the stock apps."
        }
      ]
    },
    "sources": [
      "https://support.apple.com/guide/calendar/welcome/mac",
      "https://support.apple.com/guide/calendar/subscribe-to-calendars-icl1022/mac",
      "https://support.apple.com/guide/calendar/use-reminders-icl873b9a527/mac",
      "https://support.apple.com/guide/reminders/create-reminders-in-calendar-remn2ff3b312/mac",
      "https://support.apple.com/guide/calendar/add-modify-or-delete-events-icalwr13-events/mac"
    ]
  },
  {
    "id": "google-stock",
    "name": "Google Calendar + Tasks",
    "tagline": "Google’s calendar and task apps",
    "url": "https://calendar.google.com",
    "cells": {
      "mac": "n",
      "mobile": "y",
      "apple2way": "p",
      "gcal2way": "y",
      "canvas": "p",
      "timeline": "y",
      "drag": "p",
      "capture": "p",
      "review": "n",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "Free (personal account)"
    },
    "prose": {
      "dek": "Google Calendar is the schedule everything else syncs to; Atlas gives it a native Mac home, Canvas courses and a review step before anything is saved.",
      "intro": [
        "Google Calendar is free, runs on essentially every device with a screen, and is the calendar the rest of this comparison treats as the source of truth. Google Tasks with a date sits on the grid beside events, sharing works well enough to run a household or a club, and for anyone already living inside Gmail and Drive it is a difficult default to argue with.",
        "Two things matter on a Mac. There is no Mac app, so the calendar is a browser tab or a third-party wrapper, which is a daily difference rather than a footnote. And Apple calendars cannot be added as an account at all: the only route is publishing an iCloud calendar and subscribing to the public link, one way and read-only."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "It’s a tie on calendars.",
          "body": [
            "As a calendar, Google is the standard. Twenty years of reliability, invitations everyone can accept, shared calendars, working hours, and an ICS subscription field that takes any feed handed to it.",
            "Where it stops is Apple. An iCloud calendar can only be published and subscribed to, meaning one direction and no edits. Atlas syncs two ways with both Google Calendar and Apple Calendar, and keeps tasks on the same timeline as events, so a task dragged onto Friday morning becomes a real block of time."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Google’s quick-add parses a line at a time, and Tasks is a separate surface with its own field. The larger point is what happens unprompted: Google’s help pages state that when Gmail finds a date in a message, an event may be added to the calendar automatically, on by default outside the EEA, the UK, Switzerland and Japan, with no approval step.",
            "Atlas takes a whole messy sentence, typed or spoken, splits it into tasks and events, files each into the right space and project, and shows everything for confirmation before saving. Atlas never asks for access to email."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "A Canvas feed can be subscribed to in Google Calendar, where it behaves like any other ICS subscription: a column of due dates with no assignment behind them and no way to group them by course.",
            "Atlas pulls course calendars, assignments and due dates through the Canvas feed, and the courses selected become projects holding their own assignments. Spaces keep School separate from Personal inside one app rather than across four."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Google Tasks offers a short details field and nothing more. Real writing goes to Google Docs, which is excellent and completely disconnected from the assignment and the due date it exists to serve.",
            "Atlas has long-form notes built in and attached to the project, kept two-way with Google Docs over the narrow drive.file scope, so it touches only documents it created or that were explicitly picked."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Google Calendar and Tasks win on platforms.",
          "body": [
            "Google runs everywhere: Windows, Android, ChromeOS, any browser on a borrowed machine, plus native iPhone and iPad apps. Nothing here matches that reach.",
            "Atlas is Apple platforms only, with a native Mac app and native iPhone and iPad apps. No Windows, no web. Anyone splitting a week between a MacBook and a Windows desktop should weigh that first."
          ]
        },
        {
          "title": "Price",
          "verdict": "It’s a tie on price.",
          "body": [
            "Google Calendar and Tasks are free on a personal account, with no ads in the calendar itself. Atlas is free on all three of its platforms."
          ]
        }
      ],
      "bottom": [
        "Google Calendar and Tasks are the right answer for anyone whose life is already Google-shaped: Workspace at school or at work, a shared family calendar, an Android phone, or a Windows machine in the mix. Universal invitations and twenty years of stability are worth more than any feature list, and Atlas syncs to that calendar rather than asking anyone to leave it.",
        "Atlas is the better pick for a Mac user who wants that same Google calendar in a native window, alongside Apple calendars that sync both ways, Canvas courses that arrive as projects, tasks on the same timeline, and a capture bar that waits for approval before writing anything down."
      ],
      "faq": [
        {
          "q": "Is there a Google Calendar app for Mac?",
          "a": "No. Google Calendar on a Mac is a browser tab or a third-party wrapper around that tab. Atlas is a native Mac app that syncs two ways with the same Google account."
        },
        {
          "q": "Can Google Calendar sync with Apple Calendar?",
          "a": "Not as an account. An iCloud calendar has to be published and then subscribed to by its public link, which is one-way and read-only. Atlas syncs two ways with Apple Calendar and Google Calendar at once."
        },
        {
          "q": "Does Atlas read my email?",
          "a": "No. Atlas never asks for a mail scope of any kind. Google Calendar, by contrast, may add events found in Gmail messages automatically in most regions."
        }
      ]
    },
    "sources": [
      "https://support.google.com/calendar/answer/9901136",
      "https://support.google.com/calendar/answer/6084018",
      "https://support.google.com/calendar/answer/37100",
      "https://support.google.com/calendar/answer/72143",
      "https://support.google.com/gemini/answer/15305236"
    ]
  },
  {
    "id": "structured",
    "name": "Structured",
    "tagline": "Daily planner with a visual timeline",
    "url": "https://structured.app",
    "cells": {
      "mac": "y",
      "mobile": "y",
      "apple2way": "p",
      "gcal2way": "n",
      "canvas": "p",
      "timeline": "y",
      "drag": "y",
      "capture": "y",
      "review": "y",
      "areas": "n",
      "gdocs": "n",
      "windows": "y",
      "teams": "n",
      "price": "$2.50/mo (annual)"
    },
    "prose": {
      "dek": "Structured owns the single-day timeline; Atlas writes back to the calendar and holds the courses, projects and notes a day view has no room for.",
      "intro": [
        "Structured presents the day as one vertical timeline, mixing calendar events and tasks into a single readable column. It is a real Mac app rather than a web page in a window, it also runs on iPhone and iPad, and at roughly thirty dollars a year it is priced like a tool. Its AI capture accepts typed or spoken input and will replan the day on request.",
        "The design is deliberately narrow: Structured is a day, not a system. That focus is exactly what makes it good, and it is also where it runs out. Calendar sync goes one direction, and there are no projects or areas to hold a semester’s worth of work."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Structured’s own help pages state the limit plainly: calendar synchronisation is one-way. Google, Apple and Outlook events flow in, and nothing done inside Structured flows back out. Move a block to the afternoon and the calendar everyone else can see still shows the morning.",
            "Atlas syncs two ways with Apple Calendar and Google Calendar. A task dragged onto Wednesday at four becomes an event a roommate or a group partner can actually see."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Structured wins on capture.",
          "body": [
            "Structured’s AI takes typed or spoken input, will rearrange the whole day when asked, and presents each suggestion as something to accept or dismiss rather than acting unilaterally. Automatic replanning of an over-full day is a real capability, and Atlas does not do it.",
            "Atlas capture is strong in a different direction: a messy sentence becomes tasks and events, each filed into the right space and project, with the whole set shown for review before saving. It sorts the input; Structured rearranges the day."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Structured has no ICS field of its own, so a Canvas feed has to be subscribed to in another calendar app first and inherited from there. What arrives is a set of dated events, with no assignment and no course behind them.",
            "Atlas reads the Canvas feed directly for course calendars, assignments and due dates, and the courses chosen become projects with their assignments inside."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Structured allows a note on an item and stops there. Its own five-year retrospective names projects among the things the app does not have, and long-form writing is outside its remit by design.",
            "Atlas has long-form notes built in, attached to projects and kept two-way with Google Docs over the narrow drive.file scope, touching only documents it created or picked deliberately. Spaces sit above projects, so School and Personal stay distinct."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Structured wins on platforms.",
          "body": [
            "Structured runs natively on Mac, iPhone and iPad, and reaches past Apple hardware as well, so the day is available from a machine that is not a Mac.",
            "Atlas is Apple platforms only: native on Mac, iPhone and iPad, with no Windows version and no web version. That is a flat limitation and worth settling before anything else."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Structured asks about $2.50 a month billed annually for its full feature set, which is a fair price for what it does. Atlas is free on Mac, iPhone and iPad, with no ads and nothing gated behind a tier."
          ]
        }
      ],
      "bottom": [
        "Structured is the right answer for someone whose calendar already lives somewhere trusted and who wants one beautiful, legible day laid on top of it. A professional with a fixed work calendar, or anyone whose real question is “what am I doing in the next six hours,” will get more out of that focus than out of a system with rooms to fill.",
        "Atlas is the better pick when the day is not the whole problem. Two-way sync means the schedule changes when the plan changes, Canvas courses arrive as projects rather than as loose due dates, notes belong to the work they describe, and none of it costs anything."
      ],
      "faq": [
        {
          "q": "Does Structured sync both ways with Google Calendar?",
          "a": "No. Structured’s help pages state that calendar sync is one direction only: events come in, and changes made in Structured do not go back out. Atlas syncs two ways with both Google Calendar and Apple Calendar."
        },
        {
          "q": "Can Structured import a Canvas calendar?",
          "a": "Only indirectly. Structured has no ICS subscription field, so the Canvas feed must be added to another calendar app and inherited from there as plain events. Atlas reads the Canvas feed directly and turns chosen courses into projects."
        },
        {
          "q": "Which is better for students, Atlas or Structured?",
          "a": "Atlas, because a semester needs projects, courses and notes, and Structured is built to hold a single day. A student with a light load who only wants today in order will enjoy Structured more."
        }
      ]
    },
    "sources": [
      "https://help.structured.app/en/articles/324674",
      "https://help.structured.app/en/articles/1897986",
      "https://help.structured.app/en/articles/324738",
      "https://help.structured.app/en/articles/338562",
      "https://structured.app/blog/structuredfive"
    ]
  },
  {
    "id": "motion",
    "name": "Motion",
    "tagline": "AI work manager that auto-schedules tasks",
    "url": "https://www.usemotion.com",
    "cells": {
      "mac": "p",
      "mobile": "p",
      "apple2way": "p",
      "gcal2way": "y",
      "canvas": "n",
      "timeline": "y",
      "drag": "y",
      "capture": "p",
      "review": "p",
      "areas": "y",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "$12.73/mo (annual)"
    },
    "prose": {
      "dek": "Motion decides when the work happens. Atlas leaves that call to the person holding the calendar, and writes back to Apple Calendar.",
      "intro": [
        "Motion is an AI work manager built on one premise: nobody should have to decide when to do things. Tasks go in with a deadline and a duration, and Motion arranges the calendar around them, re-planning through the day as meetings run long and blocks slip. For a professional facing competing deadlines, that engine is the product, and it is a serious one.",
        "Atlas takes the opposite position. It reads a messy sentence, splits it into tasks and events, files them into the right space and project, and then stops and waits for confirmation. Scheduling stays a human decision made by dragging a task onto an hour. The trade-off is plain: Motion is faster at filling a calendar, Atlas is clearer about why the calendar says what it says."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Motion's own documentation states that iCloud support is read-only: it can display an Apple calendar and can never write an event back to it. For someone whose life already lives in Apple Calendar, that means every block Motion creates lands somewhere else, and the two views drift apart. Google and Outlook get full two-way treatment.",
            "Atlas syncs Apple Calendar and Google Calendar in both directions, and every event carries the source it actually came from. Tasks and events share a single timeline, so a due date and a class meeting compete for the same hour on screen."
          ]
        },
        {
          "title": "Capture",
          "verdict": "It's a tie on capture.",
          "body": [
            "Motion's strength is what happens after capture. Give it a task with a deadline and an estimate and the auto-scheduler places it, then keeps placing it as the day moves. That is the single feature people buy Motion for.",
            "Atlas invests the same effort one step upstream. Type or speak something unstructured, and it comes back split into tasks and events, sorted into spaces and projects, staged for review before anything is saved. Motion optimises for never planning; Atlas for never wondering what happened to Thursday."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Motion has no Canvas integration and no calendar subscription field to improvise one with, so a course schedule has no route in short of retyping it. Assignments become ordinary tasks with manually entered dates, and the semester has to be maintained by hand.",
            "Atlas pulls course calendars, assignments and due dates through the Canvas feed. The courses selected during setup become projects with their assignments already inside them, so the term arrives structured rather than transcribed."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Motion carries notes and documents, which is more than most task managers offer, but they stay inside Motion. There is no Google Docs relationship, so a draft written for a seminar has to be copied out to be shared or handed in.",
            "Atlas keeps long-form notes in the app and holds them two-way with Google Docs over the narrow drive.file scope, touching only documents it created or ones explicitly picked. Motion's AI email product, by contrast, connects to Gmail and Outlook and drafts replies from an inbox. Atlas never asks for access to email."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Motion wins on platforms.",
          "body": [
            "Motion runs on Windows, in the browser and on iPhone, so a team spread across operating systems can all use it. Its App Store listing shows no dedicated iPad app, but the web version covers most of that gap.",
            "Atlas is native macOS, iPhone and iPad only. There is no Windows build and no web version, and for anyone who touches a PC during the day that is disqualifying."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Motion has no free tier. At roughly $12.73 a month billed annually it comes to about a hundred and fifty dollars a year per seat, a number that assumes an employer is paying.",
            "Atlas is free, with no ads. For a student comparing an auto-scheduler against rent, that difference is not a rounding error."
          ]
        }
      ],
      "bottom": [
        "Motion is the right answer for a working professional with a calendar full of meetings and genuinely competing deadlines, who wants the machine to choose the order and will pay a hundred and fifty dollars a year to stop making that choice.",
        "Atlas fits the person running four courses and the rest of a life on Apple hardware: Canvas assignments arriving as projects, Apple and Google calendars writing both ways, and a calendar whose contents can always be explained."
      ],
      "faq": [
        {
          "q": "Does Motion sync with Apple Calendar?",
          "a": "Partly. Motion's documentation describes iCloud support as read-only, so it can display Apple Calendar events but cannot write scheduled blocks back. Google and Outlook calendars sync in both directions."
        },
        {
          "q": "Can Motion import a Canvas calendar?",
          "a": "No. Motion offers no Canvas integration and no calendar subscription field, so course schedules and assignment due dates have to be entered by hand."
        },
        {
          "q": "Is Atlas free?",
          "a": "Yes. Atlas costs nothing and carries no ads. Motion has no free tier and runs about a hundred and fifty dollars a year per seat."
        }
      ]
    },
    "sources": [
      "https://www.usemotion.com/pricing",
      "https://www.usemotion.com/help/time-management/all-things-calendars/reference-all-things-calendars/all-things-icloud",
      "https://www.usemotion.com/help/time-management/auto-scheduling/calendar-syncing-faq",
      "https://www.usemotion.com/integrations",
      "https://apps.apple.com/us/app/motion-tasks-ai-scheduling/id1580440623"
    ]
  },
  {
    "id": "akiflow",
    "name": "Akiflow",
    "tagline": "Task manager and calendar in one",
    "url": "https://akiflow.com",
    "cells": {
      "mac": "p",
      "mobile": "p",
      "apple2way": "n",
      "gcal2way": "y",
      "canvas": "n",
      "timeline": "y",
      "drag": "y",
      "capture": "y",
      "review": "n",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "p",
      "price": "$19/mo (annual)"
    },
    "prose": {
      "dek": "Akiflow consolidates tasks from ten work tools into one keyboard-driven day. Atlas starts from a calendar and a course list instead.",
      "intro": [
        "Akiflow exists for the person whose work arrives from everywhere at once: Slack threads, Jira tickets, Asana cards, Linear issues, Notion pages and starred Gmail. It pulls all of it into a single inbox, and a fast command bar turns each item into a time block on the day. For that job it is precise, keyboard-first, and hard to beat.",
        "Atlas is built for someone with the opposite problem. There is no scattered pile to consolidate, just a semester, a calendar and the rest of a life to fit around it. The dividing question is simple: does the work already sit in five other systems, or does it start with a syllabus and a due date?"
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Akiflow connects Google and Outlook calendars only. Apple Calendar is absent entirely, and the iCloud request has sat open on its public feature board for roughly five years. Anyone whose events live in Apple Calendar has to migrate them first.",
            "Atlas syncs Apple Calendar and Google Calendar in both directions, with each event attributed to the source it actually came from. Tasks and events occupy one timeline, and dragging a task onto the grid is what gives it a time."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Akiflow wins on capture.",
          "body": [
            "Akiflow's command bar is the reason people pay for it. Anything can be captured in a keystroke from anywhere, and the integrations mean items arrive on their own from the tools that generated them. Starred mail becomes a task, and un-starring it in Gmail marks it done.",
            "Atlas captures differently and more narrowly. A typed or spoken sentence gets parsed into tasks and events, filed into the right space and project, and shown for confirmation before it is saved. That review step is a real advantage over silent capture, but it is one input path against Akiflow's dozen."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Akiflow has no Canvas integration and, unusually, no ICS or webcal subscription either, which closes off the usual back door. A class schedule and its assignment dates simply have no way into the app.",
            "Atlas takes the Canvas feed directly. Course calendars, assignments and due dates come across, and the chosen courses become projects with their assignments already filed inside them."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Notes in Akiflow are task descriptions. That is enough for a line of context on a ticket and too little for a set of lecture notes or an essay outline.",
            "Atlas has long-form notes as a first-class object, kept two-way with Google Docs over the narrow drive.file scope, so it only ever touches documents it created or the ones deliberately picked. Akiflow's Gmail connection, by contrast, is central to how it works. Atlas never asks for access to email."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Akiflow wins on platforms.",
          "body": [
            "Akiflow runs on Windows, macOS, the web and iPhone, which matters when the same person uses a work PC and a personal Mac. The desktop apps are cross-platform builds rather than native Mac software, but they are available everywhere.",
            "Atlas is Apple-only: native macOS, iPhone and iPad, with no Windows build and no browser version. That is a hard limit, not a temporary one."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Akiflow is about $19 a month billed annually, roughly two hundred and thirty dollars a year, with no free tier. The integrations justify that for someone whose employer covers it.",
            "Atlas is free and carries no ads. A student paying for four courses is unlikely to add a two-hundred-dollar planner to the list."
          ]
        }
      ],
      "bottom": [
        "Akiflow is the correct choice for someone whose tasks arrive through Slack, Jira and a shared inbox, where consolidation is the actual problem. Nothing in Atlas addresses that, and Akiflow addresses it better than almost anything else on the market.",
        "Atlas suits the reader with one calendar, one course list and one Mac. Canvas assignments become projects, Apple and Google calendars stay in sync both ways, and nothing gets scheduled without a deliberate drag."
      ],
      "faq": [
        {
          "q": "Does Akiflow work with Apple Calendar?",
          "a": "No. Akiflow supports Google and Outlook calendars only, and iCloud support has been an open request on its feature board for about five years."
        },
        {
          "q": "Can Akiflow import a Canvas calendar?",
          "a": "No. Akiflow has no Canvas integration and no ICS or webcal subscription option, so there is no way to bring a course schedule in."
        },
        {
          "q": "How much does Akiflow cost compared to Atlas?",
          "a": "Akiflow is around $19 a month on the annual plan, roughly two hundred and thirty dollars a year, with no free tier. Atlas is free."
        },
        {
          "q": "Which is better for students, Atlas or Akiflow?",
          "a": "Atlas, clearly. It reads Canvas, syncs Apple Calendar both ways and costs nothing, while Akiflow's strengths are work integrations most students never touch."
        }
      ]
    },
    "sources": [
      "https://akiflow.com/pricing/",
      "https://akiflow.com/integrations",
      "https://product.akiflow.com/en/help/collections/1999346-integrations",
      "https://apps.apple.com/us/app/akiflow-ai-planner-calendar/id1621279084",
      "https://product.akiflow.com/help/articles/9441910-meet-aki-your-personal-assistant"
    ]
  },
  {
    "id": "sunsama",
    "name": "Sunsama",
    "tagline": "Daily planner that timeboxes tasks onto a calendar",
    "url": "https://www.sunsama.com",
    "cells": {
      "mac": "p",
      "mobile": "p",
      "apple2way": "y",
      "gcal2way": "y",
      "canvas": "n",
      "timeline": "y",
      "drag": "y",
      "capture": "y",
      "review": "p",
      "areas": "y",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "$17/mo (annual)"
    },
    "prose": {
      "dek": "Sunsama is the most thoughtful daily planner in this category, and it costs about two hundred dollars a year. Atlas costs nothing and reads Canvas.",
      "intro": [
        "Sunsama is a daily planning ritual in software. It walks through the day one task at a time, asks how long each will take, warns when the day is over-committed, tracks planned time against actual, and closes with a reflection. It connects Apple, Google and Outlook calendars and pulls tasks from the tools already in use. The design argues, persuasively, that doing less on purpose is the whole point.",
        "Atlas shares the two convictions that matter most: the day should be seen whole, and nothing should be scheduled without a person choosing it. What differs is the shape of the answer and who it is priced for. Sunsama offers a disciplined ritual for a working adult. Atlas offers a capture bar, a Mac-native calendar, and a semester it already understands."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Sunsama wins on calendars.",
          "body": [
            "Sunsama connects Apple, Google and Outlook calendars, which is the broadest coverage of the three, and its timeboxing puts tasks directly onto that grid. For someone carrying a work Outlook account alongside a personal iCloud one, that breadth is decisive.",
            "Atlas covers Apple Calendar and Google Calendar, both directions, with correct source attribution on every event. Tasks and events live on one timeline and a drag assigns the hour. It is the same idea over a narrower set of accounts."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Sunsama's entry point is the planning session. Items are brought in one at a time, estimated and placed, which is exactly the friction the product intends. It is excellent for reflection and slow for dumping a week out of a head at midnight.",
            "Atlas takes an unstructured sentence, typed or spoken, and returns tasks and events already sorted into spaces and projects, staged for review before saving. Both apps refuse to auto-schedule anyone. Atlas is simply quicker at the messy part."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Sunsama has no Canvas integration and no ICS subscription, so a class schedule has no route in. Lectures, labs and assignment deadlines would have to be entered by hand and re-entered each term.",
            "Atlas ingests the Canvas feed for course calendars, assignments and due dates, and turns selected courses into projects holding their own assignments. Nothing about a semester needs retyping."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Sunsama's notes attach to tasks and to days. That structure serves daily reflection well and does not stretch to an essay draft or a set of readings.",
            "Atlas keeps long-form documents in the app and syncs them two-way with Google Docs over the narrow drive.file scope, touching only files it created or ones explicitly chosen. Sunsama's Gmail connection uses a modify scope so mail can be browsed and converted to tasks in-app, a deliberate design that nonetheless means Sunsama sees the inbox. Atlas never asks for email access."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Sunsama wins on platforms.",
          "body": [
            "Sunsama runs on Windows, macOS, the web and iPhone, so the ritual survives a change of laptop or a borrowed machine.",
            "Atlas is Apple-only, with native macOS, iPhone and iPad apps and no Windows or web version. Anyone splitting time between a PC at work and a Mac at home should weigh that heavily."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Sunsama is about $17 a month on the annual plan, roughly two hundred dollars a year, with no free tier. That is priced for a person who expenses software.",
            "Atlas is free and ad-free. For a nineteen-year-old with four classes and no expense account, that gap decides the question before any feature does."
          ]
        }
      ],
      "bottom": [
        "Sunsama is the better product for a working adult whose problem is over-commitment rather than disorganisation. The daily ritual, the time estimates and the end-of-day reflection are genuinely more disciplined than anything Atlas does, and two hundred dollars a year is obviously worth it to fix a chronic over-commitment habit on a salary.",
        "Atlas is the better fit for a student on Apple hardware: Canvas courses arriving as projects, Apple and Google calendars synced both ways, long-form notes tied to Google Docs, and no bill at the end of it."
      ],
      "faq": [
        {
          "q": "Does Sunsama sync with Apple Calendar?",
          "a": "Yes. Sunsama connects Apple, Google and Outlook calendars, which is broader coverage than Atlas offers. Atlas syncs Apple and Google two-way but does not support Outlook."
        },
        {
          "q": "Can Sunsama import a Canvas calendar?",
          "a": "No. Sunsama has no Canvas integration and no ICS subscription option, so a course schedule cannot be brought in automatically."
        },
        {
          "q": "How much is Sunsama?",
          "a": "About $17 a month billed annually, roughly two hundred dollars a year, with no free tier. Atlas is free."
        },
        {
          "q": "Which is better for students, Atlas or Sunsama?",
          "a": "Atlas, on price and on school features. It reads Canvas, turns courses into projects and costs nothing, while Sunsama's planning ritual is aimed at working professionals."
        }
      ]
    },
    "sources": [
      "https://www.sunsama.com/pricing",
      "https://help.sunsama.com/docs/integrations/calendar/",
      "https://help.sunsama.com/docs/privacy-notes",
      "https://help.sunsama.com/docs/usage-guides/sunny/",
      "https://www.sunsama.com/"
    ]
  },
  {
    "id": "morgen",
    "name": "Morgen",
    "tagline": "Calendar and task planner with AI scheduling",
    "url": "https://www.morgen.so",
    "cells": {
      "mac": "p",
      "mobile": "p",
      "apple2way": "y",
      "gcal2way": "y",
      "canvas": "p",
      "timeline": "y",
      "drag": "y",
      "capture": "y",
      "review": "y",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "$15/mo (annual)"
    },
    "prose": {
      "dek": "Morgen is a capable cross-platform planner whose AI asks before it schedules; Atlas is the Mac app that understands a semester.",
      "intro": [
        "Morgen is a calendar and task planner for people whose work is spread across several operating systems. It connects Apple, Google and Outlook calendars, subscribes to arbitrary ICS feeds, and layers tasks and an AI planner on top. The planner drafts a day as preview events a person approves, rather than moving anything on its own.",
        "The trade-off is shape rather than quality. Morgen states on its own site that it is not a note-taking app, and it has no top-level areas of life: there are calendar sets and coloured task lists, so school and personal never fully separate. Atlas runs only on Apple hardware, but it treats a term of classes as a structure instead of a stream of events."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Morgen wins on calendars.",
          "body": [
            "Morgen reaches further than anything else here: Apple, Google and Outlook accounts plus subscription to any ICS feed, which is how a Canvas course calendar finds its way in.",
            "Atlas syncs Apple Calendar and Google Calendar two-way and reads the Canvas feed directly, which covers the calendars most students actually hold. Outlook accounts and arbitrary ICS URLs sit outside that list. On raw coverage, Morgen is ahead."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Both apps read a typed sentence and both stop for approval, and Morgen took that position first: the company says outright that its planner will never schedule or move a task without permission.",
            "The difference is where the result lands. Atlas takes a messy line, typed or spoken, such as “essay due Thursday, gym three times this week, call mom Sunday,” splits it into tasks and events, files each into the right space and project, and shows the set for review before saving. Morgen's capture ends in a list; Atlas's ends inside a project."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "In Morgen, Canvas arrives as a calendar feed. Assignments land on the right days, which is useful, but a class is never a place that can be opened.",
            "In Atlas, course calendars, assignments and due dates come through the Canvas feed, and the courses a student picks become projects with their assignments inside. Spaces sit above that, keeping School and Personal genuinely separate."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Morgen is direct about this: it is not a note-taking app. No long-form notes, no documents, so reading and writing happen somewhere else entirely.",
            "Atlas has long-form notes built in, kept two-way with Google Docs through the narrow drive.file scope, so it only ever touches documents it created or ones a person picked. Atlas never asks for access to email."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Morgen wins on platforms.",
          "body": [
            "Morgen runs on Windows, macOS, Linux, iPhone and Android. The desktop app is a cross-platform build rather than a Mac-first one, a fair criticism of the feel, but it opens on every machine a person owns.",
            "Atlas is a native macOS app with native iPhone and iPad apps on the App Store, and that is the whole list. No Windows version, no web version. Anyone with a Mac at home and a Windows machine at work should choose Morgen."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Morgen's free tier ended this year. What remains is a fourteen-day trial and then roughly a hundred and eighty dollars annually, a fair price for a mature cross-platform calendar and a real cost for a student. Atlas is free."
          ]
        }
      ],
      "bottom": [
        "Morgen is the right answer for a working professional who signs into a Windows laptop at the office and a Mac at home, keeps an Outlook work calendar beside a personal Google one, and wants a planner that proposes a day and waits to be told yes. Morgen serves that person well.",
        "Atlas is the right answer for someone on a Mac and an iPhone whose life is four classes plus everything around them, who wants assignments filed into the course they belong to, notes beside the schedule, and no annual bill."
      ],
      "faq": [
        {
          "q": "Does Morgen work with Canvas?",
          "a": "Yes, through an ICS subscription. The feed comes in as calendar events, which puts due dates on the right days but does not create a course that can be opened with its assignments behind it."
        },
        {
          "q": "Is Morgen still free?",
          "a": "No. The free tier ended this year, leaving a fourteen-day trial and then roughly a hundred and eighty dollars annually. Atlas is free."
        },
        {
          "q": "Which is better for students, Atlas or Morgen?",
          "a": "Atlas, for a student on Apple hardware: courses become projects with assignments inside, notes sync to Google Docs, and there is no subscription. Morgen is the better pick for a student who must use a Windows or Linux machine daily."
        }
      ]
    },
    "sources": [
      "https://www.morgen.so/pricing",
      "https://www.morgen.so/integrations",
      "https://www.morgen.so/for-ai",
      "https://apps.apple.com/us/app/morgen-calendar-planner/id1604574131",
      "https://www.lastingdynamics.com/clients/morgen/"
    ]
  },
  {
    "id": "amie",
    "name": "Amie",
    "tagline": "AI meeting notes with a calendar and todos",
    "url": "https://amie.so",
    "cells": {
      "mac": "p",
      "mobile": "p",
      "apple2way": "y",
      "gcal2way": "y",
      "canvas": "n",
      "timeline": "y",
      "drag": "y",
      "capture": "y",
      "review": "p",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "$20/user/mo (annual)"
    },
    "prose": {
      "dek": "Amie is now an AI meeting notetaker with a calendar attached: strong for a day of calls, weak for a term of classes.",
      "intro": [
        "Amie spent a few years as the best-looking calendar in this category, the one people posted screenshots of. As of 2026 it is something else: an AI meeting notetaker with a calendar and todos still attached. The site leads with AI agents, the changelog describes a note taker with calendar integration, and Meeting Notes is the first thing a new user sees.",
        "That reframes the comparison. Someone who sits in calls all day and wants them transcribed, chaptered and turned into follow-ups is exactly who Amie is built for, and Atlas does not compete there. A student looking at the same product finds no ICS subscription, no Canvas, no free tier, and a bill near two hundred and forty dollars a year."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "It's a tie on calendars.",
          "body": [
            "Amie connects Apple, Google and Outlook accounts, puts tasks and events on one timeline, and lets a task be dragged onto a time. Atlas syncs Apple Calendar and Google Calendar two-way, shares one timeline, and drags the same way.",
            "Each holds what the other lacks: Amie adds Outlook, Atlas adds the Canvas feed. For a student the Canvas side matters more; for an office worker, the Outlook side."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Amie parses natural language into events and todos smoothly. What it cannot do is decide where the result belongs: there are no spaces, and only a light notion of projects.",
            "Atlas takes a messy spoken or typed sentence, splits it into tasks and events, files each into the correct space and project, and presents everything for confirmation before saving. That filing step is what keeps a term from becoming one long list."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Amie has no ICS subscription and no Canvas support, so coursework is typed in by hand. Sign-up also requires a Google account, because the Gmail connection, which reads threads, drafts replies and manages labels, is central to the current product.",
            "Atlas pulls course calendars, assignments and due dates from the Canvas feed and turns chosen courses into projects holding their assignments. It never asks for access to email."
          ]
        },
        {
          "title": "Notes",
          "verdict": "It's a tie on notes.",
          "body": [
            "Amie's notes are meeting notes, and they are the point of the product now: transcription, chapters and action items pulled out of a call automatically. Nothing in Atlas does that.",
            "Atlas's notes are long-form documents that sit beside the schedule and stay two-way with Google Docs over the narrow drive.file scope. Different jobs, and each app is better at its own."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Amie wins on platforms.",
          "body": [
            "Amie's current product lives on the desktop and the web, so it opens on a Windows machine or in any browser. Atlas has none of that reach: native macOS, iPhone and iPad apps are the entire list, with no Windows version and no web version.",
            "One caveat is worth knowing first. The Amie app on the App Store is still the pre-pivot “Todos, calendar” build, last updated over a year ago, and there is no iPad version at all. On Apple devices specifically, Atlas is better served."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Amie costs twenty dollars per user each month on the annual plan, about two hundred and forty dollars a year, with no free tier. For software aimed at people whose employer pays for meeting tools, that is defensible. Atlas is free."
          ]
        }
      ],
      "bottom": [
        "Amie is the right answer for a consultant, recruiter or account manager whose calendar is wall-to-wall calls, who wants an AI in the room writing the summary and pulling out follow-ups, and whose company reimburses the subscription. For that person Atlas would be a downgrade.",
        "Atlas is the right answer for a Mac and iPhone user whose week is built around courses rather than meetings: Canvas assignments landing in the right projects, one timeline for tasks and events, notes in the same app, nothing to pay."
      ],
      "faq": [
        {
          "q": "Does Amie still have a free plan?",
          "a": "No. Amie is twenty dollars per user each month billed annually, roughly two hundred and forty dollars a year. Atlas is free."
        },
        {
          "q": "Does Amie have an iPad app?",
          "a": "No. There is no iPad version, and the iPhone app on the App Store is still the older “Todos, calendar” build from before the product changed direction. Atlas ships native iPhone and iPad apps."
        },
        {
          "q": "Can Amie import a Canvas calendar?",
          "a": "No. Amie has no ICS subscription, so a Canvas feed cannot be added and assignments must be entered by hand. Atlas reads the Canvas feed and turns chosen courses into projects."
        },
        {
          "q": "Which is better for students, Atlas or Amie?",
          "a": "Atlas, decisively. Amie's current product targets people in meetings all day and charges accordingly, while Atlas is free, handles Canvas, and keeps school separate from the rest of life."
        }
      ]
    },
    "sources": [
      "https://amie.so/",
      "https://amie.so/pricing",
      "https://amie.so/changelog",
      "https://amie.so/download",
      "https://apps.apple.com/us/app/amie-todos-calendar/id1548277133"
    ]
  },
  {
    "id": "reclaim",
    "name": "Reclaim.ai",
    "tagline": "AI calendar that auto-schedules tasks and habits",
    "url": "https://reclaim.ai",
    "cells": {
      "mac": "n",
      "mobile": "n",
      "apple2way": "n",
      "gcal2way": "y",
      "canvas": "n",
      "timeline": "y",
      "drag": "y",
      "capture": "p",
      "review": "p",
      "areas": "n",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "Free tier; $15/seat/mo (annual)"
    },
    "prose": {
      "dek": "Reclaim.ai defends focus time on a Google or Microsoft work calendar; Atlas is where an Apple user's classes, tasks and notes all live.",
      "intro": [
        "Reclaim.ai is a scheduling layer for a work calendar. Tasks, habits and one-on-ones become real blocks that rearrange themselves around meetings as the week moves, and it is very good at that specific job. Habits are a first-class feature, the free tier is genuine, and Dropbox acquired the company in 2024 without folding it into something else.",
        "It is less an alternative to Atlas than a layer for a different life. Reclaim assumes a calendar full of other people's meetings and a wish for software that pushes back on your behalf. Atlas assumes a Mac, a phone, four classes and a head full of loose ends, and tries to be the place all of it lands."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Reclaim connects Google and Microsoft calendars and nothing else: no Apple Calendar, no iCloud, no ICS subscription. For a student on an Apple laptop, most of the week is invisible to it.",
            "Atlas syncs Apple Calendar two-way and Google Calendar two-way, and tasks and events share one timeline, so a task can be dragged onto the calendar to give it a time."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Reclaim captures nothing. Tasks arrive from Google Tasks, Todoist or Jira, and its skill starts after that, placing them intelligently against meetings already booked.",
            "Atlas takes a sentence typed or spoken, splits it into tasks and events, files them into the right space and project, and shows everything for confirmation before saving. Reclaim's automatic defence of focus time remains the stronger idea for a calendar that fills with other people's invitations."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "No ICS support means no Canvas by any route, and Reclaim has no projects or areas to file coursework into even if it arrived. Its model of a week is meetings, habits and a synced task list.",
            "Atlas brings course calendars, assignments and due dates through the Canvas feed and turns selected courses into projects with their assignments inside, with Spaces keeping School apart from Personal."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Reclaim holds no content of its own: no notes, no documents, no place for a reading list or a draft. That is deliberate design rather than oversight, but it leaves a gap.",
            "Atlas has long-form notes built in and keeps them two-way with Google Docs over the narrow drive.file scope, touching only documents it created or ones that were picked. Atlas never asks for access to email."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Reclaim wins on platforms.",
          "body": [
            "Reclaim has no native apps at all. Its help centre states there are no mobile apps and suggests adding the web page to a phone's home screen, and there is no Mac app either. What that costs in polish it returns in reach: any browser on any operating system opens it.",
            "Atlas is native macOS with native iPhone and iPad apps, and stops there. No Windows, no web. For anyone off Apple hardware, Reclaim is available and Atlas is not."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Reclaim runs a real free tier, more than most of this category offers, with paid plans at fifteen dollars per seat each month on annual billing once the limits pinch. Atlas is free, with no seat count and no tier above it."
          ]
        }
      ],
      "bottom": [
        "Reclaim.ai is the right answer for someone employed at a company running on Google Workspace or Microsoft 365, whose calendar is largely other people's meetings, and who wants habits and focus blocks defended automatically. That person should use Reclaim; Atlas has nothing to offer them.",
        "Atlas is the right answer for a student on a Mac and an iPhone whose calendar lives in Apple Calendar or Google Calendar, whose deadlines come out of Canvas, and who wants classes, tasks and notes in one native app for nothing."
      ],
      "faq": [
        {
          "q": "Does Reclaim.ai work with Apple Calendar?",
          "a": "No. Reclaim supports Google and Microsoft calendars only, with no iCloud and no ICS subscription. Atlas syncs Apple Calendar two-way alongside Google Calendar."
        },
        {
          "q": "Does Reclaim.ai have a Mac app?",
          "a": "No, and it has no mobile apps either; the help centre recommends adding the web page to a phone's home screen. Atlas is a native macOS app with native iPhone and iPad apps on the App Store."
        },
        {
          "q": "Can Reclaim.ai import a Canvas calendar?",
          "a": "No. Reclaim cannot subscribe to ICS feeds, so a Canvas calendar cannot be added at all. Atlas reads the Canvas feed and turns chosen courses into projects holding their assignments."
        },
        {
          "q": "Which is better for students, Atlas or Reclaim.ai?",
          "a": "Atlas, for almost any student. Reclaim is built around a work calendar it can see, and on an Apple laptop it cannot see most of one. Atlas covers Apple Calendar, Google Calendar and Canvas, and costs nothing."
        }
      ]
    },
    "sources": [
      "https://reclaim.ai/pricing",
      "https://reclaim.ai/blog/dropbox-acquires-reclaim",
      "https://help.reclaim.ai/en/articles/6916961-how-to-use-reclaim-on-your-mobile-device",
      "https://reclaim.ai/integrations",
      "https://help.reclaim.ai/en/articles/14846468-reclaim-ai-2-0-overview"
    ]
  },
  {
    "id": "anydo",
    "name": "Any.do",
    "tagline": "To-do list, calendar and reminders app",
    "url": "https://www.any.do/",
    "cells": {
      "mac": "p",
      "mobile": "y",
      "apple2way": "y",
      "gcal2way": "y",
      "canvas": "n",
      "timeline": "y",
      "drag": "y",
      "capture": "y",
      "review": "y",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "$4.99/mo (annual)"
    },
    "prose": {
      "dek": "Any.do is the cheaper list for a whole household; Atlas is the one built around a semester on Apple hardware.",
      "intro": [
        "Any.do is a to-do list, calendar and reminder app that runs almost everywhere: Mac, iPhone, iPad, Windows, Android and the web, for about five dollars a month on an annual plan. It connects properly to Apple and Google calendars, accepts a typed or spoken sentence and shows a review screen before saving, and it is shaped for shared lists between people who live together.",
        "Atlas is a native macOS app with native iPhone and iPad apps, free, built around Spaces you name yourself with Projects inside them. The trade-off is straightforward. Any.do covers more devices and more of the family; Atlas covers the specific shape of a school year, including the class calendar that Any.do has no route to import."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "It’s a tie on calendars.",
          "body": [
            "Any.do does this well, and its reputation undersells it. Apple and Google calendars connect two-way, Outlook is supported too, and on desktop and web a task can be dragged onto a slot in the day. Tasks and events sit on the same surface rather than in separate apps.",
            "Atlas matches the two-way sync with Apple Calendar and Google Calendar, and puts tasks and events on one timeline where dragging a task onto the calendar gives it a time. Atlas has no Outlook connection; Any.do has no way to subscribe to an ICS or webcal feed. Different gaps, roughly even weight."
          ]
        },
        {
          "title": "Capture",
          "verdict": "It’s a tie on capture.",
          "body": [
            "Both apps take a sentence rather than a form. Any.do parses natural language, supports voice, and puts a review screen in front of the save so nothing lands in the wrong list without being seen.",
            "Atlas takes a messier input and does more with it. Type or speak something like “essay due Thursday, gym three times this week, call mom Sunday” and Atlas splits it into separate tasks and events, files each into the right space and project, and shows the whole set for confirmation before saving. The filing step is the difference; the review habit is common to both."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Any.do has Spaces, but they are three fixed types: Personal, Family and Workspace. A School space cannot be created. There is also no field anywhere in the app for pasting an ICS or webcal URL, so a Canvas class calendar can only reach Any.do by being subscribed in the system calendar and hoping the mirror carries it on that one device.",
            "Atlas connects to Canvas directly. Course calendars, assignments and due dates arrive through the feed, and the courses selected become projects with their assignments already inside them. Spaces are whatever the year actually looks like: School, Personal, anything else."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Any.do has no real writing surface. Task descriptions and attachments exist, but there is nowhere to draft an essay outline or keep lecture notes that belong to a course.",
            "Atlas has long-form notes built in and keeps them two-way with Google Docs over the narrow drive.file scope, meaning Atlas only ever touches documents it created or that were explicitly picked. Notes live inside a project, so a note about a paper sits with the assignment it belongs to."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Any.do wins on platforms.",
          "body": [
            "Any.do runs on Windows, Android and the web alongside Mac, iPhone and iPad. For a household where one person is on a PC and another on a Pixel, that reach settles the question on its own.",
            "Atlas is Apple only: macOS, iPhone and iPad, with no Windows client and no web version. On a campus where the laptop is a MacBook that is a non-issue, and anywhere else it is a hard limit."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Any.do costs about $4.99 a month billed annually for the full feature set, and the free tier has a long-standing reputation for pushing that upgrade inside the app. There is no third-party advertising, but a free user sees a steady stream of prompts.",
            "Atlas is free, with no paid tier to be nudged toward and no advertising. Atlas also never asks for access to email."
          ]
        }
      ],
      "bottom": [
        "Any.do is the right answer for a parent coordinating a household across mixed hardware: a shared grocery list on an Android phone, a school-run reminder on a Windows laptop, a calendar everyone can see. Five dollars a month for that reach is fair, and the app is mature enough to trust with it.",
        "Atlas is the right answer for a student on a Mac whose year is organised by courses. Canvas assignments arriving as projects, a single timeline for tasks and events, notes that stay in sync with Google Docs, and no subscription is a different set of priorities than breadth of devices."
      ],
      "faq": [
        {
          "q": "Can Any.do import a Canvas calendar?",
          "a": "No. Any.do has no ICS or webcal subscription field, so a Canvas feed cannot be added to it directly. The only workaround is subscribing to the feed in the system calendar and relying on that mirror."
        },
        {
          "q": "Does Any.do sync two-way with Google Calendar?",
          "a": "Yes. Any.do connects to Google Calendar, Apple Calendar and Outlook with two-way sync, and events appear alongside tasks on the same day view. Atlas does the same for Apple and Google, without Outlook."
        },
        {
          "q": "Is Atlas free?",
          "a": "Yes, Atlas is free, with no premium tier and no ads. Any.do’s full feature set costs roughly $4.99 a month on an annual plan."
        },
        {
          "q": "Which is better for students, Atlas or Any.do?",
          "a": "Atlas, for a student on Apple hardware. It creates a School space, pulls Canvas courses in as projects with their assignments, and keeps notes beside them; Any.do’s fixed Personal, Family and Workspace spaces have no equivalent."
        }
      ]
    },
    "sources": [
      "https://www.any.do/pricing",
      "https://www.any.do/to-do-list-app-for-mac/",
      "https://support.any.do/en/articles/8610622-getting-started-with-the-calendar-integration",
      "https://support.any.do/en/articles/9961171-any-do-s-spaces-explained",
      "https://apps.apple.com/us/app/any-do-to-do-list-calendar/id497328576"
    ]
  },
  {
    "id": "ms-todo",
    "name": "Microsoft To Do",
    "tagline": "Free task lists synced with Outlook",
    "url": "https://www.microsoft.com/en-us/microsoft-365/microsoft-to-do-list-app",
    "cells": {
      "mac": "y",
      "mobile": "y",
      "apple2way": "n",
      "gcal2way": "n",
      "canvas": "n",
      "timeline": "p",
      "drag": "p",
      "capture": "p",
      "review": "n",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "Free"
    },
    "prose": {
      "dek": "Microsoft To Do is a free, native list app with no calendar inside it; Atlas puts the list and the calendar on one timeline.",
      "intro": [
        "Microsoft To Do is a free task manager built around lists, groups and sharing, storing tasks on Exchange so they surface in Outlook’s task pane. Two things about it are better than its reputation suggests: it ships a real native Mac app, and has since 2019, and it is genuinely free with no ads and no in-app purchases. Almost nothing else in this category can say both.",
        "Atlas is a free native macOS app with native iPhone and iPad apps, built so tasks, calendar events, courses and notes live in one place. The trade-off here is unusually clean. Microsoft To Do is a very good list; Atlas is a list attached to a calendar, a Canvas feed and a writing surface."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Microsoft To Do has no calendar surface at all. Tasks reach Outlook because they are stored on Exchange, but inside To Do there is no timeline, no day view, and nothing to drag a task onto. Scheduling happens in Outlook, in a second app.",
            "Atlas syncs two-way with both Apple Calendar and Google Calendar and shows tasks and events on a single timeline. Dragging a task onto the calendar is how it gets a time. To Do connects to neither Apple nor Google Calendar and accepts no ICS subscription."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "To Do recognises due dates written into a task title, but that smart recognition works on Windows and iOS and not in the Mac app. There is no confirmation screen, because there is little to confirm: a task and possibly a date.",
            "Atlas takes a full sentence, typed or spoken, and pulls several items out of it at once. A line like “essay due Thursday, gym three times this week, call mom Sunday” becomes tasks and events sorted into the right space and project, presented for review before anything is saved."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "To Do understands lists and groups, not courses. There is no way to bring a Canvas schedule in, since the app supports no calendar accounts and no ICS feeds, and nothing in the data model corresponds to a class.",
            "Atlas pulls course calendars, assignments and due dates from the Canvas feed, and the chosen courses become projects holding their own assignments. Spaces such as School and Personal keep the semester separate from everything else."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "There is nowhere to write in Microsoft To Do. Each task has a notes field and file attachments, which is fine for a reminder and useless for a reading response or a lab write-up.",
            "Atlas has long-form notes as a first-class surface, kept two-way with Google Docs over the narrow drive.file scope, so Atlas only ever touches documents it created or that were picked deliberately. A note belongs to a project rather than floating in a separate app."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Microsoft To Do wins on platforms.",
          "body": [
            "To Do runs natively on Mac, iPhone, iPad, Windows and Android, and on the web, with sharing across all of them. The Mac app is small, AppKit, and still maintained, despite Microsoft’s own marketing page neglecting to mention it exists.",
            "Atlas is macOS, iPhone and iPad only. No Windows app, no web version. For anyone splitting time between a PC lab and a personal laptop, that alone can decide it."
          ]
        },
        {
          "title": "Price",
          "verdict": "It’s a tie on price.",
          "body": [
            "Both apps are free. Microsoft To Do has no paid tier, no advertising and no in-app purchases, and it comes bundled with a Microsoft 365 account many schools already provide.",
            "Atlas is also free, with no upsell and no ads, and never asks for access to email. Neither app charges, so price is not the deciding factor between them."
          ]
        }
      ],
      "bottom": [
        "Microsoft To Do is the right answer for someone whose school or workplace runs on Microsoft 365 and whose calendar already lives in Outlook. Pairing a free, fast list app with the calendar the institution mandates is a perfectly sound setup, and switching away from it would mean giving up integration that already works.",
        "Atlas is the argument for not running two apps at once. On a Mac, with an iPhone and an iPad, a student gets Canvas assignments as projects, tasks and events on one timeline, and notes that stay with the work they describe."
      ],
      "faq": [
        {
          "q": "Does Microsoft To Do have a calendar view?",
          "a": "No. To Do has no calendar surface; tasks appear on the Outlook calendar’s task pane because they are stored on Exchange. Any scheduling has to happen in Outlook."
        },
        {
          "q": "Is there a Mac app for Microsoft To Do?",
          "a": "Yes. A native AppKit Mac app has shipped since 2019 and is still being updated, even though Microsoft’s marketing page for To Do does not mention it."
        },
        {
          "q": "Can Microsoft To Do sync with Google Calendar?",
          "a": "No. To Do connects to neither Google Calendar nor Apple Calendar, and has no ICS subscription option. Atlas syncs two-way with both."
        },
        {
          "q": "Which is better for students, Atlas or Microsoft To Do?",
          "a": "Atlas, unless the school is entirely a Microsoft 365 campus. Atlas turns Canvas courses into projects with their assignments and holds them on the same timeline as the calendar, which To Do cannot do at any price."
        }
      ]
    },
    "sources": [
      "https://apps.apple.com/us/app/microsoft-to-do/id1274495053?mt=12",
      "https://apps.apple.com/us/app/microsoft-to-do/id1212616790",
      "https://www.microsoft.com/en-us/microsoft-365/microsoft-to-do-list-app",
      "https://support.microsoft.com/en-us/office/smart-due-date-reminder-recognition-in-microsoft-to-do-b8cde14b-28da-42e1-9ce8-d75cc3717993"
    ]
  },
  {
    "id": "craft",
    "name": "Craft",
    "tagline": "Notes, tasks, and daily planning",
    "url": "https://www.craft.do",
    "cells": {
      "mac": "y",
      "mobile": "y",
      "apple2way": "p",
      "gcal2way": "n",
      "canvas": "n",
      "timeline": "y",
      "drag": "p",
      "capture": "p",
      "review": "n",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "y",
      "price": "$6.40/mo (annual)"
    },
    "prose": {
      "dek": "Craft is the better writing app on Apple hardware; Atlas is the one that can actually schedule the day it shows you.",
      "intro": [
        "Craft is a native notes and documents app for Mac, iPad and iPhone, with Windows and web clients as well, at roughly $6.40 a month on an annual plan. Its documents are the best-looking on the platform, its Spaces are real top-level partitions, and the daily note flow puts today’s events, tasks and writing side by side in one calm view.",
        "Atlas is a free native macOS app with iPhone and iPad companions, organised around Spaces and Projects, with tasks and calendar events sharing one timeline. The trade-off is legible from the first minute: Craft is a writing tool that reads a calendar, and Atlas is a planner that also writes."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Craft’s own documentation is explicit about the limits. The calendar integration connects to Apple Calendar, on Mac, read-only, and it does not exist on Windows or the web. Google and Outlook events only appear if those accounts were added to Apple Calendar first, and nothing Craft does writes back to any calendar.",
            "Atlas syncs two-way with Apple Calendar and with Google Calendar directly. Craft allows a task to be moved to another day but not onto an hour; in Atlas a task dropped on Thursday at two becomes an event at Thursday at two."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Craft parses some date text when a task is typed, but there is no voice capture and no review step, because there is no routing decision to review. Everything lands where the cursor already was.",
            "Atlas is built for a messy sentence spoken on the walk home. “Essay due Thursday, gym three times this week, call mom Sunday” comes back as separate tasks and events, sorted into the right space and project, held on a confirmation screen until approved."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Craft has no ICS field, so a Canvas class calendar has no way in, and no concept of a course. A student can build a School space by hand and keep documents in it, but the assignments and due dates have to be typed by the person who already has to do the assignments.",
            "Atlas takes the Canvas feed directly: course calendars, assignments and due dates arrive on their own, and the courses selected become projects with those assignments inside them."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Craft wins on notes.",
          "body": [
            "Craft is the stronger writing environment, and likely always will be. The editor, the block model, the typography and the polish of the exported document are ahead of what Atlas offers, and for anyone whose week centres on writing, that gap matters more than any calendar feature.",
            "The one place Atlas takes a point is round-tripping. Craft imports from Google Docs once, as a conversion; Atlas keeps a note and a Doc in sync in both directions over the narrow drive.file scope, touching only documents it created or that were picked."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Craft wins on platforms.",
          "body": [
            "Craft is native on Mac, iPad and iPhone and also ships Windows and web clients, so a document written on a MacBook is readable from a shared PC or a browser on campus.",
            "Atlas is Apple only, with no Windows app and no web version. That is a real limit, and worth weighing before switching if any part of the week happens on a machine that is not a Mac."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Craft’s paid plan runs about $6.40 a month billed annually, which buys a genuinely excellent editor. On a student budget it is still a subscription competing with everything else that bills monthly.",
            "Atlas is free, has no advertising, and never requests access to email. Sharing exists in the Mac app, though Atlas is not a team collaboration tool and does not try to be."
          ]
        }
      ],
      "bottom": [
        "Craft is the right answer for a writer first and a planner second: someone drafting long documents on an iPad, who wants the nicest pages on Apple hardware and finds it sufficient to see the day’s calendar rather than change it. That person should stay with Craft and let a separate calendar app do the scheduling.",
        "Atlas suits the student whose bottleneck is the schedule rather than the prose. Canvas assignments arriving as projects, two-way Google Calendar sync, a task dropped onto an hour, and notes that stay in step with Google Docs add up to a planner that happens to write, at no cost."
      ],
      "faq": [
        {
          "q": "Does Craft sync two-way with Google Calendar?",
          "a": "No. Craft’s calendar integration is read-only, connects only to Apple Calendar on the Mac, and never writes back. Google events reach it only if the Google account was added to Apple Calendar first."
        },
        {
          "q": "Can Craft import a Canvas calendar?",
          "a": "No. Craft has no ICS or webcal subscription field, so Canvas assignments have to be entered by hand. Atlas connects to the Canvas feed and turns chosen courses into projects."
        },
        {
          "q": "Is Craft’s editor better than Atlas?",
          "a": "Yes. Craft is the stronger document app on Mac and iPad, with a more capable editor and better-looking output. Atlas notes are built to sit next to assignments and stay in sync with Google Docs, not to win on typography."
        },
        {
          "q": "Which is better for students, Atlas or Craft?",
          "a": "Atlas, for a student managing courses and deadlines on a Mac. Craft is the better pick for a student whose work is mostly long-form writing and who already has a calendar app they trust."
        }
      ]
    },
    "sources": [
      "https://www.craft.do/pricing",
      "https://support.craft.do/en/integrate/calendar",
      "https://support.craft.do/en/plan-and-do/calendar",
      "https://craft-support.mintlify.app/en/introduction/platforms.md",
      "https://apps.apple.com/us/app/craft-docs-notes-ai-editor/id1487937127"
    ]
  },
  {
    "id": "obsidian",
    "name": "Obsidian",
    "tagline": "Local-first Markdown notes with plugins",
    "url": "https://obsidian.md",
    "cells": {
      "mac": "p",
      "mobile": "y",
      "apple2way": "p",
      "gcal2way": "p",
      "canvas": "p",
      "timeline": "p",
      "drag": "p",
      "capture": "p",
      "review": "n",
      "areas": "p",
      "gdocs": "p",
      "windows": "y",
      "teams": "p",
      "price": "Free (Sync $4/mo annual)"
    },
    "prose": {
      "dek": "Obsidian is the more durable notebook and runs almost everywhere; Atlas is the app that already knows when the work is due.",
      "intro": [
        "Obsidian is a local-first Markdown editor. Every note is a plain text file in a folder on the disk, so no company controls the format and no subscription stands between a person and their own writing. The app is free, including for commercial use, with the paid licence functioning as voluntary support. A large community plugin ecosystem extends it in almost any direction.",
        "Atlas is a native macOS app with iPhone and iPad companions, built around a calendar that school and personal life both live on. The trade-off is clean: Obsidian is a filing system that can be shaped into a planner, while Atlas is a planner that happens to keep notes. Which one fits depends on whether the week or the archive is the problem."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Obsidian ships no first-party calendar and no first-party task manager. Calendar views, ICS feeds and task importers all arrive as community plugins, which require restricted mode to be turned off, their own OAuth credentials configured by hand, and maintainers who keep going. A planner can absolutely be assembled this way, but its durability belongs to volunteers rather than to the app.",
            "Atlas syncs two-way with Apple Calendar and two-way with Google Calendar out of the box. Tasks and events share a single timeline, and dragging a task onto the calendar is how it gets a time."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Capture in Obsidian means creating a note, and a very fast one at that. Turning a sentence into a dated task on a calendar is a different job, and it lands on whichever plugin chain a person has chosen to install and maintain.",
            "Atlas takes a messy sentence typed or spoken in one go, splits it into separate tasks and events, files each one into the right space and project, and puts the whole result on screen for review before anything is saved."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Obsidian has no concept of a course, an assignment or a due date beyond what a person builds from folders, tags and Dataview queries. Worth clearing up: the Canvas feature inside Obsidian is an infinite whiteboard for arranging cards, and has nothing to do with Canvas LMS.",
            "In Atlas, course calendars, assignments and due dates arrive through the Canvas feed, and the courses selected become projects with their assignments already inside them. That is a fixed structure rather than a construction project."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Obsidian wins on notes.",
          "body": [
            "This is the section where Obsidian is simply better, and it is not close. Backlinks, graph view, templating and thousands of plugins add up to a writing environment no planner matches. Notes stay readable files on disk long after any particular app stops being maintained.",
            "Atlas has long-form notes built in, kept two-way with Google Docs over the narrow drive.file scope, so it touches only documents it created or that were explicitly picked. That is a solid notebook next to a calendar, not a replacement for a knowledge base."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Obsidian wins on platforms.",
          "body": [
            "Obsidian runs on macOS, Windows, Linux, iOS and Android, with the vault syncing between them through the paid Sync service or any folder-sync tool.",
            "Atlas is Apple only. There is no Windows build and no web version, so a shared Windows lab machine or a Chromebook is out of reach. For anyone whose week involves a PC, that settles this section."
          ]
        },
        {
          "title": "Price",
          "verdict": "It's a tie on price.",
          "body": [
            "Obsidian is free to use, with a voluntary licence for commercial settings and an optional Sync subscription at roughly four dollars a month billed annually. Nothing about the core app is paywalled.",
            "Atlas is free, with no ads and no request for access to email. Neither app charges to get started, so cost should not decide this one."
          ]
        }
      ],
      "bottom": [
        "Someone who wants to own their files outright, who enjoys assembling a system to their own taste, and who is keeping notes they expect to still be able to read in twenty years should pick Obsidian. That reader is real and common, and no calendar feature changes what plain Markdown on a local disk is worth to them.",
        "Someone whose actual problem is a Tuesday with three deadlines, a shift and a lab report should pick Atlas, where the calendar, the Canvas connection and the capture bar work on the first afternoon. Running both is a coherent setup: Obsidian as the permanent notebook, Atlas for the week."
      ],
      "faq": [
        {
          "q": "Does Obsidian have a built-in calendar?",
          "a": "No. Obsidian ships no first-party calendar or task manager, so calendar views and ICS feeds come from community plugins that need restricted mode disabled and their own credentials configured. Those plugins work well, but they are maintained by volunteers rather than by the company."
        },
        {
          "q": "Is Atlas free?",
          "a": "Yes, Atlas is free, with no advertising. It also never asks for access to email."
        },
        {
          "q": "Which is better for students, Atlas or Obsidian?",
          "a": "Atlas, for the scheduling half of student life, because courses, deadlines and a two-way calendar are built in. Obsidian is better for lecture notes, research and anything meant to last past graduation. A lot of students end up running both."
        }
      ]
    },
    "sources": [
      "https://obsidian.md/",
      "https://obsidian.md/pricing",
      "https://obsidian.md/changelog/",
      "https://obsidian.md/help/plugins",
      "https://apps.apple.com/us/app/obsidian-connected-notes/id1557175442"
    ]
  },
  {
    "id": "myhomework",
    "name": "myHomework Planner",
    "tagline": "Cross-platform assignment and class planner",
    "url": "https://myhomeworkapp.com",
    "cells": {
      "mac": "p",
      "mobile": "y",
      "apple2way": "p",
      "gcal2way": "n",
      "canvas": "p",
      "timeline": "p",
      "drag": "?",
      "capture": "?",
      "review": "?",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "p",
      "price": "Free with ads; $4.99/yr"
    },
    "prose": {
      "dek": "myHomework is the cheap, everywhere-available assignment list; Atlas is the same idea rebuilt around a real calendar on a Mac.",
      "intro": [
        "myHomework Planner has been a default student planner since 2009, and the core model still holds up. Classes are real objects, assignments hang off them, a course schedule can be imported, and Premium costs $4.99 a year. For anyone who wants the least expensive way to track what is due, on almost any device, it remains a reasonable pick.",
        "Two facts shape the comparison. The iPhone app was last updated in February 2025, and the Mac App Store version was last updated in April 2019 under a different developer name, with a help centre article devoted to fixing it. The company now sells digital hall-pass software to K-12 schools, and the planner is the smaller half of that business."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "myHomework holds assignment-shaped things. There is no way to bring a personal calendar in, and its own calendar export runs one direction only, out to other apps. A shift at work, a doctor's appointment and a study block cannot sit next to a problem set.",
            "Atlas syncs two-way with Apple Calendar and two-way with Google Calendar, and puts tasks and events on one timeline. Dragging a task onto the calendar gives it a time, which is the move that turns a list of deadlines into a plan for Thursday."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Adding work to myHomework means filling in a form: pick a class, name the assignment, set a due date, choose a type. It is fast enough once the classes are set up, and entirely manual.",
            "Atlas accepts a messy sentence typed or spoken, such as an essay due Thursday plus the gym three times this week plus a Sunday phone call, then splits it into tasks and events, routes them to the right space and project, and shows the full result for confirmation before saving."
          ]
        },
        {
          "title": "School",
          "verdict": "Atlas wins on school.",
          "body": [
            "Both apps take Canvas coursework in through the Canvas calendar feed rather than the Canvas API, so the transport is identical. The difference is what happens next.",
            "myHomework lands the imported items in a class list and stops there. Atlas turns the selected courses into projects with their assignments inside them, sitting alongside a Personal space, so coursework and the rest of the week share one structure instead of living in separate apps."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "myHomework has no notes feature. Lecture notes, a reading summary or an essay outline all have to live somewhere else, which usually means a second app and a second place to look.",
            "Atlas has long-form notes built in, kept two-way with Google Docs through the narrow drive.file scope, so it only ever touches documents it created or that were explicitly picked. A note can sit inside the same project as the assignment it belongs to."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "myHomework wins on platforms.",
          "body": [
            "myHomework runs on iPhone, iPad, Android, Windows and the web, which matters enormously for a student issued a school Chromebook or working on a shared lab PC. The Mac App Store build is the weak point, given a last update in April 2019.",
            "Atlas is Apple only, with native macOS, iPhone and iPad apps and no Windows or web version at all. On breadth of devices, this section goes to myHomework without qualification."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "myHomework's free tier carries advertising, as its pricing page states, and removing the ads costs $4.99 a year. That is a small sum, and it is still a paywall and an ad-supported default.",
            "Atlas is free, with no advertising and no upgrade tier, and it never asks for access to email."
          ]
        }
      ],
      "bottom": [
        "A student on a Windows laptop or a school-issued Chromebook who needs nothing more than a tidy list of what is due, and who would rather spend five dollars a year than think about it again, should pick myHomework. It has survived fifteen years for a reason, and it will run on whatever hardware the school hands out.",
        "A student on a Mac and an iPhone whose week also contains shifts, training, family and rent should pick Atlas, where coursework lands on the same calendar as everything else and the notes live next to the assignments."
      ],
      "faq": [
        {
          "q": "Can myHomework sync with Google Calendar?",
          "a": "No, not two-way. myHomework can push its assignments out to another calendar as a feed, but personal calendar events cannot be brought back in, so the planner stays a list of coursework. Atlas syncs two-way with both Google Calendar and Apple Calendar."
        },
        {
          "q": "Is the free version of myHomework ad-supported?",
          "a": "Yes. The free tier shows advertising, which the pricing page states plainly, and Premium at $4.99 a year removes it. Atlas is free with no ads."
        },
        {
          "q": "Which is better for students, Atlas or myHomework?",
          "a": "Atlas, for a student on Apple hardware who wants coursework, personal commitments and notes in one place. myHomework is the better choice on Windows, Android or a Chromebook, since Atlas does not run there."
        }
      ]
    },
    "sources": [
      "https://myhomeworkapp.com/pricing",
      "https://myhomeworkapp.com/help",
      "https://myhomeworkapp.com/help/schoology-import",
      "https://apps.apple.com/us/app/myhomework-student-planner/id303490844",
      "https://apps.apple.com/us/app/myhomework-student-planner/id970610831?mt=12"
    ]
  },
  {
    "id": "shovel",
    "name": "Shovel Study Planner",
    "tagline": "Time-blocking study planner for coursework",
    "url": "https://shovelapp.io",
    "cells": {
      "mac": "p",
      "mobile": "p",
      "apple2way": "p",
      "gcal2way": "n",
      "canvas": "p",
      "timeline": "y",
      "drag": "y",
      "capture": "n",
      "review": "y",
      "areas": "p",
      "gdocs": "n",
      "windows": "y",
      "teams": "p",
      "price": "$3.25/mo (annual)"
    },
    "prose": {
      "dek": "Shovel is a serious coursework planner with real workload math; Atlas covers school plus the rest of life, natively on a Mac.",
      "intro": [
        "Shovel Study Planner is built for the college week: courses, readings, deadlines and the hours available to do them. It is actively developed, it pulls Canvas courses in and turns them into real courses with tasks, and it does time-blocking properly. Its Cushion figure, which shows whether the remaining hours actually cover the remaining work, is a genuinely good idea with no equivalent in Atlas.",
        "The difference is where each app lives and how much of a life it covers. Shovel is a web app, with a browser install its own documentation describes as still a web app that does not work offline, and an iPhone companion whose App Store description says setup happens on the website first. Atlas is native software for Apple hardware that holds school alongside everything else."
      ],
      "sections": [
        {
          "title": "Calendars",
          "verdict": "Atlas wins on calendars.",
          "body": [
            "Shovel's Google Calendar sync runs one direction: its documentation states that changes made in Shovel are not sent back to Google. Apple and Outlook calendars have to be published as a public URL and routed through Google, and Shovel's own help article warns that propagation can take up to twelve hours.",
            "Atlas syncs two-way with Apple Calendar and two-way with Google Calendar directly, so an event moved in either place moves in both within the sync cycle. Tasks and events share one timeline, and a task can be dragged onto the calendar to claim a slot."
          ]
        },
        {
          "title": "Capture",
          "verdict": "Atlas wins on capture.",
          "body": [
            "Shovel's syllabus upload parses a PDF and shows the extracted tasks for review before importing, which is a well-judged piece of design and a genuine confirmation step. It applies to syllabus documents specifically.",
            "Atlas applies the same principle to everyday input. A messy sentence, typed or spoken, becomes a set of tasks and events filed into the right space and project, with the whole batch shown for review before anything is saved."
          ]
        },
        {
          "title": "School",
          "verdict": "Shovel wins on school.",
          "body": [
            "For pure coursework, Shovel goes deeper. Courses carry estimated reading and study time, the time-blocking model is designed around fitting work into available hours, and the Cushion figure turns a pile of deadlines into a straight answer about whether the week is survivable. Nothing in Atlas does that math.",
            "Both apps read Canvas through the calendar feed rather than the API, so the ingest is comparable. Atlas turns the chosen courses into projects with their assignments inside them, which is good structure, but it is structure rather than workload estimation."
          ]
        },
        {
          "title": "Notes",
          "verdict": "Atlas wins on notes.",
          "body": [
            "Shovel has no notes feature, and no personal space sitting alongside the academic one. Anything that is not coursework goes into a different app.",
            "Atlas keeps long-form notes inside the same projects as the work, and syncs them two-way with Google Docs over the narrow drive.file scope, meaning it touches only documents it created or that were explicitly selected. Spaces separate School from Personal without separating the calendar."
          ]
        },
        {
          "title": "Platforms",
          "verdict": "Shovel wins on platforms.",
          "body": [
            "Being a web app, Shovel opens on Windows, Linux, a Chromebook or a library machine with nothing installed. The offline caveat is real, and so is the reach.",
            "Atlas runs only on Apple platforms: native macOS, iPhone and iPad apps, no Windows build, no web version. Anyone who switches between a Mac at home and a PC elsewhere is better served by the browser."
          ]
        },
        {
          "title": "Price",
          "verdict": "Atlas wins on price.",
          "body": [
            "Shovel costs about $3.25 a month on the annual plan, with no free tier once the trial ends. For a tool used every day of a semester that is defensible, and it is still a recurring bill.",
            "Atlas is free, with no advertising, no premium tier and no request for access to email."
          ]
        }
      ],
      "bottom": [
        "A student whose week is essentially all coursework, who wants workload estimation done properly, and who already works in a browser across mixed hardware should pick Shovel. The Cushion model is the strongest single idea in this comparison, and a heavy semester is exactly where it pays off.",
        "A student on a Mac and an iPhone whose life includes a job, a gym schedule, family and reading that has nothing to do with a syllabus should pick Atlas, where two-way calendar sync, Canvas coursework, notes and personal commitments occupy one timeline for free."
      ],
      "faq": [
        {
          "q": "Does Shovel sync two-way with Google Calendar?",
          "a": "No. Shovel's documentation states that changes made inside Shovel are not sent back to Google Calendar, and Apple or Outlook calendars must be published as a public URL routed through Google, which can take up to twelve hours to propagate. Atlas syncs two-way with both Apple Calendar and Google Calendar."
        },
        {
          "q": "Is Atlas free?",
          "a": "Yes. Atlas is free with no advertising and no paid tier, while Shovel costs roughly $3.25 a month on its annual plan after the trial."
        },
        {
          "q": "Which is better for students, Atlas or Shovel?",
          "a": "Shovel, for a student who wants rigorous workload estimation and needs the app to open on any computer. Atlas, for a student on Apple hardware whose planner has to hold school and personal life together in one calendar."
        }
      ]
    },
    "sources": [
      "https://apps.apple.com/us/app/shovel-study-planner/id1467742357",
      "https://shovelapp.io/",
      "https://help.shovelapp.io/en/connect-school-system/connect-canvas-to-shovel",
      "https://help.shovelapp.io/en/calendar/connect-google-calendar",
      "https://courses.shovelapp.io/lessons/pdf-syllabus-upload/"
    ]
  }
];

/* =====================================================================
   Render
   ===================================================================== */
const MAX_COLS = 3;
const DEFAULT = "notion";

const byId = Object.fromEntries(competitors.map(c => [c.id, c]));
const $ = sel => document.querySelector(sel);

const MARK = {
  y: { glyph: "✓", cls: "mk--y", label: "Yes" },
  n: { glyph: "✗", cls: "mk--n", label: "No" },
  p: { glyph: "◐", cls: "mk--p", label: "Partly" },
  "?": { glyph: "?", cls: "mk--q", label: "Unconfirmed" }
};

let selected = [];

function esc(s) {
  return String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

function readURL() {
  const q = new URLSearchParams(location.search);
  const vs = (q.get("vs") || "").split(",").map(s => s.trim().toLowerCase()).filter(s => byId[s]);
  selected = (vs.length ? vs : [DEFAULT]).slice(0, MAX_COLS);
}

function writeURL(replace) {
  const url = location.pathname + (selected.length ? "?vs=" + selected.join(",") : "");
  history[replace ? "replaceState" : "pushState"]({}, "", url);
}

function primary() { return byId[selected[0]]; }

function nameList(ids) {
  const names = ids.map(id => byId[id].name);
  if (names.length <= 1) return names.join("");
  return names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
}

function markHTML(v, note) {
  const m = MARK[v] || MARK["?"];
  const t = note ? ` title="${esc(note)}"` : "";
  return `<span class="mk ${m.cls}"${t} role="img" aria-label="${m.label}${note ? ". " + esc(note) : ""}">${m.glyph}</span>`;
}

/* ---- picker ---------------------------------------------------------- */
function renderChips() {
  $("#chips").innerHTML = competitors.map(c => {
    const i = selected.indexOf(c.id);
    const cls = i === 0 ? "chip-wrap is-on is-primary" : i > 0 ? "chip-wrap is-on" : "chip-wrap";
    const verb = i === 0 ? "Currently the subject of this article"
      : i > 0 ? `Make Atlas vs. ${c.name} the subject of this article`
      : `Compare Atlas with ${c.name}`;
    return `<span class="${cls}">` +
      `<button class="chip" type="button" data-pick="${c.id}" aria-pressed="${i > -1}" title="${esc(verb)}">${esc(c.name)}</button>` +
      (i > -1 ? `<button class="chip__x" type="button" data-drop="${c.id}" aria-label="Remove ${esc(c.name)} from the table">×</button>` : "") +
      `</span>`;
  }).join("");

  const p = primary();
  $("#picker-hint").textContent = selected.length > 1
    ? `Up to three at a time. The write-up below is Atlas vs. ${p.name} — click another selected app to make it the subject.`
    : `Pick one to read the full write-up, or add up to two more for extra columns in the table.`;
}

/* ---- table ----------------------------------------------------------- */
function renderTable() {
  const cols = selected.map(id => byId[id]);

  const head = `<thead><tr>
    <th class="col-crit" scope="col">Question</th>
    <th class="col-atlas" scope="col">Atlas</th>
    ${cols.map(c => `<th scope="col"><a href="${esc(c.url)}" target="_blank" rel="noopener nofollow">${esc(c.name)}</a></th>`).join("")}
  </tr></thead>`;

  const body = rows.map(r => {
    const cell = (v, isAtlas) => r.id === "price"
      ? `<td class="price-cell${isAtlas ? " col-atlas" : ""}">${esc(v)}</td>`
      : `<td class="mark${isAtlas ? " col-atlas" : ""}">${markHTML(v, isAtlas ? r.note : null)}</td>`;
    return `<tr>
      <th class="crit-label" scope="row">${esc(r.label)}</th>
      ${cell(r.atlas, true)}
      ${cols.map(c => cell(c.cells[r.id] || "?", false)).join("")}
    </tr>`;
  }).join("");

  $("#grid").innerHTML = head + `<tbody>${body}</tbody>`;
  $("#glance-h").textContent = `Atlas vs. ${nameList(selected)} at a glance`;
}

function yesCount(get) {
  return rows.filter(r => r.id !== "price" && get(r) === "y").length;
}

function renderTally() {
  const n = rows.length - 1;
  const parts = selected.map(id => `${byId[id].name} answers yes to ${yesCount(r => byId[id].cells[r.id])}`);
  $("#tally").textContent =
    `Across the ${n} yes/no questions above, Atlas answers yes to ${yesCount(r => r.atlas)}. ` +
    parts.join("; ") + ". A ◐ counts as neither.";
}

/* ---- article --------------------------------------------------------- */
function renderArticle() {
  const c = primary();
  const a = c.prose;

  $("#headline").textContent = `Atlas vs. ${c.name}: which should you use?`;
  $("#dek").textContent = a.dek;
  const framing = `This page sets Atlas beside ${c.name} for people juggling classes, deadlines and the rest of life, mostly on a Mac and an iPhone. ` +
    `Each row in the table was checked against the two products\u2019 own documentation, and each section below says plainly which one is the better pick.`;
  $("#intro").innerHTML = `<p>${esc(framing)}</p>` + a.intro.map(p => `<p>${esc(p)}</p>`).join("");

  const words = (a.intro.join(" ") + a.sections.map(s => s.verdict + s.body.join(" ")).join(" ") +
    a.bottom.join(" ") + a.faq.map(f => f.q + f.a).join(" ")).split(/\s+/).length;
  $("#readtime").textContent = `${Math.max(3, Math.round(words / 220))} min read`;

  $("#sections").innerHTML =
    a.sections.map(s => `<section>
      <h2>${esc(s.title)}</h2>
      <strong class="verdict">${esc(s.verdict)}</strong>
      ${s.body.map(p => `<p>${esc(p)}</p>`).join("")}
    </section>`).join("") +
    `<section class="bottom-line">
      <h2>The bottom line</h2>
      ${a.bottom.map(p => `<p>${esc(p)}</p>`).join("")}
      <a class="prose__link" href="${esc(c.url)}" target="_blank" rel="noopener nofollow">${esc(c.name)}’s own site →</a>
    </section>`;

  $("#faq-h").textContent = `Atlas vs. ${c.name}: frequently asked questions`;
  $("#faq-body").innerHTML = a.faq.map(f => `<div class="faq__item">
    <h3 class="faq__q">${esc(f.q)}</h3>
    <p class="faq__a">${esc(f.a)}</p>
  </div>`).join("");

  $("#cta-line").textContent =
    `Atlas is free. The Mac app downloads in a few seconds, the iPhone and iPad apps come with it, and your Apple, Google and Canvas calendars land on one timeline from the first launch.`;

  renderFaqSchema(c, a);
}

function renderFaqSchema(c, a) {
  let el = document.getElementById("faq-schema");
  if (!el) {
    el = document.createElement("script");
    el.type = "application/ld+json";
    el.id = "faq-schema";
    document.head.appendChild(el);
  }
  el.textContent = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: a.faq.map(f => ({
      "@type": "Question",
      name: f.q,
      acceptedAnswer: { "@type": "Answer", text: f.a }
    }))
  });
}

/* ---- sources --------------------------------------------------------- */
function renderSources() {
  $("#sources-body").innerHTML =
    `<p>Every mark in the competitor columns was checked against that company’s own website, help documentation, App Store listing or pricing page on <strong>${CHECKED_ON}</strong>. Prices are the vendor’s headline figure, per user per month on annual billing unless noted, in US dollars. Products in this category change quickly; if something here is out of date, email <a href="mailto:drewkhalil@gmail.com">drewkhalil@gmail.com</a> and it will be corrected.</p>` +
    `<p>Two judgment calls are worth declaring, because they are readings rather than vendor claims. <strong>“Works on Mac”</strong> is marked ◐ where the desktop app is a cross-platform build wrapped for macOS rather than one written for it; almost no vendor states which it ships, so that reading comes from install size, release channels and developer notes. <strong>“Syncs both ways with Apple Calendar”</strong> requires that edits made in the app are written back to iCloud; apps that only read your Apple calendars are marked ◐.</p>` +
    `<p>The Atlas column describes the shipping Mac, iPhone and iPad apps on the same date. Where a plain ✓ would need qualifying, the mark carries a footnote — hover it in the table, or read them here:</p>` +
    `<div class="src"><span class="src__name">Atlas footnotes</span><ul>` +
    rows.filter(r => r.note).map(r => `<li style="width:100%">${esc(r.label)} — ${esc(r.note)}</li>`).join("") +
    `</ul></div>` +
    competitors.map(c => `<div class="src">
      <span class="src__name">${esc(c.name)}</span> — ${esc(c.tagline)}
      <ul>${c.sources.map(u => `<li><a href="${esc(u)}" target="_blank" rel="noopener nofollow">${esc(u)}</a></li>`).join("")}</ul>
    </div>`).join("");
}

/* ---- glue ------------------------------------------------------------ */
function renderTitle() {
  const c = primary();
  document.title = `Atlas vs. ${c.name}: which should you use?`;
  const d = document.querySelector('meta[name="description"]');
  if (d) d.setAttribute("content",
    `A side-by-side look at Atlas and ${c.name} — calendars, capture, school, notes, platforms and price — with an at-a-glance table and an FAQ. Updated ${CHECKED_ON}.`);
}

function checkOverflow() {
  const el = $("#table-scroll");
  el.dataset.overflow = el.scrollWidth > el.clientWidth + 4 ? "true" : "false";
}

function renderAll(replaceURL) {
  if (!selected.length) selected = [DEFAULT];
  renderChips();
  renderTable();
  renderTally();
  renderArticle();
  renderTitle();
  writeURL(replaceURL);
  checkOverflow();
}

document.addEventListener("click", e => {
  const drop = e.target.closest("[data-drop]");
  if (drop) {
    const id = drop.dataset.drop;
    if (selected.length > 1) selected = selected.filter(x => x !== id);
    renderAll(false);
    return;
  }
  const pick = e.target.closest("[data-pick]");
  if (pick) {
    const id = pick.dataset.pick;
    if (selected[0] === id) return;
    if (selected.includes(id)) selected = [id].concat(selected.filter(x => x !== id));
    else selected = selected.length >= MAX_COLS ? selected.slice(0, MAX_COLS - 1).concat(id) : selected.concat(id);
    renderAll(false);
  }
});

window.addEventListener("popstate", () => { readURL(); renderAll(true); });
window.addEventListener("resize", checkOverflow);

readURL();
renderSources();
renderAll(true);
