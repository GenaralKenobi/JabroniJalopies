# Decisions to review

**How to read this page:**
- ✅ means you've reviewed it and it's fine.
- 🆕 means it's new and needs your review. New decisions go in the section at the top, and I'll move them down and mark them ✅ once you've looked at them.

If something isn't right, reply with its number.

## 🆕 New decisions

55. 🆕 **A "Pass N Routine Items" button on checklists** (my suggestion, easy to remove). It passes every routine item the driver hasn't answered in one tap, so a clean truck takes seconds. It deliberately leaves **safety items, items that need a number, items with an open problem, and optional weekly items** for a deliberate answer, and any answer can still be changed. It only appears when there's more than one such item. Tell me if you'd rather drivers answer every item individually.
56. 🆕 **Light haptic taps** when a driver taps Pass or Fail (a firmer one for Fail) and when they pass the routine items in one go.
57. 🆕 **On iPad, the main lists are kept to a comfortable reading width** (about 720 points, centred) instead of stretching across the whole screen. It only affects wide screens.
58. 🆕 **The app asks for notification permission the first time a manager has an alert to receive**, such as a scheduled checklist coming due or storage getting full. Before this, a manager who only used scheduled checklists would never have been asked, and their alerts would have been silently lost. Managers can still say no, and it can be changed in iPhone Settings.
59. 🆕 **Screens keep a truck's details loaded for about 20 seconds after you leave them.** Going into a truck's chains or specs and coming back no longer blinks or re-downloads. It adds no real cost.

## Hours, and checklists due by reading

