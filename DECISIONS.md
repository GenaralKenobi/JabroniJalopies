# Decisions to review

These are choices I made without being sure they match how you work. Each one is easy to change. Reply with the numbers you'd like handled differently.

## Repeating checklist items and scheduled checklists

1. **Weekly items reset every Monday** (changed at your request). An item done on Saturday is due again two days later, on Monday. Weeks start on Monday on every phone, whatever its region setting.
2. **An item counts as done whether it passed or failed** (confirmed by you). A failed item becomes a defect, and the defect tracks the problem from there.
3. **Drivers can skip due weekly items** (changed at your request). A skipped item isn't recorded as done, so it shows on every checklist for that truck until someone does it, with "due since" and its date. Every-time items are still required. A checklist can't be submitted with nothing answered.
4. **Items that aren't due are hidden, but can be done early** (confirmed by you). They're listed under "Not due yet" with a **Do Now** button.
5. **A repeating item with an open defect always appears**, even if it isn't due, so drivers can mark it "still a problem" or "looks fixed".
6. **Schedules are tracked per truck, not per driver.** If anyone did the weekly check on Van 12 this week, nobody needs to do it again on Van 12 until next Monday.
7. **3 skips in a row means overdue** (your request). The count is per truck and per item, and it only counts checklists where the item was due and left blank. Doing the item, pass or fail, resets it. Managers get one alert per streak, and everyone sees an "Overdue" tag on the truck and the item.
8. **Monthly and every-N-days work is now a scheduled checklist** (your choice). Per-item "Monthly" and "Every N days" are no longer offered for new items; existing ones keep working as before until you move them. Scheduled checklists can't contain weekly items.
9. **A scheduled checklist is due one month (or N days) after it was last done on that truck** (your choice). A truck that has never done it is due on the checklist's **first due date**, which defaults to two weeks after the schedule is set. A truck added later is due straight away if that date has passed.
10. **Managers are alerted 14 days before the due date, at 9 AM**, once per truck and due date, unless a day is already planned. If the schedule is set less than 14 days before the due date, the alert comes straight away. These are notifications on the manager's own phone, worked out from the fleet data the phone has; nothing is sent from a server, so a manager who hasn't opened the app in a while gets the alert the next time they do.
11. **Planning a day** (your choice): a manager picks a date per truck from the Upcoming tab or the truck page. It's shown to managers. Drivers can start a scheduled checklist any time from Start Checklist, but it's only highlighted to them once it's overdue. A plan applies to that due date only; once the checklist is done, the next due date has no plan.
12. **Overdue means past the due date, even if a day was planned later.** Planning a date after the due date is allowed, and the app warns that drivers will see it as overdue from the due date.
13. **Calendar: planning a day offers "Add to My Calendar"** (your request). After saving, the phone's own New Event screen opens, filled in: an all-day event on the planned day named after the checklist and truck, with a 7 AM alert. The manager picks which calendar (iCloud, Google, Outlook, a shared work calendar) and taps Add. The app doesn't ask for access to read the calendar, so **it can't move or delete that event later**: if the planned day changes, the manager is offered a new event and removes the old one themselves. The toggle is remembered. With full calendar access instead, I could keep events in step automatically.
14. **Drivers aren't sent a notification when something becomes overdue**; they see the orange "Overdue" tag on the fleet list and the truck page. I can add a notification for drivers too.

## Chainsaws, ropes and chains

15. **Anyone can mark a saw "Do not use".** You said only managers can do this for ropes. I kept it open to everyone for saws, because a saw with a failed chain brake is an immediate safety issue.
16. **Equipment problems show in two places:**
    - a badge on the truck in the fleet list
    - a coloured banner at the top of the truck's page

    You left this choice to me.
17. **Chain counts can go below zero and show as they are** (changed at your request). For example, -2 means chains were probably added on a phone that hasn't synced yet. The truck shows an orange note, and the fleet totals include the negative number.
18. **A manager's count is final** (your request). **Correct Counts** sets each size to exactly what the manager counted, and records who counted and when. Any used-box or added log made *before* that moment, still waiting to sync on someone's phone, is saved in the history but doesn't change the count; that person sees a note saying so. Logs made after the count apply as normal. Saving Correct Counts without changing anything still marks the chains as counted. One limit: if the manager's own phone is offline when they count, logs others make between the count and the manager's phone syncing are overwritten by the count.
19. **Chains aren't tracked while they're out for sharpening.** Dull chains leave the truck's count. Chains coming back go in through **Add Chains** on any truck. The fleet totals show how many were logged dull (to resharpen) over the period, but there's no running count of "currently at the sharpener".
20. **Chain sizes are whole or decimal inches**, such as 16, 18 or 20.5. A manager types them as a list. They can be filled in from the bar lengths of the saws on that truck.
21. **Ropes record:** a name or number, diameter, length in feet, an optional minimum length, serial number and notes. A rope below its minimum length shows a warning; it isn't automatically marked "Do not use".
22. **Removing a saw or rope deletes its history.** Moving it keeps the history. Managers see a warning before removing.
23. **Only managers add, edit or remove saws and ropes.** Drivers can report problems and submit rope length reductions.

