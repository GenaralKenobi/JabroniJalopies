# Decisions to review

These are choices I made without being sure they match how you work. Each one is easy to change. Reply with the numbers you'd like handled differently.

## Repeating checklist items (weekly / monthly / every N days)

1. **Weekly and monthly items follow the calendar** (changed at your request).
   - Weekly items reset every **Monday**. An item done on Saturday is due again two days later, on Monday.
   - Monthly items reset on the **1st** of each month.
   - Weeks start on Monday on every phone, whatever its region setting, so the whole fleet agrees.
   - **"Every N days" items still count from when they were last done**, because they don't match a calendar period. Tell me if you'd rather they reset on fixed dates.
2. **An item counts as done whether it passed or failed** (confirmed by you). A failed item becomes a defect, and the defect tracks the problem from there.
3. **Due repeating items are required.** When a weekly item is due, it has to be answered pass or fail like every other item before the checklist can be submitted. The alternative is letting drivers skip it and keep it due.
4. **Items that aren't due are hidden, but can be done early.** They're listed under "Not due yet" with a **Do Now** button. Doing one again counts for the current week or month, so a weekly item done again is still due next Monday. An "every N days" item done early starts its N days again.
5. **A repeating item with an open defect always appears**, even if it isn't due, so drivers can mark it "still a problem" or "looks fixed".
6. **The schedule is tracked per truck, not per driver.** If anyone did the weekly check on Van 12 this week, nobody needs to do it again on Van 12 until next week.
7. **The schedule belongs to the item in each checklist.** If two checklists both contain "Grease fittings", each one tracks its own schedule.
8. **Managers don't get alerts for overdue items.** Overdue items show up when the next checklist on that truck is started, and the truck page shows "Includes N weekly/monthly items". There's no separate manager alert or report for repeating items that haven't been done. I can add one.

## Chainsaws, ropes and chains

9. **Anyone can mark a saw "Do not use".** You said only managers can do this for ropes. I kept it open to everyone for saws, because a saw with a failed chain brake is an immediate safety issue.
10. **Equipment problems show in two places:**
    - a badge on the truck in the fleet list
    - a coloured banner at the top of the truck's page

    You left this choice to me.
11. **Chain counts can go negative, and the app shows that as 0.** If more chains are logged out than the truck shows, the log is still saved, the count is flagged, and a manager uses **Correct Counts**. Corrections are applied as adjustments, so logs still syncing from other phones aren't lost.
12. **Chains aren't tracked while they're out for sharpening.** Dull chains leave the truck's count. Chains coming back go in through **Add Chains** on any truck. The fleet totals show how many were logged dull (to resharpen) over the period, but there's no running count of "currently at the sharpener".
13. **Chain sizes are whole or decimal inches**, such as 16, 18 or 20.5. A manager types them as a list. They can be filled in from the bar lengths of the saws on that truck.
14. **Ropes record:** a name or number, diameter, length in feet, an optional minimum length, serial number and notes. A rope below its minimum length shows a warning; it isn't automatically marked "Do not use".
15. **Removing a saw or rope deletes its history.** Moving it keeps the history. Managers see a warning before removing.
16. **Only managers add, edit or remove saws and ropes.** Drivers can report problems and submit rope length reductions.

## From earlier

17. **Defect photos are switched on per fleet** with Settings → Defect Photos. They need Firebase's pay-as-you-go plan.
18. **Records are deleted automatically 5 years after they're created.** Defects are deleted 5 years after they're closed.
19. **Managers get push notifications only for maintenance reminders and storage warnings.** These are local notifications on the manager's own phone. A server-sent alert when a driver reports a defect needs Firebase's pay-as-you-go plan plus an Apple push key, so it isn't built yet.

## From the full review

20. **The distance unit (miles or kilometres) is a fleet setting.** It used to be per phone, which meant two drivers could enter odometer readings in different units on the same truck. Now a manager sets it once under Settings → Fleet Settings, and everyone's phone follows it. Changing it doesn't convert readings already entered.
21. **There's a daily checklist reminder, off by default.** A manager can turn it on and pick a time under Settings → Fleet Settings. Every member's phone then shows "Complete today's checklist" at that time, **every day including weekends**. Should it be weekdays only, or per driver?
22. **Each truck shows when its last checklist was done.**
    - The fleet list shows "Checked today" or "Not checked today".
    - The truck page shows "Last checklist today at 6:12 AM by Dan".

    Several checklists a day on the same truck are still allowed; nothing blocks a second one.
23. **Managers can change the safety flag on any defect, either way.** That includes a truck's "Unsafe to drive", so a driver's mistaken flag can be cleared without closing the defect.
24. **Managers can correct a rope's length directly** in its edit screen, for example after replacing the rope. Drivers still go through approval.
25. **Signing out checks for unsynced work first.** If checklists done offline or photos haven't uploaded yet, the app warns that signing out will lose them and suggests waiting for signal. If you sign out anyway, waiting photos are deleted from the phone, so the next person to sign in can't see them.
26. **A manager closing a defect doesn't lose an offline checklist.** If a driver offline marks a defect "still a problem" while a manager closes it, the checklist is still saved and the driver is told to report the problem again if it's still there. The app doesn't reopen the closed defect or create a new one automatically.

## What's on the truck

31. **The truck lead can edit only that truck's contents list.** I read "set up that vehicle as his" as the contents list. The lead can't edit the truck's specs, details, checklists or anything else. I can let the lead edit the specs card too.
32. **One lead per truck, and only a driver.** Managers can already edit every truck's list. A driver can be lead of more than one truck.
33. **Picking a lead who can't see that truck gives them access to it.** If a driver only sees their assigned trucks, making them lead also adds the truck to their assigned trucks. Removing them as lead doesn't take that access away; a manager does that in Members.
34. **Each item has a name, an optional quantity, a location and notes.** Items are grouped by location, such as "Cab" or "Left side box", with unplaced items under "Other". There's no expiry date or "last checked" date, and the contents aren't part of the morning checklist. I can add a "check the truck contents" checklist item, or expiry dates for things like first-aid kits and extinguishers.
35. **Contents changes aren't kept as history.** The list shows what's on the truck now, and each item remembers who last changed it. Removing an item deletes it.
36. **Copy from Another Truck adds only missing items.** It skips items with the same name and location that are already on the list, and never changes or removes anything.

## From your latest answers

27. **Managers can still see email addresses and phone numbers; drivers can't.** You asked for these not to be visible. I read that as "not visible to other drivers", because managers invite people by email and may need to call them. Drivers see only names and roles. This is enforced by the server, not just hidden in the app. If managers shouldn't see them either, I'll hide them completely.
28. **The checklist reminder starts as Monday–Friday** when a manager turns it on. They can tap any days of the week to change that.
29. **Jabroni Jalopies and Tailgate Labs.** A web search found no app, business or trademark called "Jabroni Jalopies", and earlier checks found no company called Tailgate Labs. That check is not legal clearance. The App Store confirms whether an app name is free when you create the app record.
30. **The home screen label is "Jalopies"**, as you asked. The App Store name, the sign-in screen and Settings all still say "Jabroni Jalopies". Apple asks that the home screen name be close to the App Store name so people can find the app. "Jalopies" is part of the full name, so it should be fine; if App Review objects, I'll switch it back to the full name.