47. ✅ **Hours are chosen per vehicle** (your choice). Edit Vehicle → **Reading** sets a vehicle to miles, kilometres or hours. It then shows "Hour meter", "Update Hour meter" and "hr" everywhere: the fleet list, service history, reminders and checklists. The fleet-wide setting stays miles or kilometres for everything else. Changing a vehicle's unit doesn't convert readings already entered.
48. ✅ **Maintenance reminders already work by reading**, so a reminder like "oil change every 250 hours" works for hour-based vehicles without anything new. The app suggests no hour intervals (they depend on the machine), so the manager types them.
49. ✅ **A checklist can be due every N hours (or miles / km)** (your choice, same as the monthly ones). In the checklist editor, choose Schedule → **Every … hours / miles** and type the number. It's due that many hours after the reading when it was last done on that vehicle. A vehicle that has never done it is due at the next multiple of the number (a chipper at 1,180 hours with a 250-hour service is due at 1,250).
50. ✅ **Managers are alerted when a vehicle gets within a tenth of the interval** (your choice): 25 hours early for a 250-hour service, 500 miles early for 5,000 miles. The alert is a notification on the manager's phone, sent the next time that phone sees the new reading, so it depends on someone updating the hour meter. Once per due reading, and not sent if a manager has already planned a day.
51. ✅ **Once the reading passes the due reading, the vehicle shows Overdue** on the fleet list and its page, and drivers see the checklist tagged the same way, as with monthly ones. Managers can still plan a day (it's only a reminder and a calendar event). The vehicle's reading decides when it's overdue, not the date.
52. ✅ **The interval is in each vehicle's own unit.** A 250 checklist means 250 hours on a chipper and 250 miles on a truck, so use **Used For** to give it only vehicles that share a unit. A mixed checklist works, but the number won't mean the same thing on each.
53. ✅ **What counts as the reading when a checklist is done** is the higher of the number typed on the checklist and the vehicle's last recorded reading. If nobody updates the hour meter, the next due reading doesn't move, so drivers need to enter the reading on the checklist.
54. ✅ **A checklist is either dated (monthly, every N days) or reading-based, not both.** If you want both, such as "every 250 hours or every 6 months, whichever comes first", say so and I'll add it.

## Repeating checklist items and scheduled checklists

1. ✅ **Weekly items reset every Monday** (changed at your request). An item done on Saturday is due again two days later, on Monday. Weeks start on Monday on every phone, whatever its region setting.
2. ✅ **An item counts as done whether it passed or failed** (confirmed by you). A failed item becomes a defect, and the defect tracks the problem from there.
3. ✅ **Drivers can skip due weekly items** (changed at your request). A skipped item isn't recorded as done, so it shows on every checklist for that truck until someone does it, with "due since" and its date. Every-time items are still required. A checklist can't be submitted with nothing answered.
4. ✅ **Items that aren't due are hidden, but can be done early** (confirmed by you). They're listed under "Not due yet" with a **Do Now** button.
5. ✅ **A repeating item with an open defect always appears**, even if it isn't due, so drivers can mark it "still a problem" or "looks fixed".
6. ✅ **Schedules are tracked per truck, not per driver.** If anyone did the weekly check on Van 12 this week, nobody needs to do it again on Van 12 until next Monday.
7. ✅ **3 skips in a row means overdue** (your request). The count is per truck and per item, and it only counts checklists where the item was due and left blank. Doing the item, pass or fail, resets it. Managers get one alert per streak, and everyone sees an "Overdue" tag on the truck and the item.
8. ✅ **Monthly and every-N-days work is now a scheduled checklist** (your choice). Per-item "Monthly" and "Every N days" are no longer offered for new items; existing ones keep working as before until you move them. Scheduled checklists can't contain weekly items.
9. ✅ **A scheduled checklist is due one month (or N days) after it was last done on that truck** (your choice). A truck that has never done it is due on the checklist's **first due date**, which defaults to two weeks after the schedule is set. A truck added later is due straight away if that date has passed.
10. ✅ **Managers are alerted 14 days before the due date, at 9 AM**, once per truck and due date, unless a day is already planned. If the schedule is set less than 14 days before the due date, the alert comes straight away. These are notifications on the manager's own phone, worked out from the fleet data the phone has; nothing is sent from a server, so a manager who hasn't opened the app in a while gets the alert the next time they do.
11. ✅ **Planning a day** (your choice): a manager picks a date per truck from the Upcoming tab or the truck page. It's shown to managers. Drivers can start a scheduled checklist any time from Start Checklist, but it's only highlighted to them once it's overdue. A plan applies to that due date only; once the checklist is done, the next due date has no plan.
12. ✅ **Overdue means past the due date, even if a day was planned later.** Planning a date after the due date is allowed, and the app warns that drivers will see it as overdue from the due date.
13. ✅ **Calendar: planning a day offers "Add to My Calendar"** (your request). After saving, the phone's own New Event screen opens, filled in: an all-day event on the planned day named after the checklist and truck, with a 7 AM alert. The manager picks which calendar (iCloud, Google, Outlook, a shared work calendar) and taps Add. The app doesn't ask for access to read the calendar, so **it can't move or delete that event later**: if the planned day changes, the manager is offered a new event and removes the old one themselves. The toggle is remembered. With full calendar access instead, I could keep events in step automatically.
14. ✅ **Drivers aren't sent a notification when something becomes overdue**; they see the orange "Overdue" tag on the fleet list and the truck page. I can add a notification for drivers too.

## Chainsaws, ropes and chains

15. ✅ **Anyone can mark a saw "Do not use".** You said only managers can do this for ropes. I kept it open to everyone for saws, because a saw with a failed chain brake is an immediate safety issue.
16. ✅ **Equipment problems show in two places:**
    - a badge on the truck in the fleet list
    - a coloured banner at the top of the truck's page

    You left this choice to me.
17. ✅ **Chain counts can go below zero and show as they are** (changed at your request). For example, -2 means chains were probably added on a phone that hasn't synced yet. The truck shows an orange note, and the fleet totals include the negative number.
18. ✅ **A manager's count is the new starting point** (your request). **Correct Counts** sets each size to what the manager counted and records who counted and when. Every used-box or added log made *after* that moment is added on top, in whatever order the phones sync, even if the manager's own phone was offline when they counted. Logs made *before* the count are kept in the history but left out of the count, with no message to anyone. Saving Correct Counts without changing anything still marks the chains as counted. Times come from each phone's clock, so a phone with the wrong time could land on the wrong side of a count.
19. ✅ **Chains aren't tracked while they're out for sharpening.** Dull chains leave the truck's count. Chains coming back go in through **Add Chains** on any truck. The fleet totals show how many were logged dull (to resharpen) over the period, but there's no running count of "currently at the sharpener".
20. ✅ **Chain sizes are whole or decimal inches**, such as 16, 18 or 20.5. A manager types them as a list. They can be filled in from the bar lengths of the saws on that truck.
21. ✅ **Ropes record:** a name or number, diameter, length in feet, an optional minimum length, serial number and notes. A rope below its minimum length shows a warning; it isn't automatically marked "Do not use".
22. ✅ **Removing a saw or rope deletes its history.** Moving it keeps the history. Managers see a warning before removing.
23. ✅ **Only managers add, edit or remove saws and ropes.** Drivers can report problems and submit rope length reductions.

## From earlier

24. ✅ **Defect photos are switched on per fleet** with Settings → Defect Photos. They need Firebase's pay-as-you-go plan.
25. ✅ **Records are deleted automatically 5 years after they're created.** Defects are deleted 5 years after they're closed.
26. ✅ **Managers get notifications only for maintenance reminders, storage warnings, scheduled checklists coming due and items skipped 3 times.** These are local notifications on the manager's own phone. A server-sent alert when a driver reports a defect needs Firebase's pay-as-you-go plan plus an Apple push key, so it isn't built yet.

## From the full review

27. ✅ **The distance unit (miles or kilometres) is a fleet setting.** It used to be per phone, which meant two drivers could enter odometer readings in different units on the same truck. Now a manager sets it once under Settings → Fleet Settings, and everyone's phone follows it. Changing it doesn't convert readings already entered.
28. ✅ **There's a daily checklist reminder, off by default.** A manager can turn it on and pick a time under Settings → Fleet Settings. Every member's phone then shows "Complete today's checklist" at that time, on the days of the week the manager picks.
29. ✅ **Each truck shows when its last checklist was done.**
    - The fleet list shows "Checked today" or "Not checked today".
    - The truck page shows "Last checklist today at 6:12 AM by Dan".

    Several checklists a day on the same truck are still allowed; nothing blocks a second one.
30. ✅ **Managers can change the safety flag on any defect, either way.** That includes a truck's "Unsafe to drive", so a driver's mistaken flag can be cleared without closing the defect.
31. ✅ **Managers can correct a rope's length directly** in its edit screen, for example after replacing the rope. Drivers still go through approval.
32. ✅ **Signing out checks for unsynced work first.** If checklists done offline or photos haven't uploaded yet, the app warns that signing out will lose them and suggests waiting for signal. If you sign out anyway, waiting photos are deleted from the phone, so the next person to sign in can't see them.
33. ✅ **A manager closing a defect doesn't lose an offline checklist.** If a driver offline marks a defect "still a problem" while a manager closes it, the checklist is still saved and the driver is told to report the problem again if it's still there. The app doesn't reopen the closed defect or create a new one automatically.

## What's on the truck

34. ✅ **The truck lead can edit only that truck's contents list.** I read "set up that vehicle as his" as the contents list. The lead can't edit the truck's specs, details, checklists or anything else. I can let the lead edit the specs card too.
35. ✅ **One lead per truck, and only a driver.** Managers can already edit every truck's list. A driver can be lead of more than one truck.
36. ✅ **Picking a lead who can't see that truck gives them access to it.** If a driver only sees their assigned trucks, making them lead also adds the truck to their assigned trucks. Removing them as lead doesn't take that access away; a manager does that in Members.
37. ✅ **Each item has a name, an optional quantity, a location and notes.** Items are grouped by location, such as "Cab" or "Left side box", with unplaced items under "Other". There's no expiry date or "last checked" date, and the contents aren't part of the morning checklist. I can add a "check the truck contents" checklist item, or expiry dates for things like first-aid kits and extinguishers.
38. ✅ **Contents changes aren't kept as history.** The list shows what's on the truck now, and each item remembers who last changed it. Removing an item deletes it.
39. ✅ **Copy from Another Truck adds only missing items.** It skips items with the same name and location that are already on the list, and never changes or removes anything.

## From your latest answers

40. ✅ **Managers can still see email addresses and phone numbers; drivers can't.** You asked for these not to be visible. I read that as "not visible to other drivers", because managers invite people by email and may need to call them. Drivers see only names and roles. This is enforced by the server, not just hidden in the app. If managers shouldn't see them either, I'll hide them completely.
41. ✅ **The checklist reminder starts as Monday–Friday** when a manager turns it on. They can tap any days of the week to change that.
42. ✅ **Jabroni Jalopies and Tailgate Labs.** A web search found no app, business or trademark called "Jabroni Jalopies", and earlier checks found no company called Tailgate Labs. That check is not legal clearance. The App Store confirms whether an app name is free when you create the app record.
43. ✅ **The home screen label is "Jalopies"**, as you asked. The App Store name, the sign-in screen and Settings all still say "Jabroni Jalopies". Apple asks that the home screen name be close to the App Store name so people can find the app. "Jalopies" is part of the full name, so it should be fine; if App Review objects, I'll switch it back to the full name.

## Keeping costs down

44. ✅ **Each truck (and each saw and rope) carries a small summary**, so the fleet list loads one record per truck. The summary holds open and unsafe defect counts, services waiting for sign-off, the next maintenance due date and odometer, and when the last checklist was done and by whom. A truck's full details load only while its page is open. The Upcoming tab, chain totals and the member list load only while they're on screen. For drivers, the Defects tab loads only trucks that have open defects. **Managers' phones still load every truck's defects, reminders and pending services**, because they need them for alerts and because it lets their phones keep every summary correct. Managers are usually a small share of users.
45. ✅ **Anyone who can see a truck can update its summary.** That's needed so a driver's phone can record a new defect, even offline. A driver could in theory edit the summary by hand, but the defect records themselves are protected. The next time a manager's phone loads that truck, it checks the summary against those records and corrects it.
46. ✅ **Drivers load only their own profile**, plus the full member list while they're on the Members screen. Settings shows the member count only when the list is loaded.