## From earlier

24. **Defect photos are switched on per fleet** with Settings → Defect Photos. They need Firebase's pay-as-you-go plan.
25. **Records are deleted automatically 5 years after they're created.** Defects are deleted 5 years after they're closed.
26. **Managers get notifications only for maintenance reminders, storage warnings, scheduled checklists coming due and items skipped 3 times.** These are local notifications on the manager's own phone. A server-sent alert when a driver reports a defect needs Firebase's pay-as-you-go plan plus an Apple push key, so it isn't built yet.

## From the full review

27. **The distance unit (miles or kilometres) is a fleet setting.** It used to be per phone, which meant two drivers could enter odometer readings in different units on the same truck. Now a manager sets it once under Settings → Fleet Settings, and everyone's phone follows it. Changing it doesn't convert readings already entered.
28. **There's a daily checklist reminder, off by default.** A manager can turn it on and pick a time under Settings → Fleet Settings. Every member's phone then shows "Complete today's checklist" at that time, on the days of the week the manager picks.
29. **Each truck shows when its last checklist was done.**
    - The fleet list shows "Checked today" or "Not checked today".
    - The truck page shows "Last checklist today at 6:12 AM by Dan".

    Several checklists a day on the same truck are still allowed; nothing blocks a second one.
30. **Managers can change the safety flag on any defect, either way.** That includes a truck's "Unsafe to drive", so a driver's mistaken flag can be cleared without closing the defect.
31. **Managers can correct a rope's length directly** in its edit screen, for example after replacing the rope. Drivers still go through approval.
32. **Signing out checks for unsynced work first.** If checklists done offline or photos haven't uploaded yet, the app warns that signing out will lose them and suggests waiting for signal. If you sign out anyway, waiting photos are deleted from the phone, so the next person to sign in can't see them.
33. **A manager closing a defect doesn't lose an offline checklist.** If a driver offline marks a defect "still a problem" while a manager closes it, the checklist is still saved and the driver is told to report the problem again if it's still there. The app doesn't reopen the closed defect or create a new one automatically.

## What's on the truck

34. **The truck lead can edit only that truck's contents list.** I read "set up that vehicle as his" as the contents list. The lead can't edit the truck's specs, details, checklists or anything else. I can let the lead edit the specs card too.
35. **One lead per truck, and only a driver.** Managers can already edit every truck's list. A driver can be lead of more than one truck.
36. **Picking a lead who can't see that truck gives them access to it.** If a driver only sees their assigned trucks, making them lead also adds the truck to their assigned trucks. Removing them as lead doesn't take that access away; a manager does that in Members.
37. **Each item has a name, an optional quantity, a location and notes.** Items are grouped by location, such as "Cab" or "Left side box", with unplaced items under "Other". There's no expiry date or "last checked" date, and the contents aren't part of the morning checklist. I can add a "check the truck contents" checklist item, or expiry dates for things like first-aid kits and extinguishers.
38. **Contents changes aren't kept as history.** The list shows what's on the truck now, and each item remembers who last changed it. Removing an item deletes it.
39. **Copy from Another Truck adds only missing items.** It skips items with the same name and location that are already on the list, and never changes or removes anything.

## From your latest answers

40. **Managers can still see email addresses and phone numbers; drivers can't.** You asked for these not to be visible. I read that as "not visible to other drivers", because managers invite people by email and may need to call them. Drivers see only names and roles. This is enforced by the server, not just hidden in the app. If managers shouldn't see them either, I'll hide them completely.
41. **The checklist reminder starts as Monday–Friday** when a manager turns it on. They can tap any days of the week to change that.
42. **Jabroni Jalopies and Tailgate Labs.** A web search found no app, business or trademark called "Jabroni Jalopies", and earlier checks found no company called Tailgate Labs. That check is not legal clearance. The App Store confirms whether an app name is free when you create the app record.
43. **The home screen label is "Jalopies"**, as you asked. The App Store name, the sign-in screen and Settings all still say "Jabroni Jalopies". Apple asks that the home screen name be close to the App Store name so people can find the app. "Jalopies" is part of the full name, so it should be fine; if App Review objects, I'll switch it back to the full name.
