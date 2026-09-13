# Marble

A toolkit built for FRC robotics teams: AI-powered inspection and rules checking, a shared battery tracker, and a live Team Stats & Match Center with match alerts.

**[Try it live!](https://mirage54321.github.io/Marble/)**

This is just the README, **[view full documentation here!](https://github.com/mirage54321/Marble/blob/main/DOCUMENTATION.md)**

**[Look at Stardance project!](https://stardance.hackclub.com/projects/16179)**

---

## What it does

Built for a robotics team with limited hands on deck, Marble started as a single AI scanner but has grown into four tools that cover a team's day-to-day needs, from pit-stop checks to competition day logistics:

- **Scan for issues** -> AI vision checks a robot photo for loose or frayed wiring, loose screws, cracked/bent frames, corrosion, and other visible mechanical or electrical problems. Meant to cut down the time it takes to find an issue so your team has more time to actually fix it.
- **Check FRC rules** -> checks your robot photo against the official FRC game manual (2024-2026 supported) for things like bumper compliance, frame perimeter, and wiring rule violations.
- **Battery tracker** -> a shared, team-wide log for tracking which batteries are charged, in use, or flagged as weak, so nobody grabs a dead battery mid-match.
- **Team Stats & Match Center** -> live team info and upcoming matches, a season-wide team rating, an events browser, and a matchup simulator with win probabilities, pulled from The Blue Alliance and the official FRC Events API. Bookmark teams and get push notifications when their matches are coming up, so you don't have to keep checking manually.

How to use it: go to https://mirage54321.github.io/Marble/, pick a tool from the home screen, and go from there: upload a photo for scanning/rules, sign in with a team number for batteries, or browse stats and bookmark teams for match alerts.

## How the AI works

The scanning pipeline runs in two passes instead of one, which is what makes the bounding boxes actually line up with the real issue:

1. **Detection pass** -> the full image is sent to Gemini, which returns a list of findings (title, description, severity) without worrying about exact pixel coordinates yet.
2. **Localization pass** -> for each finding, the AI first picks a rough region of the image (e.g. "bottom-left"), that region gets cropped out and zoomed in, and *then* the AI is asked to find the exact bounding box within that crop. The crop coordinates get mapped back onto the full image.

This two-step approach is more accurate than asking for one big list of exact coordinates in a single pass, especially on a full-size robot photo where a single component is a small fraction of the frame.

The Rules tool works the same way, but also feeds the actual FRC game manual PDF for the selected year into the model alongside the photo, so its answers are grounded in the real rulebook instead of general knowledge.

Both tools also pull from a small database of findings users have flagged as wrong, and pass that context back into the prompt so the AI is less likely to repeat the same mistake twice.

A guided camera also walks you through lighting, tilt, and framing before you scan, so the AI has a clean shot to work with.

## How the battery tracking works

Unlike the two scanning tools, the battery tracker is a persistent, shared log rather than a one-off AI call. Each team's data lives in the cloud so the whole team sees the same up-to-date list.

1. **Team accounts** -> a team registers with a team number and a passcode, which get stored server-side. Anyone on the team can log in with those same credentials to see and update the shared battery list.
2. **Guest mode** -> anyone can view a team's batteries read-only by just entering the team number, no passcode needed. Handy for scouts or other teams checking status without needing real access.
3. **Battery state** -> each battery tracks whether it's currently charging, in use, or available, plus a timestamp for when it was last charged. Charging batteries show a live countdown based on a fixed charge time, so you can tell at a glance which one will be ready soonest.
4. **Flagging** -> any battery can be flagged as weak or unreliable with an optional note (e.g. "died after auto"), and flagged batteries stay visible with their flag history so the team knows to watch out for them.
5. **AI recommendation** -> on request, the app can ask the AI which battery to grab next based on current charge/use state, in addition to the app's own built-in "pick the most-charged available battery" logic.

Team settings also let you view or change your passcode, or wipe all battery data to start fresh for a new competition. As a small bonus, when a team registers, the backend automatically looks up their real team name via the FRC Events API based on the team number, so the team doesn't have to type it in manually.

## How the Match Center works

This is the one non-AI tool in the app, built to give teams a competition-day dashboard without needing AI at all:

1. **My Team** -> shows your own team's info and next match at a glance.
2. **Stats** -> a season-wide team rating calculated by aggregating OPR data across every event a team has played this season, so it works even for events that haven't started yet.
3. **Events** -> browse every FRC event, filter by time or location, and see who's currently live.
4. **Sim** -> a matchup simulator that gives rough win probabilities for upcoming matches based on each team's season-wide rating.

Bookmark any team from around the app to add it to your saved list, then subscribe to get a real browser push notification when one of your bookmarked teams has a match coming up, even if the tab isn't open. Push notifications currently work reliably on desktop browsers and Android; iOS Safari requires the site to be added to the home screen first before push will work at all.

## Tech stack

| Layer | Tech |
|---|---|
| App | Flutter (Dart), deployed to web via GitHub Pages |
| AI | Google Gemini (vision + PDF input) |
| Backend | Node.js (Express) server on Render |
| Database | MongoDB |
| External data | The Blue Alliance API, FRC Events API |
| Notifications | Web Push API, service workers, VAPID |

## AI usage disclosure

I used Gemini as the AI model that powers the scanning, rules checking, and battery recommendation tools. The Team Stats & Match Center doesn't use AI at all, it's built entirely on data from The Blue Alliance and FRC Events APIs. I used Claude to help debug issues and learn how to write parts of the Flutter/Dart code I wasn't familiar with yet, especially UI work, since Flutter had a steep learning curve for me.

## Why I built this

I'm on a robotics team with a small number of people, and I wanted something that could help catch physical problems on the robot faster. What started as one AI tool grew into a broader toolkit once I realized how many other small pains (dead batteries, missed matches, no easy stats) were worth solving too. Plus I wanted a real excuse to work with an AI model end-to-end before starting college.